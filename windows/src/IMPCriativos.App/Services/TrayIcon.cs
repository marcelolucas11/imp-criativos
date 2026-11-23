using IMPCriativos.Core.Models;
using IMPCriativos.Core.Updates;
using WinForms = System.Windows.Forms;

namespace IMPCriativos.App.Services;

/// <summary>Ícone na bandeja (modo segundo plano), com o mesmo menu da barra de menus do Mac (<c>MenuBarView.swift</c>).</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly App _app;
    private readonly WinForms.NotifyIcon _icon;

    public TrayIcon(App app)
    {
        _app = app;
        _icon = new WinForms.NotifyIcon { Text = "IMP Criativos" };
        try
        {
            using var s = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Resources/AppIcon.ico"))?.Stream;
            if (s != null) _icon.Icon = new System.Drawing.Icon(s, 16, 16);
        }
        catch { }
        _icon.ContextMenuStrip = new WinForms.ContextMenuStrip();
        _icon.ContextMenuStrip.Opening += (_, _) => Build();
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) _app.Dispatcher.Invoke(() => _app.ShowMain()); };
        Build();
    }

    public bool Visible
    {
        get => _icon.Visible;
        set => _icon.Visible = value;
    }

    public void Balloon(string title, string body)
    {
        var wasVisible = _icon.Visible;
        _icon.Visible = true;
        _icon.ShowBalloonTip(5000, title, body, WinForms.ToolTipIcon.Info);
        if (!wasVisible) Task.Delay(6000).ContinueWith(_ => _app.Dispatcher.Invoke(() => _icon.Visible = AppModel.Shared.Settings.RunInBackground));
    }

    /// <summary>Itens do menu, na ordem do Mac (exposto para o teste de fumaça).</summary>
    public static List<(string Text, Action? Action)> Items(App app)
    {
        var model = AppModel.Shared;
        var jobs = model.Jobs.Jobs;
        var active = jobs.Where(j => j.State == JobState.Running).ToList();
        var inReview = jobs.Where(j => j.State == JobState.Review).ToList();
        var items = new List<(string, Action?)> { ($"IMP Criativos {AppInfo.Version}", null), ("-", null) };
        if (active.Count == 0) items.Add(("Nenhum lote em andamento", null));
        foreach (var job in active)
        {
            var id = job.Id;
            items.Add(($"{job.Name} — {job.FinishedSteps}/{job.TotalSteps} ({(int)(job.Progress * 100)}%)", () => app.ShowMain(new SidebarItem.JobItem(id))));
        }
        if (inReview.Count > 0) items.Add(($"{inReview.Count} lote(s) aguardando revisão", null));
        items.Add(("-", null));
        items.Add(("Abrir IMP Criativos", () => app.ShowMain()));
        items.Add(("Novo lote", () => app.ShowMain(new SidebarItem.NewJob())));
        items.Add(("Limpar logo", () => app.ShowMain(new SidebarItem.CleanOnly())));
        items.Add(("Otimizador em Lote (Stories 9:16)", () => app.ShowMain(new SidebarItem.StoryOptimizer())));
        if (active.Count > 0) items.Add(("Pausar todos os lotes", () => model.Runner.PauseAll()));
        var failures = jobs.Where(j => j.State != JobState.Cancelled).Sum(j => j.FailureCount);
        if (failures > 0) items.Add(($"Tentar falhas de novo em todos os lotes ({failures})", () => model.Runner.RetryAllFailed()));
        items.Add(("Histórico…", () => app.ShowMain(new SidebarItem.Logs())));
        items.Add(("-", null));
        if (model.Updater.AvailableRelease is ReleaseInfo r)
            items.Add(($"Instalar versão {r.Version}…", () => app.ShowMain(new SidebarItem.Settings())));
        else
            items.Add(("Buscar atualização", () => _ = model.Updater.Check(model.Settings.IncludeBetaUpdates)));
        items.Add(("Configurações…", () => app.ShowMain(new SidebarItem.Settings())));
        items.Add(("-", null));
        items.Add(("Sair do IMP Criativos", () => app.Quit()));
        return items;
    }

    private void Build()
    {
        var menu = _icon.ContextMenuStrip!;
        menu.Items.Clear();
        foreach (var (text, action) in Items(_app))
        {
            if (text == "-") { menu.Items.Add(new WinForms.ToolStripSeparator()); continue; }
            var item = new WinForms.ToolStripMenuItem(text) { Enabled = action != null };
            if (action != null) item.Click += (_, _) => _app.Dispatcher.Invoke(action);
            menu.Items.Add(item);
        }
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
