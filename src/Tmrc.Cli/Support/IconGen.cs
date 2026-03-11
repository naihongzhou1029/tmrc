using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace Tmrc.Cli.Support;

public static class IconGen
{
    public static void GenerateIconIfMissing(string path)
    {
        if (File.Exists(path)) return;

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        using var bitmap = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        // Clock face (Blue circle)
        using var brush = new SolidBrush(Color.FromArgb(255, 60, 120, 216)); // Blue
        g.FillEllipse(brush, 2, 2, 28, 28);
        using var pen = new Pen(Color.White, 2);
        g.DrawEllipse(pen, 2, 2, 28, 28);

        // Clock hands (12:15)
        g.DrawLine(pen, 16, 16, 16, 7); // 12
        g.DrawLine(pen, 16, 16, 25, 16); // 3

        // Play button (Triangle)
        // Draw a small triangle in the middle to represent "video player"
        Point[] triangle = {
            new Point(13, 11),
            new Point(13, 21),
            new Point(21, 16)
        };
        g.FillPolygon(Brushes.White, triangle);

        // Save as Icon
        try
        {
            var iconHandle = bitmap.GetHicon();
            using var icon = Icon.FromHandle(iconHandle);
            using var fs = new FileStream(path, FileMode.Create);
            icon.Save(fs);
        }
        catch { }
    }
}
