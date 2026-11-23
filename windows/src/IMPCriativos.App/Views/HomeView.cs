using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;

namespace IMPCriativos.App.Views;

public sealed class HomeView : Page
{
    protected override void Attach() => Subscribe(() => Model.Changed += Invalidate, () => Model.Changed -= Invalidate);

    protected override UIElement Render()
    {
        var jobs = Model.Jobs.Jobs;
        var running = jobs.Count(j => j.State == JobState.Running);
        var review = jobs.Count(j => j.State == JobState.Review);

        var root = new StackPanel();
        var header = U.Row(new UIElement[] { U.Header("Início", "Limpe criativos e gere variações em lote.") }, new UIElement[]
        {
            U.Btn("▯  Stories 9:16", () => Model.Selection = new SidebarItem.StoryOptimizer(),
                tooltip: "Otimizador em Lote: até 100 imagens em 1080×1920, sem IA"),
            U.Btn("⌫  Limpar logo", () => Model.Selection = new SidebarItem.CleanOnly()),
            U.Btn("＋  Novo lote", () => Model.Selection = new SidebarItem.NewJob(), primary: true),
        });
        U.Add(root, header, 0);

        if (Model.MissingKeys)
        {
            U.Add(root, U.Card(U.Row(new UIElement[]
            {
                U.T("🔑", 16, color: Brand.Warning),
                U.V(2, U.T("Configure suas chaves de API", 15, bold: true),
                    U.T("Sem a chave do Gemini ou da OpenAI os lotes não rodam.", color: Brand.Secondary)),
            }, new UIElement[] { U.Btn("Abrir Configurações", () => Model.Selection = new SidebarItem.Settings()) })), 20);
        }
        if (Model.Updater.AvailableRelease is { } r)
        {
            U.Add(root, U.Card(U.Row(new UIElement[]
            {
                U.T("⬇", 16, color: Brand.Red), U.T($"Nova versão disponível: {r.Version}", 15, bold: true),
            }, new UIElement[] { U.Btn("Ver atualização", () => Model.Selection = new SidebarItem.Settings()) })), 20);
        }

        var stats = new UniformGrid3();
        stats.Add(Stat("Em processamento", $"{running}", "⚙", Brand.Red));
        stats.Add(Stat("Aguardando revisão", $"{review}", "👁", Brand.Warning));
        stats.Add(Stat("Gasto estimado no mês", Model.Jobs.MonthCost.Usd(), "$", Brand.Secondary));
        U.Add(root, stats.Panel, 20);

        U.Add(root, U.T("Lotes recentes", 18, bold: true), 26);
        if (jobs.Count == 0)
        {
            U.Add(root, U.Card(U.V(6, U.T("Nenhum lote ainda.", 15, bold: true),
                U.T("O app é feito para criativos de cassino online e apostas esportivas (bet). Crie um cliente em Clientes (o que remover e como variar) e depois um Novo lote apontando para a pasta dos criativos.",
                    color: Brand.Secondary))), 12);
        }
        else
        {
            var list = new StackPanel();
            foreach (var job in jobs.Take(10)) U.Add(list, RecentRow(job), 8);
            U.Add(root, list, 12);
        }
        return U.Scroll(root);
    }

    private static Border Stat(string label, string value, string symbol, System.Windows.Media.Brush tint) =>
        U.Card(U.V(8, U.H(6, U.T(symbol, 13, color: tint), U.T(label, 13, color: tint)), U.T(value, 28, weight: FontWeights.SemiBold)));

    public static System.Windows.Media.Color StateColor(JobState s) => s switch
    {
        JobState.Running => Brand.RedColor,
        JobState.Review => Brand.Warning.Color,
        JobState.Exported => Brand.Success.Color,
        JobState.Cancelled => System.Windows.Media.Color.FromRgb(90, 90, 90),
        _ => System.Windows.Media.Colors.Gray,
    };

    private UIElement RecentRow(Job job)
    {
        var right = new List<UIElement>();
        if (job.State == JobState.Running) right.Add(U.Progress(job.Progress, 120));
        right.Add(U.Caption(job.CostUSD.Usd()));
        right.Add(U.Pill(job.State.Label(), StateColor(job.State)));
        var card = U.Card(U.Row(new UIElement[]
        {
            U.V(3, U.T(job.Name, 15, bold: true, wrap: false),
                U.Caption($"{job.Client.Name} · {job.Items.Count} criativos · {(job.IsCleanOnly ? "só limpeza" : $"{job.VariationsPerItem} variações")} · {Short(job.CreatedAt)}")),
        }, right, 14), 12);
        card.Cursor = Cursors.Hand;
        var id = job.Id;
        card.MouseLeftButtonUp += (_, _) => Model.Selection = new SidebarItem.JobItem(id);
        return card;
    }
}

/// <summary>Três colunas iguais (os quadros de números do Início).</summary>
public sealed class UniformGrid3
{
    public Grid Panel { get; } = new();
    private int _n;

    public UniformGrid3(int columns = 3)
    {
        for (var i = 0; i < columns; i++)
            Panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
    }

    public void Add(FrameworkElement e)
    {
        e.Margin = new Thickness(_n == 0 ? 0 : 7, 0, 7, 0);
        Grid.SetColumn(e, _n++);
        Panel.Children.Add(e);
    }
}
