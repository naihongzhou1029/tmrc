using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using Tmrc.Core.Config;
using Tmrc.Core.Storage;

namespace Tmrc.Cli.Support;

public sealed class TrayIconManager : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly TmrcConfig _config;
    private readonly StorageManager _storage;
    private readonly Action _stopAction;
    private readonly Func<string> _statusProvider;
    private Thread? _messageLoopThread;

    public TrayIconManager(TmrcConfig config, StorageManager storage, Action stopAction, Func<string> statusProvider)
    {
        _config = config;
        _storage = storage;
        _stopAction = stopAction;
        _statusProvider = statusProvider;

        _icon = new NotifyIcon();
    }

    public void Start()
    {
        _messageLoopThread = new Thread(() =>
        {
            var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app.ico");

            if (File.Exists(iconPath))
            {
                try
                {
                    _icon.Icon = new Icon(iconPath);
                }
                catch
                {
                    _icon.Icon = SystemIcons.Application;
                }
            }
            else
            {
                _icon.Icon = SystemIcons.Application;
            }

            _icon.Text = "tmrc - Recording";
            _icon.Visible = true;

            var menu = new ContextMenuStrip();
            menu.Items.Add("Status", null, (s, e) => ShowStatus());
            menu.Items.Add("Open Storage Folder", null, (s, e) => OpenStorage());
            menu.Items.Add("-");
            menu.Items.Add("Stop Recording", null, (s, e) => _stopAction());

            _icon.ContextMenuStrip = menu;
            _icon.DoubleClick += (s, e) => ShowStatus();

            Application.Run();
        });

        _messageLoopThread.SetApartmentState(ApartmentState.STA);
        _messageLoopThread.IsBackground = true;
        _messageLoopThread.Start();
    }

    private void ShowStatus()
    {
        MessageBox.Show(_statusProvider(), "tmrc Status", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private void OpenStorage()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{_storage.StorageRoot}\"",
                UseShellExecute = true
            });
        }
        catch { }
    }

    public void Dispose()
    {
        if (_icon.Visible)
        {
            _icon.Visible = false;
        }

        Application.Exit();

        _icon.Dispose();
    }
}
