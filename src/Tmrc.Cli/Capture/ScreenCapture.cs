using System.Runtime.InteropServices;
using Tmrc.Cli.Native;

namespace Tmrc.Cli.Capture;

/// <summary>
/// Captures the primary display via GDI BitBlt. Reports "event" when frame
/// differs from the previous one (pixel diff above threshold) for event-based segmentation.
/// </summary>
public sealed class ScreenCapture : IDisposable
{
    private readonly int _diffThreshold;
    private nint _hWnd;
    private nint _hScreenDc;
    private nint _hMemDc;
    private nint _hBitmap;
    private nint _hOldBitmap;
    private byte[]? _previous;
    private int _width;
    private int _height;
    private bool _disposed;

    public int Width => _width;
    public int Height => _height;

    /// <param name="diffThreshold">Sum of per-pixel absolute differences (scaled) above which we consider the frame an "event". 0 = any change.</param>
    public ScreenCapture(int diffThreshold = 500_000)
    {
        _diffThreshold = diffThreshold;
        _hWnd = GdiNative.GetDesktopWindow();
        _hScreenDc = GdiNative.GetWindowDC(_hWnd);
        if (_hScreenDc == 0)
        {
            throw new InvalidOperationException("GetWindowDC failed.");
        }

        if (!GdiNative.GetWindowRect(_hWnd, out var rect))
        {
            Release();
            throw new InvalidOperationException("GetWindowRect failed.");
        }

        _width = rect.Width;
        _height = rect.Height;
        if (_width <= 0 || _height <= 0)
        {
            Release();
            throw new InvalidOperationException("Invalid capture dimensions.");
        }

        _hMemDc = GdiNative.CreateCompatibleDC(_hScreenDc);
        _hBitmap = GdiNative.CreateCompatibleBitmap(_hScreenDc, _width, _height);
        if (_hMemDc == 0 || _hBitmap == 0)
        {
            Release();
            throw new InvalidOperationException("CreateCompatibleDC/CreateCompatibleBitmap failed.");
        }

        _hOldBitmap = GdiNative.SelectObject(_hMemDc, _hBitmap);
    }

    /// <summary>
    /// Constructor for unit testing that bypasses GDI initialization.
    /// </summary>
    internal ScreenCapture(int diffThreshold, int width, int height)
    {
        _diffThreshold = diffThreshold;
        _width = width;
        _height = height;
    }

    /// <summary>
    /// Captures one frame. Returns (pixels BGRA, hasEvent).
    /// First frame or resolution change is treated as hasEvent.
    /// </summary>
    public (byte[] Bgra, bool HasEvent) CaptureFrame()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(ScreenCapture));
        }

        int w = _width;
        int h = _height;
        int stride = w * 4;
        int size = stride * h;

        if (!GdiNative.BitBlt(_hMemDc, 0, 0, w, h, _hScreenDc, 0, 0, GdiNative.SRCCOPY))
        {
            return (Array.Empty<byte>(), false);
        }

        var bmi = new GdiNative.BITMAPINFO
        {
            bmiHeader = new GdiNative.BITMAPINFOHEADER
            {
                biSize = Marshal.SizeOf<GdiNative.BITMAPINFOHEADER>(),
                biWidth = w,
                biHeight = -h,
                biPlanes = 1,
                biBitCount = 32,
                biCompression = GdiNative.BI_RGB,
                biSizeImage = size
            },
            // BITMAPINFO declares a fixed-length color array (SizeConst = 1),
            // so marshalling requires exactly one element here.
            bmiColors = new int[1]
        };

        var buffer = new byte[size];
        int lines = GdiNative.GetDIBits(_hMemDc, _hBitmap, 0, h, buffer, ref bmi, GdiNative.DIB_RGB_COLORS);
        if (lines <= 0)
        {
            return (Array.Empty<byte>(), false);
        }

        bool hasEvent = ComputeHasEvent(buffer);
        _previous = buffer;
        return (buffer, hasEvent);
    }

    internal bool ComputeHasEvent(byte[] current)
    {
        if (_previous is null || _previous.Length != current.Length)
        {
            return true;
        }

        // Pixel-aligned sampling: step in whole pixels (4 bytes each) so we never
        // mix channels between samples. Target ~2 500 pixels ≈ 10 000 bytes.
        int pixelStep = Math.Max(1, current.Length / 4 / 2_500);
        int byteStep = pixelStep * 4;

        long sum = 0;
        for (int i = 0; i + 3 < current.Length; i += byteStep)
        {
            // Compare only B, G, R channels; skip A (index +3) to avoid
            // GDI alpha-compositing bias on otherwise static frames.
            sum += Math.Abs((int)current[i] - (int)_previous[i]);
            sum += Math.Abs((int)current[i + 1] - (int)_previous[i + 1]);
            sum += Math.Abs((int)current[i + 2] - (int)_previous[i + 2]);
        }

        // Upscale the sampled total to estimate the full-frame difference.
        // No early-exit above, so the sum is never artificially capped before
        // being multiplied.
        sum *= pixelStep;
        return sum >= _diffThreshold;
    }

    /// <summary>
    /// Sets the previous buffer manually for testing purposes.
    /// </summary>
    internal void SetPreviousForTest(byte[]? previous)
    {
        _previous = previous;
    }
    private void Release()
    {
        if (_hOldBitmap != 0 && _hMemDc != 0)
        {
            GdiNative.SelectObject(_hMemDc, _hOldBitmap);
            _hOldBitmap = 0;
        }
        if (_hBitmap != 0)
        {
            GdiNative.DeleteObject(_hBitmap);
            _hBitmap = 0;
        }
        if (_hMemDc != 0)
        {
            GdiNative.DeleteDC(_hMemDc);
            _hMemDc = 0;
        }
        if (_hScreenDc != 0 && _hWnd != 0)
        {
            GdiNative.ReleaseDC(_hWnd, _hScreenDc);
            _hScreenDc = 0;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        Release();
        _disposed = true;
        GC.SuppressFinalize(this);
    }
}
