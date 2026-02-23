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

    private bool ComputeHasEvent(byte[] current)
    {
        if (_previous is null || _previous.Length != current.Length)
        {
            return true;
        }

        long sum = 0;
        int step = Math.Max(1, current.Length / 10_000);
        for (int i = 0; i < current.Length && sum < _diffThreshold; i += step)
        {
            sum += Math.Abs((int)current[i] - (int)_previous[i]);
        }

        sum = sum * (current.Length / Math.Max(1, step));
        return sum >= _diffThreshold;
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
