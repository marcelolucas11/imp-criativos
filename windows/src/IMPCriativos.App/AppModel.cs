using System.Windows;
using System.Windows.Threading;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App;

/// <summary>Itens do menu lateral (mesma ordem do Mac).</summary>
public abstract record SidebarItem
{
    public sealed record Home : SidebarItem;
    public sealed record NewJob : SidebarItem;
    /// <summary>1.0.0-beta.20: módulo "Limpar logo" (só limpeza, sem variações).</summary>
    public sealed record CleanOnly : SidebarItem;
    /// <summary>1.0.0-beta.21: Otimizador em Lote (Stories 9:16), 100% local, sem IA.</summary>
    public sealed record StoryOptimizer : SidebarItem;
    public sealed record JobItem(Guid Id) : SidebarItem;
    public sealed record Clients : SidebarItem;
    public sealed record Logs : SidebarItem;
    public sealed record Settings : SidebarItem;
}

/// <summary>Ponto central do app: guarda as lojas de dados, o executor de lotes e o atualizador.</summary>
public sealed class AppModel
{
    private static AppModel? _shared;
    public static AppModel Shared => _shared ??= new AppModel();

    public AppSettings Settings { get; } = new();
    public ClientStore Clients { get; } = new();
    public CustomAxisStore CustomAxes { get; } = new();
    public JobStore Jobs { get; } = new();
    public Updater Updater { get; } = new();
    public ActivityLog Log => ActivityLog.Shared;
    public JobRunner Runner { get; }

    private SidebarItem _selection = new SidebarItem.Home();

    /// <summary>Tela escolhida no menu lateral.</summary>
    public SidebarItem Selection
    {
        get => _selection;
        set
        {
            _selection = value;
            SelectionChanged?.Invoke();
        }
    }

    public event Action? SelectionChanged;

    /// <summary>Lote a filtrar quando o Histórico é aberto a partir de um lote.</summary>
    public Guid? LogJobFilter { get; set; }

    /// <summary>Algo que o menu lateral ou a bandeja mostram mudou (já na thread da tela, com intervalo mínimo).</summary>
    public event Action? Changed;

    private readonly DispatcherTimer _debounce;

    private AppModel()
    {
        Runner = new JobRunner(Jobs, Settings);
        CustomAxes.SeedIfNeeded(Clients.Clients);
        _debounce = new DispatcherTimer(DispatcherPriority.Background, Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(250),
        };
        _debounce.Tick += (_, _) =>
        {
            _debounce.Stop();
            Changed?.Invoke();
        };
        Jobs.Changed += _ => Poke();
        Runner.RunningChanged += Poke;
        Updater.Changed += Poke;
        Log.Added += _ => Poke();
        Clients.Changed += Poke;
    }

    /// <summary>Agenda um "Changed" (pode ser chamado de qualquer thread).</summary>
    public void Poke()
    {
        var d = _debounce.Dispatcher;
        if (d.CheckAccess()) { if (!_debounce.IsEnabled) _debounce.Start(); }
        else d.BeginInvoke(() => { if (!_debounce.IsEnabled) _debounce.Start(); });
    }

    public bool MissingKeys => !ApiKeyStore.HasKey(ProviderKind.Gemini) && !ApiKeyStore.HasKey(ProviderKind.Openai);
}
