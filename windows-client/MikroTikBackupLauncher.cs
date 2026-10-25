using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class Program
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    private const uint WM_SETICON = 0x0080;
    private const int ICON_SMALL = 0;
    private const int ICON_BIG = 1;
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x0010;

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr LoadImage(IntPtr hInst, string name, uint type, int cx, int cy, uint fuLoad);

    [STAThread]
    private static int Main()
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(folder, "Generate-MikroTik-Backup.ps1");
        string iconPath = Path.Combine(folder, "AmirTaheri-Backup.ico");
        Console.Title = "Amir Taheri | MikroTik Backup Studio";
        TrySetConsoleIcon(iconPath);
        Console.ForegroundColor = ConsoleColor.DarkCyan;
        Console.WriteLine("  ============================================================");
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("       MIKROTIK BACKUP STUDIO  |  ROUTEROS 7");
        Console.ForegroundColor = ConsoleColor.White;
        Console.WriteLine("                    Created by Amir Taheri");
        Console.ForegroundColor = ConsoleColor.Magenta;
        Console.WriteLine("                    Orax Tech Solutions LLC");
        Console.ForegroundColor = ConsoleColor.Gray;
        Console.WriteLine("                    Contact: +989347682358");
        Console.ForegroundColor = ConsoleColor.DarkCyan;
        Console.WriteLine("  ============================================================");
        Console.ResetColor();
        Console.WriteLine();
        if (!File.Exists(script))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("ERROR: Generate-MikroTik-Backup.ps1 was not found.");
            Console.ResetColor();
            Console.WriteLine("Keep the EXE and PS1 in the same folder.");
            Pause();
            return 2;
        }
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe");
        if (!File.Exists(psi.FileName)) psi.FileName = "powershell.exe";
        psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
        psi.WorkingDirectory = folder;
        psi.UseShellExecute = false;
        try
        {
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                Console.WriteLine();
                Console.ForegroundColor = p.ExitCode == 0 ? ConsoleColor.Green : ConsoleColor.Red;
                Console.WriteLine(p.ExitCode == 0 ? "  Completed. Check the generated-output folder." : "  Finished with an error. Read the message above.");
                Console.ResetColor();
                Console.WriteLine("  Created by Amir Taheri | Orax Tech Solutions LLC | +989347682358");
                Pause();
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("Could not start PowerShell: " + ex.Message);
            Console.ResetColor();
            Pause();
            return 3;
        }
    }
    private static void Pause()
    {
        Console.WriteLine();
        Console.Write("Press any key to exit...");
        Console.ReadKey();
    }
    private static void TrySetConsoleIcon(string path)
    {
        try
        {
            if (!File.Exists(path)) return;
            IntPtr h = GetConsoleWindow();
            if (h == IntPtr.Zero) return;
            IntPtr icon = LoadImage(IntPtr.Zero, path, IMAGE_ICON, 0, 0, LR_LOADFROMFILE);
            if (icon != IntPtr.Zero)
            {
                SendMessage(h, WM_SETICON, new IntPtr(ICON_BIG), icon);
                SendMessage(h, WM_SETICON, new IntPtr(ICON_SMALL), icon);
            }
        }
        catch { }
    }
}