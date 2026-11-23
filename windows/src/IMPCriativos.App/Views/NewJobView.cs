using System.Windows;
using System.Windows.Controls;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.App.Views;

/// <summary>
/// Novo lote (limpeza + variações) e, desde a 1.0.0-beta.20, o módulo "Limpar logo" (<c>cleanOnly</c>):
/// a mesma tela sem as variações, para limpar anúncios pegos na Biblioteca de Anúncios.
/// </summary>
public sealed class NewJobView : Page
{
    private readonly bool _cleanOnly;

    private string _name = "";
    private Guid? _clientID;
    private string? _folder;
    private List<string> _files = new();
    private int _variations = 4;
    private bool _axisTest;
    private bool _skipClean;
    private MetaFormat? _cleanSize;
    private ModelChoice _cleanAI = AIStage.Clean.DefaultAI().Primary;
    private ModelChoice _variationAI = AIStage.Variation.DefaultAI().Primary;
    private ModelChoice _analysisAI = AIStage.Analysis.DefaultAI().Primary;
    private MetaFormat _metaFormat = MetaFormat.Feed;
    private OutputFormat _format = OutputFormat.Jpg;
    private bool _verifyText = true;
    private string? _error;

    // Instruções do lote (1.0.0-beta.6)
    private string _instructionsText = "";
    private string? _interpretedRaw;
    private bool _interpreting;
    private string? _interpretNote;
    private string _removeText = "";
    private string _textChangesText = "";
    private string _directionText = "";

    /// <summary>Acima disso, o app pede confirmação antes de iniciar.</summary>
    public const int BigBatch = 60;

    private Button? _startButton;
    private ContentControl _footer = new();
    private ContentControl _interpretedArea = new();

    public NewJobView(bool cleanOnly)
    {
        _cleanOnly = cleanOnly;
        var s = Model.Settings;
        _cleanAI = s.Stage(AIStage.Clean).Primary;
        _variationAI = s.Stage(AIStage.Variation).Primary;
        _analysisAI = s.Stage(AIStage.Analysis).Primary;
        _metaFormat = s.DefaultFormat;
        _clientID = Model.Clients.Clients.FirstOrDefault()?.Id;
        if (Client is ClientProfile c) _variations = Math.Max(1, c.DefaultVariations);
    }

    protected override void Attach() =>
        Subscribe(() => Model.Clients.Changed += Invalidate, () => Model.Clients.Changed -= Invalidate);

    private ClientProfile? Client => Model.Clients.Client(_clientID);
    private ProviderKind CleanProvider => _cleanAI.Provider;
    private ProviderKind VariationProvider => _variationAI.Provider;
    private ProviderKind AnalysisProvider => _analysisAI.Provider;

    /// <summary>O lote passa pela limpeza? (Sempre no módulo "Limpar logo"; no lote normal, a menos que seja desligada.)</summary>
    private bool Cleaning => _cleanOnly || !_skipClean;

    private List<ProviderKind> UsedProviders => _cleanOnly
        ? new List<ProviderKind> { CleanProvider, AnalysisProvider }
        : (Cleaning ? new List<ProviderKind> { CleanProvider } : new List<ProviderKind>()).Concat(new[] { VariationProvider, AnalysisProvider }).ToList();

    private ProviderKind? MissingKey => UsedProviders.Where(p => !ApiKeyStore.HasKey(p)).Cast<ProviderKind?>().FirstOrDefault();

    private OutputSizeMode SizeMode => _cleanOnly ? (_cleanSize?.SizeMode() ?? OutputSizeMode.Original) : _metaFormat.SizeMode();

    private bool HasInstructions => _instructionsText.Trimmed().Length > 0;
    private bool NeedsInterpretation => HasInstructions && _interpretedRaw != _instructionsText;
    private List<string> SavedInstructions => Client?.SavedInstructions ?? new List<string>();

    private BatchInstructions? CurrentInstructions
    {
        get
        {
            if (!HasInstructions || NeedsInterpretation) return null;
            var remove = _removeText.Split('\n', '\r').Select(x => x.Trimmed()).Where(x => x.Length > 0).ToList();
            var ins = new BatchInstructions
            {
                Raw = _instructionsText.Trimmed(), RemoveItems = remove, TextChanges = _textChangesText.Trimmed(),
                Direction = _cleanOnly ? "" : _directionText.Trimmed(),
            };
            return ins.IsEmpty ? null : ins;
        }
    }

    private int AxesCount => Client is ClientProfile c ? (c.Axes.Count == 0 ? ClientProfile.DefaultAxes.Count : c.Axes.Count) : 0;
    private int EffectiveVariations => _cleanOnly ? 0 : (_axisTest ? AxesCount : _variations);
    private int TotalVariations => _files.Count * EffectiveVariations;

    private CostEstimator.Estimate Estimate => CostEstimator.Calculate(_files.Count, EffectiveVariations, CleanProvider, VariationProvider,
        _verifyText && !_cleanOnly, Model.Settings, Cleaning);

    private string TimeLabel
    {
        get
        {
            var snaps = SpeedMonitor.Shared.Snapshots;
            var lat = snaps.TryGetValue(_cleanOnly ? CleanProvider : VariationProvider, out var s) ? s.Latency : null;
            return CostEstimator.MinutesLabel(CostEstimator.Minutes(_files.Count, EffectiveVariations, Model.Settings, lat, Cleaning));
        }
    }

    protected override UIElement Render()
    {
        _footer = new ContentControl();
        _interpretedArea = new ContentControl();
        var root = new StackPanel { MaxWidth = 860, HorizontalAlignment = HorizontalAlignment.Left };
        U.Add(root, _cleanOnly
            ? U.Header("Limpar logo", "Só remove o logo e o nome da empresa dos anúncios (ex.: pegos na Biblioteca de Anúncios). Não cria variações.")
            : U.Header("Novo lote", "Escolha o cliente, a pasta dos criativos e como processar."), 0);

        // Lote
        var clients = Model.Clients.Clients;
        var client = Client;
        var clientRow = U.H(8,
            U.Combo(new Guid?[] { null }.Concat(clients.Select(c => (Guid?)c.Id)), _clientID,
                id => id == null ? "Selecione…" : clients.First(c => c.Id == id).Name,
                id =>
                {
                    _clientID = id;
                    if (Client is ClientProfile c) _variations = Math.Max(1, c.DefaultVariations);
                    Rerender();
                }, 260),
            U.Btn("Gerenciar clientes", () => Model.Selection = new SidebarItem.Clients()));
        var loteRows = new List<UIElement?>
        {
            U.Labeled("Nome do lote", Sized(U.Field(_name, v => _name = v, _cleanOnly ? "Ex.: Biblioteca novembro" : "Ex.: Hilux novembro"), 420)),
            U.Labeled("Cliente", clientRow),
        };
        if (client != null)
        {
            loteRows.Add(U.Caption($"Remove {client.RemoveItems.Count} itens · {client.Axes.Count} eixos de variação"));
            if (client.HasPlaceholderTerms)
                loteRows.Add(U.H(8, U.Warning("Este cliente ainda tem os nomes de exemplo (\"Minha Bet\", @minhabet). Troque pelos nomes reais para a limpeza saber o que remover."),
                    U.Btn("Editar cliente", () => Model.Selection = new SidebarItem.Clients())));
        }
        U.Add(root, U.Section("Lote", loteRows.ToArray()), 18);

        // Criativos
        var folderInfo = U.V(2, U.T(_folder != null ? Path.GetFileName(_folder) : "Nenhuma pasta escolhida"),
            _folder != null ? U.Caption(_folder) : null);
        var crRows = new List<UIElement?> { U.Row(new UIElement[] { folderInfo }, new UIElement[] { U.Btn("Escolher pasta…", PickFolder) }) };
        if (_folder != null)
            crRows.Add(U.T(_files.Count == 0 ? "Nenhuma imagem (JPG, PNG, WEBP, HEIC) encontrada nessa pasta." : $"{_files.Count} imagens encontradas",
                12.5, color: _files.Count == 0 ? Brand.Warning : Brand.Secondary));
        U.Add(root, U.Section("Criativos", crRows.ToArray()), 12);

        if (_cleanOnly)
        {
            U.Add(root, U.Section("Limpeza",
                U.Labeled("IA da limpeza", ModelMenu.Create(ModelRole.Image, _cleanAI, c => { if (c != null) { _cleanAI = c; Rerender(); } })),
                U.Labeled("IA das checagens", ModelMenu.Create(ModelRole.Text, _analysisAI, c => { if (c != null) { _analysisAI = c; Rerender(); } })),
                U.Caption("Remove o que está na lista do cliente (logo, nome, @, site…) mais o que você pedir abaixo. Depois, a checagem lê a imagem limpa e, se ainda sobrar marca, refaz a limpeza sozinha uma vez.")), 12);
        }
        else
        {
            var rows = new List<UIElement?>
            {
                U.Labeled("Modo do lote", U.Segmented(new[] { false, true }, _axisTest, t => t ? "Teste de eixos" : "Normal", t => { _axisTest = t; Rerender(); })),
            };
            if (!_axisTest)
            {
                rows.Add(U.Labeled($"Variações por criativo: {_variations}", U.H(6,
                    U.Btn("−", () => { _variations = Math.Max(1, _variations - 1); Rerender(); }),
                    U.Btn("+", () => { _variations = Math.Min(10, _variations + 1); Rerender(); }))));
            }
            else
            {
                rows.Add(U.V(4,
                    U.T($"Cada criativo passa por todos os {AxesCount} eixos do cliente, na ordem da lista (sem rodízio), com uma limpeza só."),
                    U.T(_files.Count == 1
                            ? $"1 imagem → {AxesCount} variações. Na revisão e na exportação cada variação leva o número e o nome do eixo, para comparar."
                            : $"{_files.Count} imagens → {TotalVariations} variações. Para comparar os eixos, o ideal é usar 1 imagem.",
                        11.5, color: _files.Count > 1 ? Brand.Warning : Brand.Secondary),
                    U.Caption("Para escolher os eixos testados, marque-os em Clientes → Eixos de variação (Catálogo do app ou Meus eixos).")));
            }
            var cleanToggle = U.V(4, U.Toggle("Limpar logo e nome antes das variações", !_skipClean, v => { _skipClean = !v; Rerender(); }));
            if (_skipClean)
                cleanToggle.Children.Add(U.T("Limpeza desligada: as imagens da pasta já vêm limpas e vão direto para as variações, sem custo de limpeza. A checagem ainda lê cada imagem; se achar marca, só avisa na revisão (dá para usar Refazer na limpeza daquela imagem).",
                    11.5, color: Brand.Warning));
            rows.Add(cleanToggle);
            if (Cleaning)
                rows.Add(U.Labeled("IA da limpeza", ModelMenu.Create(ModelRole.Image, _cleanAI, c => { if (c != null) { _cleanAI = c; Rerender(); } })));
            rows.Add(U.Labeled("IA das variações", ModelMenu.Create(ModelRole.Image, _variationAI, c => { if (c != null) { _variationAI = c; Rerender(); } })));
            rows.Add(U.Labeled("IA das checagens", ModelMenu.Create(ModelRole.Text, _analysisAI, c => { if (c != null) { _analysisAI = c; Rerender(); } })));
            rows.Add(U.Toggle("Conferir o texto de cada variação", _verifyText, v => { _verifyText = v; UpdateFooter(); }));
            U.Add(root, U.Section("Processamento", rows.ToArray()), 12);
        }

        U.Add(root, InstructionsSection(), 12);

        // Saída
        UIElement size = _cleanOnly
            ? U.Combo(new MetaFormat?[] { null, MetaFormat.Feed, MetaFormat.Story }, _cleanSize,
                f => f == null ? "Manter o tamanho original" : f.Value.Label(), f => { _cleanSize = f; }, 320)
            : U.Combo(MetaFormatExt.All, _metaFormat, f => f.Label(), f => { _metaFormat = f; }, 320);
        U.Add(root, U.Section("Saída",
            U.Labeled("Tamanho", size),
            U.Labeled("Formato", U.Segmented(new[] { OutputFormat.Jpg, OutputFormat.Png }, _format, f => f.Label(), f => { _format = f; Rerender(); }))), 12);

        U.Add(root, _footer, 18);
        U.Add(root, U.Caption("Valores estimados com a tabela de preços das Configurações. O custo real é cobrado pelo Google/OpenAI na sua conta."), 8);
        if (_error != null) U.Add(root, U.Error(_error), 8);
        UpdateFooter();
        return U.Scroll(root);
    }

    private static FrameworkElement Sized(FrameworkElement e, double w) { e.Width = w; return e; }

    /// <summary>Estimativa e botão de iniciar (atualizados sem redesenhar a tela, para não perder o que está sendo digitado).</summary>
    private void UpdateFooter()
    {
        var est = Estimate;
        var left = U.V(4,
            U.Caption("Estimativa"),
            U.T(est.Usd.Usd(), 26, weight: FontWeights.SemiBold),
            U.Caption($"{est.ImageCalls} imagens geradas · {est.AnalysisCalls} checagens" + (Model.Settings.PlanningEnabled ? $" · {_files.Count} planejamentos" : "")),
            _files.Count > 0 ? U.Caption($"Tempo: {TimeLabel}" + (Model.Settings.FastMode ? " · modo rápido com segurança" : " · velocidade original")) : null);
        var right = new List<UIElement>();
        if (MissingKey is ProviderKind k)
            right.Add(U.V(4, U.Warning($"Falta a chave do {k.Label()}"), U.Btn("Configurar chave", () => Model.Selection = new SidebarItem.Settings())));
        _startButton = U.Btn(NeedsInterpretation ? "🔍  Interpretar instruções" : (_cleanOnly ? "▶  Iniciar limpeza" : "▶  Iniciar lote"), OnStart,
            primary: true, enabled: Client != null && _files.Count > 0 && MissingKey == null && !_interpreting);
        _startButton.Padding = new Thickness(18, 8, 18, 8);
        right.Add(_startButton);
        _footer.Content = U.Card(U.Row(new UIElement[] { left }, right, 20));
    }

    private void OnStart()
    {
        if (NeedsInterpretation) { Interpret(); return; }
        if (TotalVariations > BigBatch)
        {
            var est = Estimate;
            if (!Confirm($"Lote grande: {TotalVariations} variações",
                    $"{_files.Count} criativo(s) × {EffectiveVariations} variações. Custo estimado {est.Usd.Usd()} e tempo {TimeLabel}. Dá para pausar a qualquer momento sem perder o que já foi feito.\n\nIniciar ({est.Usd.Usd()}, {TimeLabel})?"))
                return;
        }
        StartJob();
    }

    private void PickFolder()
    {
        var f = Pickers.Folder("Pasta com os criativos");
        if (f == null) return;
        _folder = f;
        _files = Paths.ListImages(f);
        if (_name.Length == 0) _name = Path.GetFileName(f);
        Rerender();
    }

    private void StartJob()
    {
        if (Client is not ClientProfile client || _folder is not string folder) return;
        _error = null;
        var jobName = _name.Trim().Length == 0
            ? $"{client.Name}{(_cleanOnly ? " limpeza" : (_axisTest ? " teste de eixos" : ""))} {Short(DateTime.UtcNow)}"
            : _name;
        var axisTest = !_cleanOnly && _axisTest;
        try
        {
            var job = Model.Jobs.CreateJob(jobName, client, folder, _files, _variations, CleanProvider, VariationProvider, AnalysisProvider,
                SizeMode, _format, _verifyText && !_cleanOnly, CurrentInstructions, axisTest, _cleanOnly, !_cleanOnly && _skipClean);
            AppLog.Info(LogCategory.Lote, $"Lote criado: {_files.Count} criativos de {Path.GetFileName(folder)}.",
                details: $"Cliente: {client.Name} · {(_cleanOnly ? "só limpeza (módulo Limpar logo)" : (axisTest ? $"teste de eixos: {job.VariationsPerItem} eixos por criativo" : $"{_variations} variações"))} · {(Cleaning ? "limpeza ligada" : "limpeza desligada (imagens já limpas)")} · {SizeMode.Label} {_format.Label()}"
                         + (_cleanOnly ? "" : $" · checagem de texto: {(_verifyText ? "sim" : "não")}")
                         + (job.Instructions is BatchInstructions ins ? $"\nInstruções: {ins.Raw}\n{ins.Summary}" : ""),
                jobID: job.Id, jobName: job.Name);
            // a escolha do lote vira a principal de cada etapa (a reserva continua a de Configurações)
            if (Cleaning) Model.Settings.AdoptForBatch(_cleanAI, AIStage.Clean);
            if (!_cleanOnly)
            {
                Model.Settings.AdoptForBatch(_variationAI, AIStage.Variation);
                Model.Settings.DefaultFormat = _metaFormat;
            }
            Model.Settings.AdoptForBatch(_analysisAI, AIStage.Analysis);
            Model.Runner.Start(job.Id);
            // limpa o formulário para o próximo lote
            _folder = null;
            _files = new List<string>();
            _name = "";
            ClearInstructions();
            Model.Selection = new SidebarItem.JobItem(job.Id);
        }
        catch (Exception e)
        {
            _error = $"Não foi possível criar o lote: {e.Message}";
            AppLog.Error(LogCategory.Lote, $"Não foi possível criar o lote: {e.Message}", details: folder);
            Rerender();
        }
    }

    // MARK: Instruções do lote

    private UIElement InstructionsSection()
    {
        var box = U.Field(_instructionsText, v =>
            {
                _instructionsText = v;
                UpdateInterpreted();
                UpdateFooter();
            },
            _cleanOnly ? "Ex.: tirar também o nome Aviator e o selo do canto"
                       : "Ex.: tirar todo nome Aviator, tirar o nome X, adicionar o nome Y no topo, criar ângulos bem diferentes e variados",
            multiline: true, minHeight: 70);
        box.MaxHeight = 140;

        var saved = SavedInstructions;
        var savedMenu = new Button { Content = "Instruções salvas  ▾", IsEnabled = saved.Count > 0, Padding = new Thickness(12, 5, 12, 5) };
        savedMenu.Click += (_, _) =>
        {
            var m = new ContextMenu { PlacementTarget = savedMenu };
            foreach (var t in saved)
            {
                var mi = new MenuItem { Header = MenuTitle(t) };
                var text = t;
                mi.Click += (_, _) => { box.Text = text; };
                m.Items.Add(mi);
            }
            if (saved.Count > 0)
            {
                m.Items.Add(new Separator());
                var del = new MenuItem { Header = "Apagar" };
                foreach (var t in saved)
                {
                    var mi = new MenuItem { Header = MenuTitle(t) };
                    var text = t;
                    mi.Click += (_, _) => DeleteSaved(text);
                    del.Items.Add(mi);
                }
                m.Items.Add(del);
            }
            m.IsOpen = true;
        };
        var saveBtn = U.Btn("Salvar no cliente", SaveToClient, tooltip: "Guarda este texto no perfil do cliente para usar em outros lotes",
            enabled: Client != null && HasInstructions && !saved.Contains(_instructionsText.Trimmed()));
        var actions = U.Row(new UIElement[]
        {
            U.Btn("🔍  Interpretar", Interpret, enabled: HasInstructions && !_interpreting),
            _interpreting ? U.Caption("Lendo as instruções…") : null!,
        }.Where(x => x != null), new UIElement[] { savedMenu, saveBtn });

        UpdateInterpreted();
        var card = U.V(8, box, actions, _interpretedArea);
        var footer = U.Caption(_cleanOnly
            ? "Valem só para esta limpeza, somadas à lista do cliente. O que for para remover entra na limpeza e na checagem."
            : "Valem só para este lote, somadas ao perfil do cliente. O que for para remover entra na limpeza e nas checagens; alterações de texto viram o texto esperado das variações; o resto orienta as variações.");
        return U.V(8, U.T("Instruções para este lote (opcional)", 13, bold: true, color: Brand.Secondary), U.Card(card, 14), footer);
    }

    private void UpdateInterpreted()
    {
        if (HasInstructions && !NeedsInterpretation)
        {
            var s = U.V(8, U.Divider(), U.Caption("Confira como o app entendeu. Você pode editar antes de iniciar."),
                InstructionField("Remover também (limpeza e checagens)", _removeText, v => _removeText = v, "Um item por linha. Ex.: Nome Aviator (em qualquer lugar)"),
                InstructionField("Alterar o texto dos criativos", _textChangesText, v => _textChangesText = v, "Ex.: incluir o nome \"Nome Novo\" no topo"),
                _cleanOnly ? null : InstructionField("Direção das variações", _directionText, v => _directionText = v, "Ex.: ângulos bem diferentes e variados"),
                _interpretNote != null ? U.Warning(_interpretNote) : null);
            _interpretedArea.Content = s;
        }
        else if (NeedsInterpretation && _interpretedRaw != null)
        {
            _interpretedArea.Content = U.Warning("O texto mudou. Clique em Interpretar de novo.");
        }
        else _interpretedArea.Content = null;
    }

    private static UIElement InstructionField(string title, string value, Action<string> set, string prompt) =>
        U.V(4, U.T(title, 11.5, bold: true), U.Field(value, set, prompt, multiline: true, minHeight: 30));

    private static string MenuTitle(string t)
    {
        var one = t.Replace("\n", " ");
        return one.Length > 70 ? one[..70] + "…" : one;
    }

    private void Apply(BatchInstructions ins)
    {
        _removeText = string.Join("\n", ins.RemoveItems);
        _textChangesText = ins.TextChanges;
        _directionText = ins.Direction;
    }

    private async void Interpret()
    {
        var raw = _instructionsText;
        if (raw.Trimmed().Length == 0 || _interpreting) return;
        _interpreting = true;
        _interpretNote = null;
        Rerender();
        try
        {
            var (ins, used) = await InstructionInterpreter.Interpret(raw.Trimmed(), AnalysisProvider, Model.Settings);
            if (_instructionsText != raw) return; // mudou enquanto interpretava
            Apply(ins);
            if (ins.IsEmpty) _interpretNote = "Nada aproveitável nessas instruções. Preencha os campos à mão se quiser.";
            _interpretedRaw = raw;
            AppLog.Info(LogCategory.Lote, $"Instruções do lote interpretadas com {used.Label()}.", details: $"{raw.Trimmed()}\n\n{ins.Summary}");
        }
        catch (Exception e)
        {
            if (_instructionsText != raw) return;
            Apply(new BatchInstructions { Raw = raw.Trimmed(), Direction = raw.Trimmed() });
            _interpretNote = $"Não consegui interpretar ({e.Message}). Coloquei tudo em Direção das variações; ajuste os campos se precisar.";
            _interpretedRaw = raw;
            AppLog.Warning(LogCategory.Lote, "Não foi possível interpretar as instruções do lote.",
                details: string.Join("\n\n", new[] { raw.Trimmed(), e.Message, e.AiDetails() }.Where(x => x != null)));
        }
        finally
        {
            _interpreting = false;
            Rerender();
        }
    }

    private void ClearInstructions()
    {
        _instructionsText = "";
        _interpretedRaw = null;
        _interpretNote = null;
        _removeText = "";
        _textChangesText = "";
        _directionText = "";
    }

    private void SaveToClient()
    {
        if (Client is not ClientProfile c) return;
        var t = _instructionsText.Trimmed();
        var list = c.SavedInstructions ?? new List<string>();
        list.RemoveAll(x => x == t);
        list.Insert(0, t);
        c.SavedInstructions = list.Take(20).ToList();
        Model.Clients.Save(c);
        AppLog.Info(LogCategory.Clientes, $"Instrução de lote salva no cliente {c.Name}.", details: t);
        Rerender();
    }

    private void DeleteSaved(string t)
    {
        if (Client is not ClientProfile c) return;
        c.SavedInstructions = (c.SavedInstructions ?? new List<string>()).Where(x => x != t).ToList();
        Model.Clients.Save(c);
        Rerender();
    }
}
