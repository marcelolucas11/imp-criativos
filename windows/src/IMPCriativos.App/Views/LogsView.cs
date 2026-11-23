using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App.Views;

/// <summary>Histórico de movimentações, edições e erros, com filtros e cópia pronta para colar numa conversa de suporte.</summary>
public sealed class LogsView : Page
{
    private static readonly string[] Levels = { "Tudo", "Erros e alertas", "Só erros" };
    private static readonly string[] Periods = { "Hoje", "Últimos 7 dias", "Últimos 30 dias", "Tudo" };
    private const int MaxRows = 3000;

    private string _search = "";
    private string _level = "Tudo";
    private LogCategory? _category;
    private Guid? _jobFilter;
    private string _period = "Últimos 7 dias";
    private Guid? _selection;
    private string? _flash;
    private ContentControl _body = new();
    private ContentControl _summary = new();

    protected override void Attach()
    {
        Model.Log.MarkSeen();
        Model.Poke();
        ApplyJobFilterFromModel();
        Action<LogEntry> onAdd = _ => Dispatcher.BeginInvoke(FillBody);
        Subscribe(() => Model.Log.Added += onAdd, () => Model.Log.Added -= onAdd);
        Subscribe(() => { }, () => { Model.Log.MarkSeen(); Model.Poke(); });
    }

    private void ApplyJobFilterFromModel()
    {
        if (Model.LogJobFilter is not Guid id) return;
        _jobFilter = id;
        _period = "Tudo";
        _level = "Tudo";
        _category = null;
        _search = "";
        Model.LogJobFilter = null;
    }

    private DateTime? PeriodStart => _period switch
    {
        "Hoje" => DateTime.Today.ToUniversalTime(),
        "Últimos 7 dias" => DateTime.UtcNow.AddDays(-7),
        "Últimos 30 dias" => DateTime.UtcNow.AddDays(-30),
        _ => null,
    };

    private List<LogEntry> Filtered()
    {
        var start = PeriodStart;
        var q = _search.Trim().ToLowerInvariant();
        return Model.Log.Entries.Where(e =>
        {
            if (start is DateTime s && e.Date < s) return false;
            if (_level == "Erros e alertas" && e.Level != LogLevel.Error && e.Level != LogLevel.Warning) return false;
            if (_level == "Só erros" && e.Level != LogLevel.Error) return false;
            if (_category is LogCategory c && e.Category != c) return false;
            if (_jobFilter is Guid j && e.JobID != j) return false;
            if (q.Length > 0)
            {
                var hay = string.Join(" ", e.Message, e.Details ?? "", e.JobName ?? "", e.Item ?? "", e.Category.Label()).ToLowerInvariant();
                if (!hay.Contains(q)) return false;
            }
            return true;
        }).ToList();
    }

    private List<(Guid Id, string Name)> JobOptions()
    {
        var seen = new HashSet<Guid>();
        var o = new List<(Guid, string)>();
        foreach (var e in Model.Log.Entries)
            if (e.JobID is Guid id && seen.Add(id)) o.Add((id, e.JobName ?? "Lote"));
        return o;
    }

    protected override UIElement Render()
    {
        _body = new ContentControl();
        _summary = new ContentControl();
        var head = new StackPanel();
        U.Add(head, U.Header("Histórico",
            "Movimentações, edições e erros. Para buscar uma solução, copie o erro ou o diagnóstico e cole na conversa com o Claude."), 0);
        var search = U.Field(_search, v => { _search = v; FillBody(); }, "Buscar (ex.: 503, nome do criativo, chave)");
        search.Width = 300;
        var jobs = JobOptions();
        var filters = U.H(10,
            search,
            U.Segmented(Levels, _level, x => x, v => { _level = v; Rerender(); }),
            U.Combo(new LogCategory?[] { null }.Concat(LogCategoryExt.All.Select(c => (LogCategory?)c)), _category,
                c => c == null ? "Todas as categorias" : c.Value.Label(), v => { _category = v; FillBody(); }, 170),
            U.Combo(new Guid?[] { null }.Concat(jobs.Select(j => (Guid?)j.Id)), _jobFilter,
                id => id == null ? "Todos os lotes" : jobs.First(j => j.Id == id).Name, v => { _jobFilter = v; FillBody(); }, 180),
            U.Combo(Periods, _period, x => x, v => { _period = v; FillBody(); }, 150));
        U.Add(head, filters, 12);
        U.Add(head, _summary, 12);
        var header = new Border { Background = Brand.HeaderBackground, Padding = new Thickness(20), Child = head, BorderBrush = Brand.Stroke, BorderThickness = new Thickness(0, 0, 0, 1) };
        var dock = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        dock.Children.Add(header);
        dock.Children.Add(_body);
        FillBody();
        return dock;
    }

    private void FillBody()
    {
        var rows = Filtered();
        var shown = rows.Take(MaxRows).ToList();
        var errors = rows.Count(e => e.Level == LogLevel.Error);
        var warnings = rows.Count(e => e.Level == LogLevel.Warning);
        var left = new List<UIElement> { U.T($"{rows.Count} registro(s)", 12.5, color: Brand.Secondary) };
        if (errors > 0) left.Add(U.IconText("⛔", $"{errors} erro(s)", Brand.Red, 12.5));
        if (warnings > 0) left.Add(U.IconText("⚠", $"{warnings} alerta(s)", Brand.Warning, 12.5));
        if (rows.Count > MaxRows) left.Add(U.T($"mostrando os {MaxRows} mais recentes", 12.5, color: Brand.Secondary));
        if (_flash != null) left.Add(U.IconText("✔", _flash, Brand.Success, 12.5));
        var diag = U.Btn("🩺 Copiar diagnóstico", () => { Shell.Copy(Diagnostic(rows)); Flash("Diagnóstico copiado — cole na conversa com o Claude"); },
            tooltip: "Copia versão do app, configuração (sem chaves) e os registros filtrados (até 300).", enabled: rows.Count > 0);
        var more = new Button { Content = "⋯ Mais", Padding = new Thickness(12, 6, 12, 6) };
        more.Click += (_, _) =>
        {
            var m = new ContextMenu { PlacementTarget = more };
            var exp = new MenuItem { Header = "Exportar registros filtrados…", IsEnabled = rows.Count > 0 };
            exp.Click += (_, _) => Export(rows);
            var open = new MenuItem { Header = "Abrir pasta dos registros" };
            open.Click += (_, _) => Shell.Open(ActivityLog.Folder);
            var clear = new MenuItem { Header = "Apagar histórico…" };
            clear.Click += (_, _) =>
            {
                if (!Confirm("Apagar todo o histórico?", "Os lotes e imagens não são afetados, só os registros.")) return;
                Model.Log.Clear();
                _selection = null;
                FillBody();
            };
            m.Items.Add(exp);
            m.Items.Add(open);
            m.Items.Add(new Separator());
            m.Items.Add(clear);
            m.IsOpen = true;
        };
        _summary.Content = U.Row(left, new UIElement[] { diag, more }, 14);

        if (shown.Count == 0)
        {
            var empty = U.V(8, U.T("☰", 36, color: Brand.Secondary), U.T("Nada por aqui", 16, bold: true),
                U.T(Model.Log.Entries.Count == 0 ? "As movimentações, edições e erros vão aparecer aqui." : "Nenhum registro com esses filtros.", color: Brand.Secondary));
            empty.HorizontalAlignment = HorizontalAlignment.Center;
            empty.VerticalAlignment = VerticalAlignment.Center;
            _body.Content = empty;
            return;
        }

        var grid = new DataGrid
        {
            AutoGenerateColumns = false,
            IsReadOnly = true,
            HeadersVisibility = DataGridHeadersVisibility.Column,
            SelectionMode = DataGridSelectionMode.Extended,
            GridLinesVisibility = DataGridGridLinesVisibility.None,
            Background = Brand.Background,
            RowBackground = Brand.Background,
            AlternatingRowBackground = Brand.Surface,
            BorderThickness = new Thickness(0),
            CanUserAddRows = false,
        };
        var data = shown.Select(e => new Row(e)).ToList();
        grid.Columns.Add(new DataGridTextColumn { Header = "Quando", Binding = new Binding(nameof(Row.When)), Width = 140 });
        grid.Columns.Add(new DataGridTextColumn { Header = "Tipo", Binding = new Binding(nameof(Row.Type)), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "Categoria", Binding = new Binding(nameof(Row.Category)), Width = 110 });
        grid.Columns.Add(new DataGridTextColumn { Header = "Lote · criativo", Binding = new Binding(nameof(Row.Where)), Width = 200 });
        grid.Columns.Add(new DataGridTextColumn { Header = "O que aconteceu", Binding = new Binding(nameof(Row.Message)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        grid.ItemsSource = data;
        var detail = new ContentControl();
        grid.SelectionChanged += (_, _) =>
        {
            if (grid.SelectedItem is Row r) { _selection = r.Entry.Id; detail.Content = Detail(r.Entry); }
        };
        var menu = new ContextMenu();
        var copy = new MenuItem { Header = "Copiar (para colar no Claude)" };
        copy.Click += (_, _) =>
        {
            var picked = grid.SelectedItems.OfType<Row>().Select(r => r.Entry.PlainText);
            Shell.Copy(string.Join("\n\n", picked));
            Flash("Copiado");
        };
        var openJob = new MenuItem { Header = "Abrir o lote" };
        openJob.Click += (_, _) => { if (grid.SelectedItem is Row { Entry.JobID: Guid id }) Model.Selection = new SidebarItem.JobItem(id); };
        menu.Items.Add(copy);
        menu.Items.Add(openJob);
        grid.ContextMenu = menu;
        if (_selection is Guid sel && data.FirstOrDefault(r => r.Entry.Id == sel) is Row selected) grid.SelectedItem = selected;
        else detail.Content = Detail(null);

        var split = new Grid();
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(3, GridUnitType.Star), MinHeight = 220 });
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(5) });
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(2, GridUnitType.Star), MinHeight = 150 });
        split.Children.Add(grid);
        var splitter = new GridSplitter { Height = 5, HorizontalAlignment = HorizontalAlignment.Stretch, Background = Brand.Stroke };
        Grid.SetRow(splitter, 1);
        split.Children.Add(splitter);
        Grid.SetRow(detail, 2);
        split.Children.Add(detail);
        _body.Content = split;
    }

    private sealed class Row
    {
        public LogEntry Entry { get; }
        public Row(LogEntry e) { Entry = e; }
        public string When => LogEntry.Stamp(Entry.Date);
        public string Type => Entry.Level switch
        {
            LogLevel.Error => "⛔ " + Entry.Level.Label(),
            LogLevel.Warning => "⚠ " + Entry.Level.Label(),
            LogLevel.Success => "✔ " + Entry.Level.Label(),
            _ => "ℹ " + Entry.Level.Label(),
        };
        public string Category => Entry.Category.Label();
        public string Where => string.Join(" · ", new[] { Entry.JobName, Entry.Item }.Where(x => x != null));
        public string Message => Entry.Message;
    }

    private UIElement Detail(LogEntry? e)
    {
        if (e == null)
        {
            var t = U.T("Selecione um registro para ver os detalhes técnicos.", color: Brand.Secondary);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.VerticalAlignment = VerticalAlignment.Center;
            return new Border { Background = Brand.Surface, Child = t };
        }
        var color = e.Level switch { LogLevel.Success => Brand.Success, LogLevel.Warning => Brand.Warning, LogLevel.Error => Brand.Red, _ => Brand.Secondary };
        var right = new List<UIElement>();
        if (e.JobID is Guid id) right.Add(U.Btn("Abrir o lote", () => Model.Selection = new SidebarItem.JobItem(id)));
        right.Add(U.Btn("Copiar este registro", () => { Shell.Copy(e.PlainText); Flash("Registro copiado"); }));
        var ctx = U.Btn("Copiar com contexto", () => { Shell.Copy(Diagnostic(Context(e))); Flash("Registro e contexto copiados"); });
        ctx.ToolTip = "Copia este registro, os 20 registros em volta e a configuração do app.";
        right.Add(ctx);
        var body = new StackPanel();
        if (e.JobName != null) U.Add(body, U.T($"Lote: {e.JobName}" + (e.Item != null ? $" · Criativo: {e.Item}" : ""), color: Brand.Secondary), 0);
        U.Add(body, new TextBox { Text = e.Message, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, BorderThickness = new Thickness(0), Background = System.Windows.Media.Brushes.Transparent, Foreground = Brand.Text }, 8);
        if (!string.IsNullOrEmpty(e.Details))
            U.Add(body, new Border
            {
                Background = Brand.Black35,
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(10),
                Child = new TextBox
                {
                    Text = e.Details, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontFamily = new System.Windows.Media.FontFamily("Cascadia Mono, Consolas"),
                    FontSize = 11.5, BorderThickness = new Thickness(0), Background = System.Windows.Media.Brushes.Transparent, Foreground = Brand.Text,
                },
            }, 8);
        var s = U.V(10, U.Row(new UIElement[]
        {
            U.T(e.Level.Label(), 15, bold: true, color: color), U.T(e.Category.Label(), color: Brand.Secondary), U.T(LogEntry.Stamp(e.Date), color: Brand.Secondary),
        }, right), new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        return new Border { Background = Brand.Surface, Padding = new Thickness(16), Child = s };
    }

    private void Flash(string text)
    {
        _flash = text;
        FillBody();
        Task.Delay(2500).ContinueWith(_ => Dispatcher.Invoke(() => { if (_flash == text) { _flash = null; FillBody(); } }));
    }

    /// <summary>O registro e os 10 antes e 10 depois dele no histórico completo.</summary>
    private List<LogEntry> Context(LogEntry entry)
    {
        var all = Model.Log.Entries;
        var i = all.FindIndex(x => x.Id == entry.Id);
        if (i < 0) return new List<LogEntry> { entry };
        var lo = Math.Max(0, i - 10);
        var hi = Math.Min(all.Count, i + 11);
        return all.GetRange(lo, hi - lo);
    }

    private string FilterDescription
    {
        get
        {
            var parts = new List<string> { _level, _period };
            if (_category is LogCategory c) parts.Add(c.Label());
            if (_jobFilter is Guid j && JobOptions().FirstOrDefault(o => o.Id == j).Name is string n) parts.Add($"lote \"{n}\"");
            if (_search.Length > 0) parts.Add($"busca \"{_search}\"");
            return string.Join(" · ", parts);
        }
    }

    /// <summary>Texto para colar numa conversa de suporte: versão, configuração (sem chaves) e registros.</summary>
    private string Diagnostic(List<LogEntry> entries, int limit = 300)
    {
        var lines = new List<string>
        {
            "=== Diagnóstico IMP Criativos ===",
            $"Versão: {AppInfo.Version} (Windows) · Windows {Environment.OSVersion.Version}",
            $"Gerado em: {LogEntry.Stamp(DateTime.UtcNow)}",
            $"Chaves: Gemini {(ApiKeyStore.HasKey(ProviderKind.Gemini) ? "salva" : "não configurada")} · OpenAI {(ApiKeyStore.HasKey(ProviderKind.Openai) ? "salva" : "não configurada")}",
            Model.Settings.Summary,
            $"Filtro: {FilterDescription}",
            "",
            $"--- Registros (mais recentes primeiro; {Math.Min(limit, entries.Count)} de {entries.Count}) ---",
        };
        lines.AddRange(entries.Take(limit).Select(e => e.PlainText));
        return string.Join("\n", lines);
    }

    private void Export(List<LogEntry> rows)
    {
        var name = $"imp-criativos-historico_{DateTime.Now.ToString("yyyy-MM-dd_HHmm", CultureInfo.InvariantCulture)}.txt";
        var path = Pickers.SaveFile("Exportar histórico", name, "Texto (*.txt)|*.txt");
        if (path == null) return;
        try
        {
            File.WriteAllText(path, Diagnostic(rows, rows.Count));
            Flash("Exportado");
            Shell.Reveal(path);
        }
        catch (Exception e)
        {
            AppLog.Error(LogCategory.Sistema, $"Não foi possível exportar o histórico: {e.Message}", details: path);
        }
    }
}
