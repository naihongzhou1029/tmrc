using System.Runtime.InteropServices;

namespace Tmrc.Cli.Native;

internal static class WindowsSessionState
{
    private const uint DESKTOP_READOBJECTS = 0x0001;
    private const uint DESKTOP_SWITCHDESKTOP = 0x0100;
    private const int UOI_NAME = 2;

    /// <summary>
    /// Returns true when the active input desktop is the interactive user desktop.
    /// On lock screen this is typically "Winlogon", which is treated as non-interactive.
    /// </summary>
    public static bool IsInteractiveDesktop()
    {
        var desktop = OpenInputDesktop(0, false, DESKTOP_READOBJECTS | DESKTOP_SWITCHDESKTOP);
        if (desktop == 0)
        {
            // Do not block recording on API access failure.
            // We only pause when lock state is positively detected.
            return true;
        }

        try
        {
            if (!TryGetDesktopName(desktop, out var name) || string.IsNullOrWhiteSpace(name))
            {
                return true;
            }

            return !string.Equals(name, "Winlogon", StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            CloseDesktop(desktop);
        }
    }

    private static bool TryGetDesktopName(nint desktop, out string? name)
    {
        name = null;
        if (!GetUserObjectInformation(desktop, UOI_NAME, nint.Zero, 0, out var bytesNeeded) || bytesNeeded <= 0)
        {
            return false;
        }

        var buffer = Marshal.AllocHGlobal(bytesNeeded);
        try
        {
            if (!GetUserObjectInformation(desktop, UOI_NAME, buffer, bytesNeeded, out _))
            {
                return false;
            }

            name = Marshal.PtrToStringUni(buffer);
            return true;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseDesktop(nint hDesktop);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool GetUserObjectInformation(
        nint hObj,
        int nIndex,
        nint pvInfo,
        int nLength,
        out int lpnLengthNeeded);
}
