using Tmrc.Cli.Native;
using Xunit;

namespace Tmrc.Tests;

public class WindowsSessionStateTests
{
    private static readonly object EnvLock = new();

    [Theory]
    [InlineData("Default", true)]
    [InlineData("default", true)]
    [InlineData("Winlogon", false)]
    [InlineData("winlogon", false)]
    [InlineData("Screen-saver", false)]
    public void InteractiveDesktopName_IsClassifiedCorrectly(string desktopName, bool expectedInteractive)
    {
        Assert.Equal(expectedInteractive, WindowsSessionState.IsInteractiveDesktopName(desktopName));
    }

    [Theory]
    [InlineData(0, true)]  // WTSActive
    [InlineData(1, false)] // WTSConnected
    [InlineData(4, false)] // WTSDisconnected
    [InlineData(6, false)] // WTSListen
    [InlineData(7, false)] // WTSReset
    public void ConnectState_IsClassifiedCorrectly(int state, bool expectedInteractive)
    {
        Assert.Equal(expectedInteractive, WindowsSessionState.IsInteractiveConnectState(state));
    }

    [Theory]
    [InlineData("1", true, true)]
    [InlineData("interactive", true, true)]
    [InlineData("locked", true, false)]
    [InlineData("logoff", true, false)]
    [InlineData("nope", false, false)]
    [InlineData("", false, false)]
    [InlineData(null, false, false)]
    public void EnvironmentOverride_ParsesSupportedValues(string? raw, bool expectedParsed, bool expectedInteractive)
    {
        var parsed = WindowsSessionState.TryParseForcedInteractiveFromEnvironment(raw, out var interactive);
        Assert.Equal(expectedParsed, parsed);
        Assert.Equal(expectedInteractive, interactive);
    }

    [Theory]
    [InlineData("locked", false)]
    [InlineData("logoff", false)]
    [InlineData("interactive", true)]
    [InlineData("active", true)]
    public void EnvironmentOverride_DrivesInteractiveStateCheck(string forcedState, bool expectedInteractive)
    {
        lock (EnvLock)
        {
            var original = Environment.GetEnvironmentVariable("TMRC_TEST_WINDOWS_SESSION_INTERACTIVE");
            try
            {
                Environment.SetEnvironmentVariable("TMRC_TEST_WINDOWS_SESSION_INTERACTIVE", forcedState);
                Assert.Equal(expectedInteractive, WindowsSessionState.IsInteractiveDesktop());
            }
            finally
            {
                Environment.SetEnvironmentVariable("TMRC_TEST_WINDOWS_SESSION_INTERACTIVE", original);
            }
        }
    }
}
