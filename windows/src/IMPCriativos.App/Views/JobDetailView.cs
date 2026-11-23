using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App.Views;

/// <summary>Um lote: progresso, revisão (aprovar, refazer com observação, descartar) e Baixar aprovados.</summary>
public sealed class JobDetailView : Page
{
    private readonly Guid _jobID;
    private string _filter = "Todos";
    private bool _exporting;
    private const double TileWidth = 190;
    private static readonly string[] Filters = { "Todos", "Com alerta", "Revisão pendente", "Com falha" };

    public JobDetailView(Guid jobID) { _jobID = jobID; }

    protected override void Attach()
    {
        Action<Guid> onJob = id => { if (id == _jobID || id == Guid.Empty) Invalidate(); };
        Subscribe(() => Model.Jobs.Changed += onJob, () => Model.Jobs.Changed -= onJob);
        Subscribe(() => SpeedMonitor.Shared.Changed += Invalidate, () => SpeedMonitor.Shared.Changed -= Invalidate);
        // contagem regressiva das novas tentativas
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        t.Tick += (_, _) => { if (Model.Jobs.Get(_jobID)?.State == JobState.Running) Invalidate(); };
        Subscribe(t.Start, t.Stop);
    }

    /// <summary>1.0.0-beta.20: cabeçalho conforme o modo (só limpeza, limpeza desligada, teste de eixos).</summary>
    public static string Subtitle(Job job)
    {
        var o = $"saída: {job.SizeMode.Label} {job.Format.Label()}";
        if (job.IsCleanOnly)
            return $"{job.Client.Name} · {job.Items.Count} criativos · só limpeza · limpeza: {job.CleanProvider.Label()} · {o}";
        var clean = job.SkipsCleaning ? "limpeza desligada (imagens já limpas)" : $"limpeza: {job.CleanProvider.Label()}";
        return $"{job.Client.Name} · {job.Items.Count} criativos · {job.VariationsPerItem} variações{(job.IsAxisTest ? " (teste de eixos)" : "")} · {clean} · variações: {job.VariationProvider.Label()} · {o}";
    }

    private List<JobItem> Filtered(Job job) => _filter switch
    {
        "Com alerta" => job.Items.Where(i => i.HasWarning).ToList(),
        "Com falha" => job.Items.Where(i => i.HasFailure).ToList(),
        "Revisão pendente" => job.Items.Where(i => (i.CleanStatus == StepStatus.Done && i.CleanReview == ReviewStatus.Pending) ||
                                                   i.Variations.Any(v => v.Status == StepStatus.Done && v.Review == ReviewStatus.Pending)).ToList(),
        _ => job.Items,
    };

    protected override UIElement Render()
    {
        var job = Model.Jobs.Get(_jobID);
        if (job == null) return U.T("Lote não encontrado.", color: Brand.Secondary);
        var dock = new DockPanel();
        var header = Header(job);
        DockPanel.SetDock(header, Dock.Top);
        dock.Children.Add(header);
        var list = new StackPanel();
        var items = Filtered(job);
        foreach (var item in items) U.Add(list, ItemCard(job, item), 12);
        if (items.Count == 0) list.Children.Add(U.T("Nada neste filtro.", color: Brand.Secondary));
        dock.Children.Add(U.Scroll(list, 20));
        return dock;
    }

    private Border Header(Job job)
    {
        var s = new StackPanel();
        var title = U.H(10, U.T(job.Name, 22, weight: FontWeights.Bold, wrap: false), U.Pill(job.State.Label(), HomeView.StateColor(job.State)));
        var cost = U.Caption(job.CostUSD.Usd());
        cost.ToolTip = "Gasto estimado deste lote";
        U.Add(s, U.Row(new UIElement[] { U.V(4, title, U.Caption(Subtitle(job))) }, new UIElement[] { cost }), 0);
        if (job.Instructions is BatchInstructions ins && !ins.IsEmpty)
        {
            var l = U.IconText("💬", ins.Summary, Brand.Text, 11.5);
            l.ToolTip = $"Instruções deste lote:\n{ins.Raw}\n\n{ins.Summary}";
            U.Add(s, l, 10);
        }
        var prog = new DockPanel();
        var steps = U.Caption($"{job.FinishedSteps}/{job.TotalSteps}");
        steps.Margin = new Thickness(10, 0, 0, 0);
        DockPanel.SetDock(steps, Dock.Right);
        prog.Children.Add(steps);
        prog.Children.Add(U.Progress(job.Progress));
        U.Add(s, prog, 10);

        // 1.0.0-beta.19: velocidade da IA das variações enquanto o lote roda
        if (job.State == JobState.Running &&
            SpeedMonitor.Shared.Snapshots.TryGetValue(job.IsCleanOnly ? job.CleanProvider : job.VariationProvider, out var snap))
        {
            var sp = U.IconText(snap.InSafeMode ? "🛡" : "⏱", snap.Line, snap.InSafeMode ? Brand.Warning : Brand.Secondary, 11.5);
            sp.ToolTip = "Configurações → Velocidade. A velocidade só muda quantos pedidos vão juntos; a qualidade não muda.";
            U.Add(s, sp, 8);
        }
        if (FailureSummary(job) is UIElement fs) U.Add(s, fs, 8);
        if (job.LastError is string err)
        {
            var row = U.H(8, U.Error(err));
            if (err.Contains("Chave")) row.Children.Add(U.Btn("Configurações", () => Model.Selection = new SidebarItem.Settings()));
            U.Add(s, row, 8);
        }

        var left = new List<UIElement>();
        switch (job.State)
        {
            case JobState.Running:
                left.Add(U.Btn("⏸ Pausar", () => Model.Runner.Pause(_jobID)));
                break;
            case JobState.Paused:
            case JobState.Queued:
                left.Add(U.Btn("▶ Retomar", () => Model.Runner.Start(_jobID), primary: true));
                break;
        }
        if (job.FailureCount > 0)
            left.Add(U.Btn($"↻ Tentar falhas de novo ({job.FailureCount})", () => Model.Runner.RetryFailed(_jobID),
                tooltip: "Volta para a fila tudo que falhou, usando a mesma IA (com troca automática se estiver ligada)."));

        var actions = new Button { Content = "⋯ Ações", Padding = new Thickness(12, 6, 12, 6) };
        actions.Click += (_, _) => ActionsMenu(job, actions);
        var export = U.Btn(_exporting ? "Exportando…" : $"⬇ Baixar aprovados ({job.ApprovedCount})", () => Export(job), primary: true,
            enabled: job.ApprovedCount > 0 && !_exporting);
        U.Add(s, U.Row(left, new UIElement[] { actions, export }), 12);
        U.Add(s, U.Segmented(Filters, _filter, f => f, f => { _filter = f; Rerender(); }), 10);
        return new Border { Background = Brand.HeaderBackground, Padding = new Thickness(20), Child = s, BorderBrush = Brand.Stroke, BorderThickness = new Thickness(0, 0, 0, 1) };
    }

    private void ActionsMenu(Job job, Button anchor)
    {
        var m = new ContextMenu { PlacementTarget = anchor, Placement = PlacementMode.Bottom };
        void Add(string text, Action a, bool enabled = true)
        {
            var mi = new MenuItem { Header = text, IsEnabled = enabled };
            mi.Click += (_, _) => a();
            m.Items.Add(mi);
        }
        Add("Aprovar pendentes sem alerta", () => BulkApprove(true));
        Add("Aprovar todos os pendentes", () => BulkApprove(false));
        if (job.FailureCount > 0)
        {
            m.Items.Add(new Separator());
            foreach (var kind in ProviderKindExt.All)
            {
                var k = kind;
                Add($"Refazer falhas com {kind.Label()}", () => Model.Runner.RetryFailed(_jobID, k), ApiKeyStore.HasKey(kind));
            }
        }
        m.Items.Add(new Separator());
        Add("Ver histórico deste lote", () => { Model.LogJobFilter = _jobID; Model.Selection = new SidebarItem.Logs(); });
        Add("Abrir pasta dos originais", () => Shell.Open(job.InputFolder));
        Add("Abrir pasta de trabalho do lote", () => Shell.Open(Model.Jobs.Folder(_jobID)));
        m.Items.Add(new Separator());
        if (job.State is JobState.Running or JobState.Paused) Add("Cancelar lote", () => Model.Runner.Cancel(_jobID));
        Add("Excluir lote…", () =>
        {
            if (!Confirm("Excluir este lote?", "Os arquivos já exportados não são apagados.\n\nExcluir lote e imagens intermediárias?")) return;
            Model.Runner.Cancel(_jobID);
            if (Model.Jobs.Get(_jobID) is Job j) AppLog.Warning(LogCategory.Lote, "Lote excluído.", jobID: _jobID, jobName: j.Name);
            Model.Selection = new SidebarItem.Home();
            Model.Jobs.Delete(_jobID);
        });
        m.IsOpen = true;
    }

    private UIElement? FailureSummary(Job job)
    {
        var kinds = job.Items.SelectMany(item => item.CleanStatus == StepStatus.Failed
            ? new[] { item.CleanErrorKind ?? AIErrorKind.Other }
            : item.Variations.Where(v => v.Status == StepStatus.Failed).Select(v => v.ErrorKind ?? AIErrorKind.Other).ToArray()).ToList();
        var temporary = kinds.Count(k => k.IsTemporary());
        var definitive = kinds.Count - temporary;
        var waiting = job.Items.Sum(i => (i.CleanRetryNote != null ? 1 : 0) + i.Variations.Count(v => v.RetryNote != null));
        if (temporary + definitive + waiting == 0) return null;
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        if (waiting > 0) U.Add(row, U.IconText("⏳", $"{waiting} aguardando nova tentativa", Brand.Warning, 11.5), 14);
        if (temporary > 0) U.Add(row, U.IconText("🕒", $"{temporary} falha(s) temporária(s) — IA ocupada ou sem conexão", Brand.Warning, 11.5), 14);
        if (definitive > 0) U.Add(row, U.IconText("⛔", $"{definitive} falha(s) definitiva(s)", Brand.Red, 11.5), 14);
        U.Add(row, U.Link("Ver no histórico", () => { Model.LogJobFilter = _jobID; Model.Selection = new SidebarItem.Logs(); }), 14);
        return row;
    }

    private void BulkApprove(bool onlyClean)
    {
        var count = 0;
        Model.Jobs.Update(_jobID, job =>
        {
            foreach (var item in job.Items)
            {
                if (item.CleanStatus == StepStatus.Done && item.CleanReview == ReviewStatus.Pending && !(onlyClean && item.CleanWarning != null))
                {
                    item.CleanReview = ReviewStatus.Approved;
                    count++;
                }
                foreach (var v in item.Variations)
                {
                    if (v.Status == StepStatus.Done && v.Review == ReviewStatus.Pending && !(onlyClean && v.TextWarning != null))
                    {
                        v.Review = ReviewStatus.Approved;
                        count++;
                    }
                }
            }
        });
        if (count > 0 && Model.Jobs.Get(_jobID) is Job j)
            AppLog.Info(LogCategory.Revisao, $"{count} imagem(ns) aprovada(s) em massa" + (onlyClean ? " (só as sem alerta)." : "."),
                jobID: _jobID, jobName: j.Name);
    }

    private async void Export(Job job)
    {
        var @base = Paths.Ensure(Model.Settings.DefaultOutputFolder);
        var dest = Pickers.Folder("Onde salvar os aprovados?", @base);
        if (dest == null) return;
        _exporting = true;
        Rerender();
        try
        {
            var result = await Exporter.Export(job, Model.Jobs.Folder(_jobID), dest);
            Model.Jobs.Update(_jobID, j =>
            {
                j.ExportedTo = result.Folder;
                if (j.State == JobState.Review) j.State = JobState.Exported;
            });
            var msg = $"{result.Count} imagens salvas em {result.Folder}." +
                      (result.Failures.Count == 0 ? "" : $"\nFalharam: {string.Join(", ", result.Failures)}");
            if (result.Failures.Count == 0)
                AppLog.Success(LogCategory.Exportacao, $"{result.Count} imagens exportadas.", details: result.Folder, jobID: _jobID, jobName: job.Name);
            else
                AppLog.Warning(LogCategory.Exportacao, $"{result.Count} imagens exportadas, {result.Failures.Count} falharam.",
                    details: $"Pasta: {result.Folder}\nFalharam: {string.Join(", ", result.Failures)}", jobID: _jobID, jobName: job.Name);
            if (MessageBox.Show(Window.GetWindow(this)!, msg + "\n\nMostrar no Explorador de Arquivos?", "Exportação",
                    MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
                Shell.Open(result.Folder);
        }
        catch (Exception e)
        {
            Alert("Exportação", $"Erro ao exportar: {e.Message}");
            AppLog.Error(LogCategory.Exportacao, $"Erro ao exportar: {e.Message}", details: dest, jobID: _jobID, jobName: job.Name);
        }
        finally
        {
            _exporting = false;
            Rerender();
        }
    }

    // MARK: - Cartão de um criativo

    private string? Url(Job job, string? rel) => Model.Jobs.FilePath(job.Id, rel);

    private UIElement ItemCard(Job job, JobItem item)
    {
        var headRight = new List<UIElement>();
        if (item.Plan is CreativePlan plan)
        {
            var p = U.T("📋", 13, color: Brand.Secondary);
            p.ToolTip = CreativePlanner.Summary(plan);
            headRight.Add(p);
        }
        if (item.Transcript is { Length: > 0 } t)
        {
            var q = U.T("❝", 13, color: Brand.Secondary);
            q.ToolTip = item.SeenText != null ? $"Texto esperado nas variações:\n{t}\n\nTexto visto no limpo:\n{item.SeenText}" : $"Texto detectado:\n{t}";
            headRight.Add(q);
        }
        var head = U.Row(new UIElement[] { U.T(item.SourceName, 15, bold: true, wrap: false), U.Caption($"{item.PixelWidth}×{item.PixelHeight}") }, headRight);

        var tiles = new StackPanel { Orientation = Orientation.Horizontal };
        // ORIGINAL
        U.Add(tiles, Tile("Original", Url(job, item.OriginalFile), StepStatus.Done, ReviewStatus.Pending, null, null,
            () => Preview.Show(Window.GetWindow(this), $"{item.SourceName} — original", Url(job, item.OriginalFile)!, null), null), 12);

        // LIMPO (v0)
        var cleanFooter = new StackPanel();
        if (item.CleanStatus == StepStatus.Failed && item.CleanError is string ce)
        {
            U.Add(cleanFooter, FailureLabel(job, item, "Limpeza", ce, item.CleanErrorKind, item.CleanErrorDetails), 4);
            if (AltProvider(item.CleanProviderUsed ?? item.CleanProviderOverride ?? job.CleanProvider,
                    k => Model.Runner.RedoClean(job.Id, item.Id, null, k)) is UIElement alt) U.Add(cleanFooter, alt, 4);
        }
        if (item.CleanStatus == StepStatus.Done && item.CleanProviderUsed is ProviderKind used && used != job.CleanProvider)
            U.Add(cleanFooter, ProviderUsed(used), 4);
        if (item.CleanStatus == StepStatus.Done && item.CleanSkipped == true && job.SkipsCleaning && item.ForceClean != true)
        {
            var l = U.IconText("→", "Limpeza desligada · imagem enviada", Brand.Secondary, 11.5);
            l.ToolTip = "Neste lote a limpeza estava desligada: a imagem da pasta foi usada como está. Use \"Refazer\" para limpar esta imagem mesmo assim.";
            U.Add(cleanFooter, l, 4);
        }
        else if (item.CleanStatus == StepStatus.Done && item.CleanSkipped == true)
        {
            var l = U.IconText("✓", "Nada a remover · usando o original", Brand.Secondary, 11.5);
            l.ToolTip = "O plano não encontrou nada para apagar nesta imagem e a checagem confirmou. Use \"Refazer\" para limpar mesmo assim.";
            U.Add(cleanFooter, l, 4);
        }
        if (item.CleanWarning is string w) U.Add(cleanFooter, U.Warning(w), 4);
        if (item.CleanStatus is StepStatus.Done or StepStatus.Failed)
            U.Add(cleanFooter, ReviewBar(item.CleanReview, item.CleanStatus == StepStatus.Done,
                () => SetClean(job, item, ReviewStatus.Approved), () => SetClean(job, item, ReviewStatus.Discarded),
                note => Model.Runner.RedoClean(job.Id, item.Id, note)), 4);
        var cleanTitle = job.IsCleanOnly ? "Limpo" : (job.SkipsCleaning ? "Enviado · v0" : "Limpo · v0");
        U.Add(tiles, Tile(cleanTitle, item.CleanStatus == StepStatus.Done ? Url(job, item.CleanedFile) : null, item.CleanStatus, item.CleanReview,
            item.CleanRetryNote, item.CleanRetryAt,
            () => { if (Url(job, item.CleanedFile) is string u) Preview.Show(Window.GetWindow(this), $"{item.SourceName} — limpo", u, Url(job, item.OriginalFile)); },
            cleanFooter), 12);

        // VARIAÇÕES (o módulo "Limpar logo" não tem)
        if (!job.IsCleanOnly)
        {
            U.Add(tiles, new Border { Width = 1, Height = TileWidth, Background = Brand.Stroke, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 22, 0, 0) }, 12);
            if (item.CleanStatus == StepStatus.Failed)
            {
                var none = U.Caption("Sem variações: a limpeza falhou.");
                none.Width = TileWidth;
                none.VerticalAlignment = VerticalAlignment.Center;
                U.Add(tiles, none, 12);
            }
            else
            {
                foreach (var v in item.Variations)
                {
                    var f = new StackPanel();
                    if (v.Status == StepStatus.Failed && v.Error is string ve)
                    {
                        U.Add(f, FailureLabel(job, item, $"Variação v{v.Index} ({v.AxisName})", ve, v.ErrorKind, v.ErrorDetails), 4);
                        var vid = v.Id;
                        if (AltProvider(v.ProviderUsed ?? v.ProviderOverride ?? job.VariationProvider,
                                k => Model.Runner.RedoVariation(job.Id, item.Id, vid, null, k)) is UIElement alt) U.Add(f, alt, 4);
                    }
                    if (v.Status == StepStatus.Done && v.ProviderUsed is ProviderKind vu && vu != job.VariationProvider) U.Add(f, ProviderUsed(vu), 4);
                    if (v.TextWarning is string tw) U.Add(f, U.Warning(tw), 4);
                    var varID = v.Id;
                    if (v.Status is StepStatus.Done or StepStatus.Failed)
                        U.Add(f, ReviewBar(v.Review, v.Status == StepStatus.Done,
                            () => SetVariation(job, item, varID, ReviewStatus.Approved), () => SetVariation(job, item, varID, ReviewStatus.Discarded),
                            note => Model.Runner.RedoVariation(job.Id, item.Id, varID, note)), 4);
                    var title = $"v{v.Index} · {v.AxisLabel}";
                    U.Add(tiles, Tile(title, v.Status == StepStatus.Done ? Url(job, v.File) : null, v.Status, v.Review, v.RetryNote, v.RetryAt,
                        () =>
                        {
                            if (Url(job, v.File) is string u)
                                Preview.Show(Window.GetWindow(this), $"{item.SourceName} — v{v.Index} ({v.AxisLabel})", u, Url(job, item.CleanedFile));
                        }, f), 12);
                }
            }
        }
        var scroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = tiles,
            Padding = new Thickness(0, 0, 0, 6),
        };
        return U.Card(U.V(10, head, scroll), 12);
    }

    private static UIElement Tile(string title, string? image, StepStatus status, ReviewStatus review, string? note, DateTime? noteUntil,
        Action onOpen, UIElement? footer)
    {
        var s = new StackPanel { Width = TileWidth };
        U.Add(s, U.T(title, 11.5, bold: true, color: Brand.Secondary, wrap: false), 0);
        UIElement body;
        if (status == StepStatus.Done)
        {
            body = U.Thumb(image, TileWidth, onClick: onOpen, opacity: review == ReviewStatus.Discarded ? 0.35 : 1);
        }
        else
        {
            UIElement inner = status switch
            {
                StepStatus.Pending => U.IconText("🕒", "Na fila", Brand.Secondary, 11.5),
                StepStatus.Running when note != null => RetryNote(note, noteUntil),
                StepStatus.Running => U.V(6, new ProgressBar { IsIndeterminate = true, Width = 80, Height = 4, Foreground = Brand.Red }, U.Caption("Gerando…")),
                StepStatus.Failed => U.T("⛔", 26, color: Brand.Red),
                _ => new TextBlock(),
            };
            if (inner is FrameworkElement fe) { fe.HorizontalAlignment = HorizontalAlignment.Center; fe.VerticalAlignment = VerticalAlignment.Center; }
            body = new Border { Background = Brand.Black35, Width = TileWidth, Height = TileWidth, Child = inner };
        }
        var frame = new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderBrush = review switch
            {
                ReviewStatus.Approved => Brand.Success,
                ReviewStatus.Discarded => new SolidColorBrush(Color.FromArgb(102, 128, 128, 128)),
                _ => Brand.Stroke,
            },
            BorderThickness = new Thickness(review == ReviewStatus.Approved ? 2.5 : 1),
            Child = body,
            ClipToBounds = true,
        };
        U.Add(s, frame, 6);
        if (footer != null) U.Add(s, footer, 6);
        return s;
    }

    /// <summary>Aviso enquanto a etapa espera para tentar de novo, com contagem regressiva.</summary>
    private static UIElement RetryNote(string note, DateTime? until)
    {
        var s = U.V(5, U.T("⏳", 18, color: Brand.Warning), U.T(note, 11, color: Brand.Warning));
        if (until is DateTime u)
        {
            var secs = Math.Max(0, (int)Math.Ceiling((u - DateTime.UtcNow).TotalSeconds));
            s.Children.Add(U.Caption(secs > 0 ? $"nova tentativa em {secs}s" : "tentando…"));
        }
        foreach (var c in s.Children.OfType<TextBlock>()) c.TextAlignment = TextAlignment.Center;
        s.Margin = new Thickness(10);
        return s;
    }

    /// <summary>Erro de uma etapa: amarelo quando é temporário, vermelho quando é definitivo. Botão direito copia.</summary>
    private UIElement FailureLabel(Job job, JobItem item, string step, string message, AIErrorKind? kind, string? details)
    {
        var k = kind ?? AIErrorKind.Other;
        var color = k.IsTemporary() ? Brand.Warning : Brand.Red;
        var s = U.V(2, U.T(k == AIErrorKind.Other ? "Erro" : k.Title(), 11.5, bold: true, color: color), U.T(message, 10.5, color: color));
        s.ToolTip = $"{k.Title()}\n\n{message}\n\nO que fazer: {k.Hint()}\n\nClique com o botão direito para copiar.";
        var menu = new ContextMenu();
        var full = new MenuItem { Header = "Copiar erro (para colar no Claude)" };
        full.Click += (_, _) =>
        {
            var text = $"IMP Criativos {AppInfo.Version} (Windows) — erro no lote \"{job.Name}\"\nCriativo: {item.SourceName} · Etapa: {step}\nTipo: {k.Title()}\nMensagem: {message}";
            if (!string.IsNullOrEmpty(details)) text += $"\nDetalhes técnicos:\n{details}";
            Shell.Copy(text);
        };
        var only = new MenuItem { Header = "Copiar só a mensagem" };
        only.Click += (_, _) => Shell.Copy(message);
        menu.Items.Add(full);
        menu.Items.Add(only);
        s.ContextMenu = menu;
        return s;
    }

    /// <summary>"Refazer com GPT/Gemini" embaixo de uma etapa que falhou (só aparece se a outra IA tiver chave).</summary>
    private static UIElement? AltProvider(ProviderKind current, Action<ProviderKind> redo)
    {
        var alt = current.Other();
        if (!ApiKeyStore.HasKey(alt)) return null;
        return U.Link($"⇄ Refazer com {alt.Label()}", () => redo(alt));
    }

    private static UIElement ProviderUsed(ProviderKind p)
    {
        var l = U.IconText("⇄", $"feito com {p.Label()}", Brand.Secondary, 10.5);
        l.ToolTip = "A IA do lote falhou e esta imagem foi gerada pela outra (troca automática ou refazer com outra IA).";
        return l;
    }

    private static UIElement ReviewBar(ReviewStatus review, bool canApprove, Action approve, Action discard, Action<string?> redo)
    {
        Button Icon(string text, Brush color, string tip, Action a, bool enabled = true)
        {
            var b = new Button
            {
                Content = U.T(text, 17, color: color),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4, 0, 4, 0),
                ToolTip = tip,
                IsEnabled = enabled,
                Cursor = System.Windows.Input.Cursors.Hand,
            };
            b.Click += (_, _) => a();
            return b;
        }
        var redoBtn = Icon("↻", Brand.Text, "Refazer (com observação opcional)", () => { });
        redoBtn.Click += (_, _) =>
        {
            var note = U.Field("", _ => { }, "Ex.: sobrou o @ no canto inferior", multiline: true, minHeight: 50);
            note.Width = 280;
            var pop = new Popup { PlacementTarget = redoBtn, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true };
            var go = U.Btn("Refazer", () =>
            {
                var n = note.Text.Trim();
                redo(n.Length == 0 ? null : n);
                pop.IsOpen = false;
            }, primary: true);
            var cancel = U.Btn("Cancelar", () => pop.IsOpen = false);
            pop.Child = new Border
            {
                Background = Brand.SurfaceRaised,
                BorderBrush = Brand.Stroke,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14),
                Child = U.V(8, U.T("Refazer", 15, bold: true), U.Caption("O que corrigir? (opcional)"), note,
                    U.Row(Array.Empty<UIElement>(), new UIElement[] { cancel, go })),
            };
            pop.IsOpen = true;
            note.Focus();
        };
        return U.H(6,
            Icon(review == ReviewStatus.Approved ? "✔" : "✓", review == ReviewStatus.Approved ? Brand.Success : Brand.Text, "Aprovar", approve, canApprove),
            redoBtn,
            Icon(review == ReviewStatus.Discarded ? "✖" : "✕", review == ReviewStatus.Discarded ? Brand.Red : Brand.Text, "Descartar", discard));
    }

    private void SetClean(Job job, JobItem item, ReviewStatus r)
    {
        var n = item.CleanReview == r ? ReviewStatus.Pending : r;
        Model.Jobs.UpdateItem(job.Id, item.Id, i => i.CleanReview = n);
        AppLog.Info(LogCategory.Revisao, $"Limpeza (v0): {ReviewText(n)}.", jobID: job.Id, jobName: job.Name, item: item.SourceName);
    }

    private void SetVariation(Job job, JobItem item, Guid id, ReviewStatus r)
    {
        var v = item.Variations.FirstOrDefault(x => x.Id == id);
        if (v == null) return;
        var n = v.Review == r ? ReviewStatus.Pending : r;
        Model.Jobs.UpdateVariation(job.Id, item.Id, id, x => x.Review = n);
        AppLog.Info(LogCategory.Revisao, $"Variação v{v.Index}: {ReviewText(n)}.", jobID: job.Id, jobName: job.Name, item: item.SourceName);
    }

    public static string ReviewText(ReviewStatus r) => r switch
    {
        ReviewStatus.Approved => "aprovada",
        ReviewStatus.Discarded => "descartada",
        _ => "voltou para pendente",
    };
}

/// <summary>Ver grande, com "Comparar com a referência".</summary>
public static class Preview
{
    public static void Show(Window? owner, string title, string path, string? compare)
    {
        var w = new Window
        {
            Title = title,
            Width = 1100,
            Height = 820,
            MinWidth = 760,
            MinHeight = 620,
            Background = Brand.Background,
            Owner = owner,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
        };
        var showCompare = false;
        var area = new Grid();
        void Fill()
        {
            area.Children.Clear();
            area.ColumnDefinitions.Clear();
            var cols = showCompare && compare != null ? new[] { ("Referência", compare), ("Resultado", path) } : new[] { ("", path) };
            foreach (var (label, p) in cols)
            {
                area.ColumnDefinitions.Add(new ColumnDefinition());
                var img = new Image { Stretch = Stretch.Uniform };
                RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                var dock = new DockPanel { Margin = new Thickness(6) };
                if (label.Length > 0)
                {
                    var t = U.Caption(label);
                    t.HorizontalAlignment = HorizontalAlignment.Center;
                    DockPanel.SetDock(t, Dock.Top);
                    dock.Children.Add(t);
                }
                dock.Children.Add(img);
                Grid.SetColumn(dock, area.ColumnDefinitions.Count - 1);
                area.Children.Add(dock);
                var file = p;
                Task.Run(() => Core.Imaging.ImageTools.ThumbnailPng(file, 1600)).ContinueWith(t => img.Source = U.FromPng(t.Result),
                    TaskScheduler.FromCurrentSynchronizationContext());
            }
        }
        var right = new List<UIElement>();
        if (compare != null) right.Add(U.Toggle("Comparar com a referência", false, v => { showCompare = v; Fill(); }));
        right.Add(U.Btn("Mostrar no Explorador", () => Shell.Reveal(path)));
        right.Add(U.Btn("Fechar", w.Close));
        var head = U.Row(new UIElement[] { U.T(title, 15, bold: true) }, right);
        var root = new DockPanel { Margin = new Thickness(18) };
        DockPanel.SetDock(head, Dock.Top);
        root.Children.Add(head);
        area.Margin = new Thickness(0, 12, 0, 0);
        root.Children.Add(area);
        w.Content = root;
        w.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) w.Close(); };
        Fill();
        w.ShowDialog();
    }
}
