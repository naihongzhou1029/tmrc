using System.Reflection;

namespace Tmrc.Core.Support;

public static class TmrcVersion
{
    public static string Current
    {
        get
        {
            var assembly = Assembly.GetEntryAssembly() ?? typeof(TmrcVersion).Assembly;
            var version = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            
            // 如果沒讀到（例如直接執行 dll），則回傳預設開發版本
            return !string.IsNullOrEmpty(version) ? version : "0.1.0-windows-dev";
        }
    }
}

