using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Dreynox.Shaiya.CleanClient;

internal sealed class MainForm : Form
{
    private const string AppHost = "app.shaiya.local";
    private const string DataHost = "data.shaiya.local";

    private readonly WebView2 _web = new();
    private readonly ToolStripStatusLabel _status = new("Inicializando cliente limpio…");
    private readonly string[] _args;
    private readonly string _stateRoot;
    private readonly string _settingsPath;
    private readonly string _logsRoot;
    private string _dataPath = "";
    private bool _fullScreen;
    private FormBorderStyle _oldBorder;
    private FormWindowState _oldState;

    private sealed record Settings(string? DataPath, bool FullScreen = false);

    public MainForm(string[] args)
    {
        _args = args;
        _stateRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Dreynox", "ShaiyaCleanClient");
        _settingsPath = Path.Combine(_stateRoot, "settings.json");
        _logsRoot = Path.Combine(_stateRoot, "logs");

        Text = "Dreynox Shaiya Clean Client 0.1 · Offline";
        BackColor = Color.FromArgb(13, 16, 22);
        ForeColor = Color.Gainsboro;
        MinimumSize = new Size(960, 640);
        Size = new Size(1440, 900);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;

        var menu = BuildMenu();
        var statusBar = new StatusStrip
        {
            BackColor = Color.FromArgb(20, 24, 31),
            ForeColor = Color.Gainsboro,
            SizingGrip = false
        };
        statusBar.Items.Add(_status);

        _web.Dock = DockStyle.Fill;
        _web.BackColor = Color.Black;
        _web.DefaultBackgroundColor = Color.Black;

        Controls.Add(_web);
        Controls.Add(statusBar);
        Controls.Add(menu);
        MainMenuStrip = menu;

        Load += async (_, _) => await InitializeAsync();
        FormClosing += (_, _) => SaveSettings();
        KeyDown += OnKeyDown;
    }

    private MenuStrip BuildMenu()
    {
        var menu = new MenuStrip
        {
            BackColor = Color.FromArgb(20, 24, 31),
            ForeColor = Color.Gainsboro,
            Renderer = new ToolStripProfessionalRenderer(new DarkColorTable())
        };

        var file = new ToolStripMenuItem("Archivo");
        file.DropDownItems.Add("Seleccionar DATA_Español…", null, async (_, _) => await SelectDataAndReloadAsync());
        file.DropDownItems.Add("Abrir carpeta de guardados", null, (_, _) => OpenPath(_stateRoot));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add("Salir", null, (_, _) => Close());

        var view = new ToolStripMenuItem("Vista");
        view.DropDownItems.Add("Pantalla completa   F11", null, (_, _) => ToggleFullScreen());
        view.DropDownItems.Add("Recargar renderer   Ctrl+R", null, (_, _) => _web.CoreWebView2?.Reload());
        view.DropDownItems.Add("Herramientas de desarrollo   F12", null, (_, _) => _web.CoreWebView2?.OpenDevToolsWindow());

        var help = new ToolStripMenuItem("Cliente");
        help.DropDownItems.Add("Estado", null, (_, _) =>
            MessageBox.Show(
                "Dreynox Shaiya Clean Client 0.1\n\n" +
                "Modo actual: Offline local\n" +
                "Renderer: WebGL 2 sobre WebView2\n" +
                "Recursos: DATA_Español original, lectura directa\n" +
                "Sin VMProtect · Sin anti-VM · Sin game.exe\n\n" +
                "F11: pantalla completa\nCtrl+R: recargar\nF12: depuración",
                "Cliente limpio", MessageBoxButtons.OK, MessageBoxIcon.Information));

        menu.Items.Add(file);
        menu.Items.Add(view);
        menu.Items.Add(help);
        return menu;
    }

    private async Task InitializeAsync()
    {
        try
        {
            Directory.CreateDirectory(_stateRoot);
            Directory.CreateDirectory(_logsRoot);

            var settings = LoadSettings();
            _dataPath = ResolveDataPath(settings?.DataPath);
            if (string.IsNullOrWhiteSpace(_dataPath))
            {
                if (!TrySelectData(out _dataPath))
                {
                    MessageBox.Show(
                        "El cliente limpio necesita la carpeta DATA_Español o DATA que contenga character, world e interface.",
                        "DATA requerido", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    Close();
                    return;
                }
            }

            var appRoot = Path.Combine(AppContext.BaseDirectory, "app");
            if (!File.Exists(Path.Combine(appRoot, "index.html")))
                throw new FileNotFoundException("Falta app\\index.html. Extrae el paquete completo.");

            var userData = Path.Combine(_stateRoot, "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(null, userData);
            await _web.EnsureCoreWebView2Async(environment);

            var core = _web.CoreWebView2 ?? throw new InvalidOperationException("WebView2 no pudo inicializarse.");
            core.SetVirtualHostNameToFolderMapping(AppHost, appRoot, CoreWebView2HostResourceAccessKind.Allow);
            MapData(core, _dataPath);

            core.Settings.AreDevToolsEnabled = true;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = true;
            core.Settings.AreBrowserAcceleratorKeysEnabled = true;

            var hostInfo = JsonSerializer.Serialize(new
            {
                version = "0.1.0",
                mode = "offline",
                dataPath = _dataPath,
                cleanClient = true,
                vmProtect = false,
                antiVm = false
            });
            await core.AddScriptToExecuteOnDocumentCreatedAsync(
                $"window.__DREYNOX_NATIVE__={hostInfo};");

            core.WebMessageReceived += CoreOnWebMessageReceived;
            core.NavigationCompleted += (_, e) =>
            {
                _status.Text = e.IsSuccess
                    ? $"DATA: {_dataPath} · Cliente limpio listo"
                    : $"Error de navegación WebView2: {e.WebErrorStatus}";
            };
            core.ProcessFailed += (_, e) => Log($"WebView2 process failed: {e.ProcessFailedKind}");

            _status.Text = $"Cargando DATA: {_dataPath}";
            core.Navigate($"https://{AppHost}/index.html");

            if (settings?.FullScreen == true)
                ToggleFullScreen();
        }
        catch (Exception ex)
        {
            Log(ex.ToString());
            MessageBox.Show(
                ex.Message + "\n\nRegistro: " + Path.Combine(_logsRoot, "clean-client.log"),
                "No se pudo iniciar el cliente limpio",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    private static void MapData(CoreWebView2 core, string path)
    {
        try { core.ClearVirtualHostNameToFolderMapping(DataHost); } catch { }
        core.SetVirtualHostNameToFolderMapping(DataHost, path, CoreWebView2HostResourceAccessKind.Allow);
    }

    private void CoreOnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var root = doc.RootElement;
            var type = root.TryGetProperty("type", out var t) ? t.GetString() : null;
            switch (type)
            {
                case "ready":
                    _status.Text = $"Offline · {_dataPath}";
                    break;
                case "chooseData":
                    BeginInvoke(async () => await SelectDataAndReloadAsync());
                    break;
                case "fullscreen":
                    BeginInvoke(ToggleFullScreen);
                    break;
                case "quit":
                    BeginInvoke(Close);
                    break;
                case "log":
                    if (root.TryGetProperty("message", out var m)) Log(m.GetString() ?? "");
                    break;
            }
        }
        catch (Exception ex)
        {
            Log("Web message error: " + ex);
        }
    }

    private async Task SelectDataAndReloadAsync()
    {
        if (!TrySelectData(out var chosen)) return;
        _dataPath = chosen;
        SaveSettings();

        if (_web.CoreWebView2 is { } core)
        {
            MapData(core, _dataPath);
            await core.ExecuteScriptAsync(
                $"window.__DREYNOX_NATIVE__.dataPath={JsonSerializer.Serialize(_dataPath)};");
            core.Reload();
        }
    }

    private bool TrySelectData(out string selected)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Selecciona DATA_Español / DATA (debe contener character, world e interface)",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = false,
            InitialDirectory = Directory.Exists(_dataPath) ? _dataPath : ""
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            selected = "";
            return false;
        }

        var path = Path.GetFullPath(dialog.SelectedPath);
        if (!ValidateData(path, out var error))
        {
            MessageBox.Show(error, "DATA no compatible", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            selected = "";
            return false;
        }
        selected = path;
        return true;
    }

    private string ResolveDataPath(string? saved)
    {
        var arg = _args.FirstOrDefault(a => a.StartsWith("--data=", StringComparison.OrdinalIgnoreCase));
        var candidates = new[]
        {
            arg is null ? null : arg[7..].Trim('"'),
            saved,
            Path.Combine(AppContext.BaseDirectory, "DATA_Español"),
            Path.Combine(AppContext.BaseDirectory, "DATA"),
            Path.Combine(Directory.GetParent(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar))?.FullName ?? "", "DATA_Español")
        };

        foreach (var c in candidates)
        {
            if (string.IsNullOrWhiteSpace(c)) continue;
            try
            {
                var p = Path.GetFullPath(c);
                if (ValidateData(p, out _)) return p;
            }
            catch { }
        }
        return "";
    }

    private static bool ValidateData(string path, out string error)
    {
        if (!Directory.Exists(path))
        {
            error = "La carpeta seleccionada no existe.";
            return false;
        }
        string? Find(string name) => Directory.EnumerateDirectories(path)
            .FirstOrDefault(x => string.Equals(Path.GetFileName(x), name, StringComparison.OrdinalIgnoreCase));

        var character = Find("character");
        var world = Find("world");
        var inter = Find("interface");
        if (character is null || world is null || inter is null)
        {
            error = "Esa carpeta no parece ser DATA de Shaiya. Debe contener character, world e interface.";
            return false;
        }
        error = "";
        return true;
    }

    private Settings? LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return null;
            return JsonSerializer.Deserialize<Settings>(File.ReadAllText(_settingsPath));
        }
        catch (Exception ex)
        {
            Log("Settings read: " + ex.Message);
            return null;
        }
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(_stateRoot);
            File.WriteAllText(_settingsPath,
                JsonSerializer.Serialize(new Settings(_dataPath, _fullScreen),
                    new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) { Log("Settings write: " + ex.Message); }
    }

    private void ToggleFullScreen()
    {
        if (!_fullScreen)
        {
            _oldBorder = FormBorderStyle;
            _oldState = WindowState;
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
            MainMenuStrip!.Visible = false;
            _fullScreen = true;
        }
        else
        {
            MainMenuStrip!.Visible = true;
            FormBorderStyle = _oldBorder;
            WindowState = _oldState;
            _fullScreen = false;
        }
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.F11)
        {
            ToggleFullScreen();
            e.Handled = true;
        }
        else if (e.KeyCode == Keys.F12)
        {
            _web.CoreWebView2?.OpenDevToolsWindow();
            e.Handled = true;
        }
        else if (e.Control && e.KeyCode == Keys.R)
        {
            _web.CoreWebView2?.Reload();
            e.Handled = true;
        }
        else if (e.KeyCode == Keys.Escape && _fullScreen)
        {
            ToggleFullScreen();
            e.Handled = true;
        }
    }

    private static void OpenPath(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }

    private void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(_logsRoot);
            File.AppendAllText(Path.Combine(_logsRoot, "clean-client.log"),
                $"[{DateTimeOffset.Now:O}] {message}{Environment.NewLine}");
        }
        catch { }
    }

    private sealed class DarkColorTable : ProfessionalColorTable
    {
        public override Color MenuItemSelected => Color.FromArgb(48, 55, 68);
        public override Color MenuItemBorder => Color.FromArgb(78, 86, 101);
        public override Color MenuBorder => Color.FromArgb(55, 61, 73);
        public override Color ToolStripDropDownBackground => Color.FromArgb(24, 28, 36);
        public override Color ImageMarginGradientBegin => Color.FromArgb(24, 28, 36);
        public override Color ImageMarginGradientMiddle => Color.FromArgb(24, 28, 36);
        public override Color ImageMarginGradientEnd => Color.FromArgb(24, 28, 36);
    }
}
