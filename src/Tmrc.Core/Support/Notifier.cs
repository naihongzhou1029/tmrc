using System;

namespace Tmrc.Core.Support;

public interface INotifier
{
    void Toast(string title, string message);
}

public sealed class NoopNotifier : INotifier
{
    public void Toast(string title, string message)
    {
        // Windows toast integration to be implemented later.
        Console.Error.WriteLine($"[toast] {title}: {message}");
    }
}

