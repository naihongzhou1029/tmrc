using System.Runtime.InteropServices;

namespace Tmrc.Cli.Native;

internal static class WindowsSessionState
{
    private const uint DESKTOP_READOBJECTS = 0x0001;
    private const uint DESKTOP_SWITCHDESKTOP = 0x0100;
    private const int UOI_NAME = 2;
    private static readonly nint WTS_CURRENT_SERVER_HANDLE = nint.Zero;

    /// <summary>
    /// Returns true only when both the current Windows session and input desktop
    /// are interactive for the logged-in user.
    /// </summary>
    public static bool IsInteractiveDesktop()
    {
        if (TryParseForcedInteractiveFromEnvironment(
            Environment.GetEnvironmentVariable("TMRC_TEST_WINDOWS_SESSION_INTERACTIVE"),
            out var forcedInteractive))
        {
            return forcedInteractive;
        }

        // Fail closed: when we cannot verify interactivity, treat as non-interactive
        // to satisfy "do not record while locked/logged out" by default.
        if (!TryIsCurrentSessionActive(out var isSessionActive) || !isSessionActive)
        {
            return false;
        }

        var desktop = OpenInputDesktop(0, false, DESKTOP_READOBJECTS | DESKTOP_SWITCHDESKTOP);
        if (desktop == 0)
        {
            return false;
        }

        try
        {
            if (!TryGetDesktopName(desktop, out var name) || string.IsNullOrWhiteSpace(name))
            {
                return false;
            }

            return IsInteractiveDesktopName(name);
        }
        finally
        {
            CloseDesktop(desktop);
        }
    }

    internal static bool IsInteractiveDesktopName(string name) =>
        !string.Equals(name, "Winlogon", StringComparison.OrdinalIgnoreCase) &&
        !string.Equals(name, "Screen-saver", StringComparison.OrdinalIgnoreCase);

    internal static bool IsInteractiveConnectState(int state) => state == (int)WTS_CONNECTSTATE_CLASS.WTSActive;

    internal static bool TryParseForcedInteractiveFromEnvironment(string? raw, out bool isInteractive)
    {
        isInteractive = false;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        var normalized = raw.Trim().ToLowerInvariant();
        switch (normalized)
        {
            case "1":
            case "true":
            case "active":
            case "interactive":
            case "unlocked":
                isInteractive = true;
                return true;
            case "0":
            case "false":
            case "locked":
            case "logoff":
            case "logged_out":
            case "disconnected":
                isInteractive = false;
                return true;
            default:
                return false;
        }
    }

    private static bool TryIsCurrentSessionActive(out bool isActive)
    {
        isActive = false;
        var sessionId = System.Diagnostics.Process.GetCurrentProcess().SessionId;

        if (!WTSQuerySessionInformation(
            WTS_CURRENT_SERVER_HANDLE,
            sessionId,
            WTS_INFO_CLASS.WTSConnectState,
            out var buffer,
            out var bytesReturned))
        {
            return false;
        }

        try
        {
            if (buffer == 0 || bytesReturned < sizeof(int))
            {
                return false;
            }

            var connectState = Marshal.ReadInt32(buffer);
            isActive = IsInteractiveConnectState(connectState);
            return true;
        }
        finally
        {
            WTSFreeMemory(buffer);
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

    [DllImport("Wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSQuerySessionInformation(
        nint hServer,
        int sessionId,
        WTS_INFO_CLASS wtsInfoClass,
        out nint ppBuffer,
        out int pBytesReturned);

    [DllImport("Wtsapi32.dll")]
    private static extern void WTSFreeMemory(nint pMemory);

    private enum WTS_INFO_CLASS
    {
        WTSConnectState = 8
    }

    private enum WTS_CONNECTSTATE_CLASS
    {
        WTSActive = 0
    }
}
