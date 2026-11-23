using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IMPCriativos.App.UI;
using IMPCriativos.App.Views;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Updates;

using Page = IMPCriativos.App.Views.Page;

namespace IMPCriativos.App;

/// <summary>Janela principal: menu lateral (mesma ordem do Mac) + tela escolhida.</summary>
public sealed class MainWindow : Window
{
    private readonly AppModel _model = AppModel.Shared;
    private readonly StackPanel _sidebar = new();
    private readonly ContentControl _content = new();
    private SidebarItem? _shown;
    private Page? _page;

    public MainWindow()
    {
        Title = "IMP Criativos";
        Width = 1240;
        Height = 800;
        MinWidth = 1020;
        MinHeight = 680;
        Background = Brand.Background;
        Foreground = Brand.Text;
        FontFamily = U.Font;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        try { Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Resources/AppIcon.ico")); } catch { }

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var side = new Border
        {
            Background = Brand.Sidebar,
            BorderBrush = Brand.Stroke,
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _sidebar },
        };
        grid.Children.Add(side);
        Grid.SetColumn(_content, 1);
        grid.Children.Add(_content);
        Content = grid;

        // atalhos: ⌘ vira Ctrl (⌘, ⌘N, ⇧⌘L, ⇧⌘O)
        InputBindings.Add(new KeyBinding(new Relay(() => _model.Selection = new SidebarItem.Settings()), Key.OemComma, ModifierKeys.Control));
        InputBindings.Add(new KeyBinding(new Relay(() => _model.Selection = new SidebarItem.NewJob()), Key.N, ModifierKeys.Control));
        InputBindings.Add(new KeyBinding(new Relay(() => _model.Selection = new SidebarItem.CleanOnly()), Key.L, ModifierKeys.Control | ModifierKeys.Shift));
        InputBindings.Add(new KeyBinding(new Relay(() => _model.Selection = new SidebarItem.StoryOptimizer()), Key.O, ModifierKeys.Control | ModifierKeys.Shift));

        _model.SelectionChanged += OnSelection;
        _model.Changed += RenderSidebar;
        Closing += (_, e) => { if (!App.Instance.OnMainClosing()) e.Cancel = true; };
        Closed += (_, _) =>
        {
            _model.SelectionChanged -= OnSelection;
            _model.Changed -= RenderSidebar;
            _page?.Detach();
        };
        RenderSidebar();
        ShowPage(_model.Selection);
    }

    private void OnSelection() => Dispatcher.Invoke(() => { RenderSidebar(); ShowPage(_model.Selection); });

    /// <summary>Tela de um item (exposto para o teste de fumaça).</summary>
    public static Page Create(SidebarItem item) => item switch
    {
        SidebarItem.NewJob => new NewJobView(cleanOnly: false),
        SidebarItem.CleanOnly => new NewJobView(cleanOnly: true),
        SidebarItem.StoryOptimizer => new StoryOptimizerView(),
        SidebarItem.JobItem j => new JobDetailView(j.Id),
        SidebarItem.Clients => new ClientsView(),
        SidebarItem.Logs => new LogsView(),
        SidebarItem.Settings => new SettingsView(),
        _ => new HomeView(),
    };

    private void ShowPage(SidebarItem item)
    {
        if (_shown == item && _page != null) return;
        _page?.Detach();
        _shown = item;
        _page = Create(item);
        _content.Content = _page;
    }

    private void RenderSidebar()
    {
        _sidebar.Children.Clear();
        var mark = new Image { Width = 28, Height = 28, Margin = new Thickness(0, 0, 10, 0) };
        try { mark.Source = new BitmapImage(new Uri("pack://application:,,,/Resources/BrandMark.png")); } catch { }
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 14, 16, 12) };
        brand.Children.Add(mark);
        brand.Children.Add(U.V(0, U.T("IMP Criativos", 15, bold: true, wrap: false), U.Caption($"{Niche.Name} · v{AppInfo.Version}")));
        _sidebar.Children.Add(brand);

        var unseen = _model.Log.UnseenErrors;
        AddItem("⌂", "Início", new SidebarItem.Home());
        AddItem("＋", "Novo lote", new SidebarItem.NewJob());
        AddItem("⌫", "Limpar logo", new SidebarItem.CleanOnly());
        AddItem("▯", "Otimizador em Lote (Stories 9:16)", new SidebarItem.StoryOptimizer());
        AddItem("👥", "Clientes", new SidebarItem.Clients());
        AddItem("☰", "Histórico", new SidebarItem.Logs(), unseen > 0 ? $"{unseen}" : null);
        AddItem("⚙", "Configurações", new SidebarItem.Settings(), _model.Updater.AvailableRelease != null ? "1" : null);

        var section = U.T("Lotes", 11.5, bold: true, color: Brand.Secondary);
        section.Margin = new Thickness(18, 16, 0, 6);
        _sidebar.Children.Add(section);
        var jobs = _model.Jobs.Jobs;
        if (jobs.Count == 0)
        {
            var none = U.T("Nenhum lote ainda", 12.5, color: Brand.Secondary);
            none.Margin = new Thickness(18, 2, 0, 0);
            _sidebar.Children.Add(none);
        }
        foreach (var job in jobs)
        {
            var sub = job.State == JobState.Running
                ? (UIElement)U.H(6, U.Progress(job.Progress, 60), U.Caption($"{(int)(job.Progress * 100)}%"))
                : U.Caption(job.State.Label());
            var row = U.V(3, U.T(job.Name, 13, wrap: false), sub);
            AddRow(row, new SidebarItem.JobItem(job.Id));
        }
    }

    private void AddItem(string icon, string label, SidebarItem target, string? badge = null)
    {
        var text = U.T(label, 13, wrap: false);
        var dock = new DockPanel();
        if (badge != null)
        {
            var b = new Border
            {
                Background = Brand.Red,
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(6, 0, 6, 1),
                Child = U.T(badge, 11, bold: true, color: Brushes.White, wrap: false),
                VerticalAlignment = VerticalAlignment.Center,
            };
            DockPanel.SetDock(b, Dock.Right);
            dock.Children.Add(b);
        }
        var ic = U.T(icon, 13, color: Brand.Red, wrap: false);
        ic.Width = 22;
        dock.Children.Add(U.H(4, ic, text));
        AddRow(dock, target);
    }

    private void AddRow(UIElement content, SidebarItem target)
    {
        var selected = _model.Selection == target;
        var row = new Border
        {
            Margin = new Thickness(8, 1, 8, 1),
            Padding = new Thickness(10, 7, 10, 7),
            CornerRadius = new CornerRadius(6),
            Background = selected ? Brand.SurfaceRaised : Brushes.Transparent,
            Child = content,
            Cursor = Cursors.Hand,
        };
        row.MouseEnter += (_, _) => { if (_model.Selection != target) row.Background = Brand.Surface; };
        row.MouseLeave += (_, _) => { if (_model.Selection != target) row.Background = Brushes.Transparent; };
        row.MouseLeftButtonUp += (_, _) => _model.Selection = target;
        _sidebar.Children.Add(row);
    }
}

public sealed class Relay : ICommand
{
    private readonly Action _a;
    public Relay(Action a) { _a = a; }
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => _a();
}
