using System.Windows;
using System.Windows.Threading;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Story;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App;

/// <summary>Ciclo de vida: instância única, segundo plano na bandeja, confirmação ao sair.</summary>
public sealed class App : Application
{
    public static App Instance => (App)Current;

    public MainWindow? Main { get; private set; }
    public TrayIcon? Tray { get; private set; }
    /// <summary>Saindo de verdade (Sair do menu ou atualização), não só fechando a janela.</summary>
    public bool Quitting { get; private set; }
    public static bool SkipQuitConfirmation { get; set; }

    internal SingleInstance? _single;

    /// <summary>Liga os serviços do Windows no Core (OCR, HEIC, notificações, risco de bateria).</summary>
    public static void ConfigureServices()
    {
        LocalOCR.Reader = new WindowsOcr();
        ImageTools.Extension = new WicDecoder();
        Notifier.Handler = Toast.Post;
        SpeedMonitor.ExtraRisk = PowerRisk.Check;
        StoryBatch.AppIsActive = () => Current?.Dispatcher.Invoke(() => Current.Windows.OfType<Window>().Any(w => w.IsActive)) ?? false;
    }

    public void Boot(bool showWindow)
    {
        ThemeMode = ThemeMode.Dark;
        Theme.Apply(this);
        ConfigureServices();
        DispatcherUnhandledException += (_, e) =>
        {
            AppLog.Error(LogCategory.Sistema, $"Erro inesperado na tela: {e.Exception.Message}", details: e.Exception.ToString());
            e.Handled = true;
        };

        var model = AppModel.Shared;
        model.Updater.QuitForUpdate = () => Dispatcher.Invoke(() =>
        {
            SkipQuitConfirmation = true;
            Quit();
        });
        AppLog.Info(LogCategory.Sistema, $"IMP Criativos {AppInfo.Version} aberto.",
            details: $"Windows {Environment.OSVersion.Version} · OCR: {LocalOCR.Reader?.Description ?? "indisponível"} · JPEG: {(TurboJpeg.Available ? "libjpeg-turbo" : "Skia")}");
        model.Settings.ApplySpeed();

        Tray = new TrayIcon(this);
        Tray.Visible = model.Settings.RunInBackground;
        model.Settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(model.Settings.RunInBackground)) Dispatcher.Invoke(() => Tray.Visible = model.Settings.RunInBackground);
        };
        Toast.Fallback = (t, b) => Dispatcher.BeginInvoke(() => Tray?.Balloon(t, b));

        _single?.Listen(() => Dispatcher.BeginInvoke(() => ShowMain()));

        if (showWindow || !model.Settings.RunInBackground) ShowMain();

        model.Runner.ResumeInterrupted();
        if (model.Settings.CheckUpdatesOnLaunch)
        {
            var beta = model.Settings.IncludeBetaUpdates;
            _ = model.Updater.Check(beta, silent: true);
        }
        _ = ModelCatalog.Shared.RefreshIfStale();
    }

    public void ShowMain(SidebarItem? item = null)
    {
        if (item != null) AppModel.Shared.Selection = item;
        if (Main == null)
        {
            Main = new MainWindow();
            Main.Closed += (_, _) => Main = null;
        }
        Main.Show();
        if (Main.WindowState == WindowState.Minimized) Main.WindowState = WindowState.Normal;
        Main.Activate();
    }

    /// <summary>
    /// Com "Continuar em segundo plano" ligado, fechar a janela não encerra o app (fica na bandeja).
    /// Devolve true se a janela pode fechar.
    /// </summary>
    public bool OnMainClosing()
    {
        if (Quitting) return true;
        if (AppModel.Shared.Settings.RunInBackground) return true;
        return Quit();
    }

    /// <summary>Sai do app, com a mesma confirmação do Mac quando há lote rodando. Devolve false se o usuário cancelou.</summary>
    public bool Quit()
    {
        var model = AppModel.Shared;
        if (!SkipQuitConfirmation && model.Runner.HasActiveWork)
        {
            const string text = "Se sair agora, o lote para e é retomado de onde parou na próxima vez que você abrir o IMP Criativos.";
            const string title = "Há um lote em andamento";
            var r = Main != null
                ? MessageBox.Show(Main, text, title, MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel)
                : MessageBox.Show(text, title, MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
            if (r != MessageBoxResult.OK) return false;
        }
        Quitting = true;
        // os passos interrompidos voltam para "pendente" na próxima abertura (o job.json é salvo a cada passo)
        _ = model.Runner.WaitIdle(TimeSpan.FromSeconds(3));
        Tray?.Dispose();
        Main?.Close();
        Shutdown();
        return true;
    }
}
