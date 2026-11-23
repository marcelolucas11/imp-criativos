using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App.Views;

public sealed class SettingsView : Page
{
    private AppSettings S => Model.Settings;
    private string? _startupError;
    private readonly Dictionary<ProviderKind, (string? Status, bool Ok, bool Testing)> _keys = new();

    protected override void Attach()
    {
        Subscribe(() => Model.Updater.Changed += Invalidate, () => Model.Updater.Changed -= Invalidate);
        Subscribe(() => ModelCatalog.Shared.Changed += Invalidate, () => ModelCatalog.Shared.Changed -= Invalidate);
        Subscribe(() => SpeedMonitor.Shared.Changed += Invalidate, () => SpeedMonitor.Shared.Changed -= Invalidate);
        S.ApplySpeed();
        _ = ModelCatalog.Shared.RefreshIfStale();
    }

    private static UIElement Desc(string title, string help) => U.V(2, U.T(title), U.Caption(help));

    private UIElement Stepper(string label, int value, int min, int max, Action<int> set, string? help = null)
    {
        var row = U.H(10, U.Btn("−", () => { set(Math.Max(min, value - 1)); Rerender(); }, enabled: value > min),
            U.Btn("+", () => { set(Math.Min(max, value + 1)); Rerender(); }, enabled: value < max), U.T(label));
        return help == null ? row : U.V(2, row, U.Caption(help));
    }

    private static CheckBox ToggleDesc(string title, string help, bool value, Action<bool> set)
    {
        var c = new CheckBox { Content = Desc(title, help), IsChecked = value, VerticalContentAlignment = VerticalAlignment.Top };
        c.Checked += (_, _) => set(true);
        c.Unchecked += (_, _) => set(false);
        return c;
    }

    protected override UIElement Render()
    {
        var root = new StackPanel { MaxWidth = 820, HorizontalAlignment = HorizontalAlignment.Left };
        U.Add(root, U.Title("Configurações"), 0);

        // Chaves de API
        U.Add(root, U.V(8, U.Section("Chaves de API",
                KeyRow(ProviderKind.Gemini, "Crie em aistudio.google.com → Get API key"),
                KeyRow(ProviderKind.Openai, "Crie em platform.openai.com → API keys")),
            U.Caption("As chaves ficam salvas só neste computador, cifradas pelo Windows para a sua conta (ninguém mais consegue ler). Nunca vão para o GitHub nem para outro lugar. Cada pessoa usa as próprias chaves.")), 18);

        // Comportamento
        var startup = ToggleDesc("Iniciar com o Windows", "Abre na bandeja ao entrar no Windows (Configurações do Windows → Aplicativos → Inicialização).",
            StartupItem.IsEnabled, v =>
            {
                try { StartupItem.Set(v); _startupError = null; }
                catch (Exception e) { _startupError = e.Message; Rerender(); }
            });
        U.Add(root, U.Section("Comportamento",
            ToggleDesc("Continuar em segundo plano", "Ao fechar a janela, o lote continua e o app fica na bandeja, perto do relógio.", S.RunInBackground, v => S.RunInBackground = v),
            startup,
            _startupError != null ? U.Warning(_startupError) : null,
            U.Toggle("Avisar por notificação quando um lote terminar", S.NotifyOnFinish, v => S.NotifyOnFinish = v)), 14);

        // Processamento
        U.Add(root, U.Section("Processamento",
            Stepper($"Criativos processados ao mesmo tempo: {S.MaxConcurrent}", S.MaxConcurrent, 1, 8, v => S.MaxConcurrent = v),
            U.Row(new UIElement[] { U.V(2, U.T("Pasta padrão de saída"), U.Caption(S.DefaultOutputFolder)) },
                new UIElement[] { U.Btn("Alterar…", () =>
                {
                    if (Pickers.Folder("Pasta padrão de saída", S.DefaultOutputFolder) is string f) { S.DefaultOutputFolder = f; Rerender(); }
                }) })), 14);

        U.Add(root, SpeedSection(), 14);

        // Erros e tentativas
        var errRows = new List<UIElement?>
        {
            Stepper($"Tentativas em erro temporário: {S.RetryAttempts}", S.RetryAttempts, 1, 10, v => S.RetryAttempts = v,
                "Esperas crescentes: ~2s, 5s, 10s, 20s, 40s… (respeita o tempo pedido pelo servidor)."),
            ToggleDesc("Trocar para a reserva automaticamente quando a IA principal falhar",
                "A etapa é refeita com a reserva escolhida em Modelos de IA (erro, sobrecarga, modelo não encontrado…).", S.FallbackEnabled,
                v => { S.FallbackEnabled = v; Rerender(); }),
        };
        var blocked = ToggleDesc("Trocar também quando a imagem for bloqueada pelo filtro de conteúdo", "Útil quando uma IA recusa o criativo e a reserva aceita.",
            S.FallbackOnBlocked, v => S.FallbackOnBlocked = v);
        blocked.IsEnabled = S.FallbackEnabled;
        errRows.Add(blocked);
        if (S.FallbackEnabled && AIStageExt.All.Any(st => S.Stage(st).Backup is ModelChoice b && !ApiKeyStore.HasKey(b.Provider)))
            errRows.Add(U.Warning("Alguma reserva é de uma plataforma sem chave salva; nessa etapa não haverá troca."));
        U.Add(root, U.V(8, U.Section("Erros e tentativas", errRows.ToArray()), U.Caption("Cada tentativa, troca de IA e erro fica registrado em Histórico.")), 14);

        // Modelos de IA
        var models = new List<UIElement?>();
        foreach (var st in AIStageExt.All)
        {
            var row = StageRow(st);
            if (st == AIStage.Planning && !S.PlanningEnabled) { row.IsEnabled = false; row.Opacity = 0.5; }
            models.Add(row);
        }
        models.Add(U.Toggle("Planejar cada criativo com IA mais forte (recomendado)", S.PlanningEnabled, v => { S.PlanningEnabled = v; Rerender(); }));
        models.Add(U.Labeled("OpenAI — qualidade da imagem", U.Combo(new[] { "low", "medium", "high" }, S.OpenaiQuality,
            q => q switch { "low" => "Baixa", "high" => "Alta", _ => "Média" }, v => S.OpenaiQuality = v, 160)));
        models.Add(U.Labeled("Formato do criativo", U.Combo(MetaFormatExt.All, S.DefaultFormat, f => f.Label(), v => S.DefaultFormat = v, 300)));
        var cat = ModelCatalog.Shared;
        var refreshRow = U.Row(new UIElement?[]
        {
            U.Btn("↻ Atualizar lista de modelos", () => _ = cat.Refresh(), enabled: !cat.Refreshing),
            cat.Refreshing ? U.Caption("Atualizando…") : cat.LastUpdated is DateTime d ? U.Caption($"Atualizada {Short(d)}") : null,
        }, new UIElement[] { U.Btn("Restaurar modelos padrão", () => { S.ResetModels(); Rerender(); }) });
        models.Add(refreshRow);
        if (cat.LastError != null) models.Add(U.Warning(cat.LastError));
        U.Add(root, U.V(8, U.Section("Modelos de IA", models.ToArray()),
            U.Caption("Clique no modelo para escolher a plataforma e a versão de cada etapa, e qual IA assume se ela der erro. A lista já traz todos os modelos de cada plataforma que funcionam no app, mesmo sem chave; lançamentos novos que a sua chave enxergar aparecem no fim (\"Atualizar lista\"). O planejamento também interpreta as instruções do lote.")), 14);

        // Preços
        U.Add(root, U.V(8, U.Section("Tabela de preços (estimativa)",
                Price("Gemini — por imagem (US$)", S.PriceGeminiImage, v => S.PriceGeminiImage = v, "0.000"),
                Price("OpenAI — por imagem (US$)", S.PriceOpenAIImage, v => S.PriceOpenAIImage = v, "0.000"),
                Price("Checagem/análise (US$)", S.PriceAnalysis, v => S.PriceAnalysis = v, "0.0000"),
                Price("Planejamento por criativo (US$)", S.PricePlanning, v => S.PricePlanning = v, "0.000")),
            U.Caption("Usada só para estimar o custo antes do lote e somar o gasto. Ajuste conforme o preço atual do seu plano.")), 14);

        // Avisos do criativo
        U.Add(root, U.V(8, U.Section("Avisos do criativo",
                ToggleDesc("Manter avisos 18+ e de jogo responsável", S.KeepWarningNotices
                        ? "Ligado: o app mantém o 18+, o \"Jogue com responsabilidade\" e advertências que já estão no criativo."
                        : "Desligado: o app remove o 18+, o \"Jogue com responsabilidade\" e advertências na limpeza, e as variações não os recriam.",
                    S.KeepWarningNotices, v => { S.KeepWarningNotices = v; Rerender(); })),
            U.Caption("Vale para os próximos lotes e para o que for refeito. Vem desligado de fábrica.")), 14);

        // Atualizações
        U.Add(root, U.Section("Atualizações",
            U.Labeled("Versão instalada", U.T(AppInfo.Version)),
            U.Toggle("Receber versões beta", S.IncludeBetaUpdates, v => S.IncludeBetaUpdates = v),
            U.Toggle("Buscar atualização ao abrir o app", S.CheckUpdatesOnLaunch, v => S.CheckUpdatesOnLaunch = v),
            UpdateRow()), 14);

        // Sobre
        U.Add(root, U.Section("Sobre",
            U.Labeled("Feito para", U.T(Niche.Summary)),
            U.Labeled("Repositório", U.Link($"github.com/{AppInfo.UpdateRepo}", () => Shell.Open($"https://github.com/{AppInfo.UpdateRepo}"))),
            U.Labeled("Dados locais", U.Btn("Abrir pasta", () => Shell.Open(Paths.AppSupport)))), 14);
        return U.Scroll(root);
    }

    private UIElement Price(string label, double value, Action<double> set, string fmt)
    {
        var f = U.Field(value.ToString(fmt, CultureInfo.InvariantCulture), t =>
        {
            if (double.TryParse(t.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v)) set(v);
        });
        f.Width = 90;
        return U.Labeled(label, f, 260);
    }

    private FrameworkElement StageRow(AIStage stage)
    {
        var v = S.Stage(stage);
        var s = U.V(8, U.V(2, U.T(stage.Label(), bold: true), U.Caption(stage.Help())),
            U.Labeled("IA principal", ModelMenu.Create(stage.Role(), v.Primary, c => { if (c != null) { S.SetPrimary(c, stage); Rerender(); } })),
            U.Labeled("Reserva se der erro", ModelMenu.Create(stage.Role(), v.Backup, c => { S.SetBackup(c, stage); Rerender(); }, allowNone: true)));
        if (v.Backup is ModelChoice b && b == v.Primary)
            s.Children.Add(U.Warning("A reserva é igual à principal. Escolha outro modelo ou outra plataforma para ela."));
        else if (v.Backup is ModelChoice b2 && !ApiKeyStore.HasKey(b2.Provider))
            s.Children.Add(U.Warning($"Sem a chave do {b2.Provider.Label()}, a reserva não será usada."));
        else if (!ApiKeyStore.HasKey(v.Primary.Provider))
            s.Children.Add(U.Warning($"Falta a chave do {v.Primary.Provider.Label()} em Chaves de API."));
        s.Margin = new Thickness(0, 4, 0, 4);
        return s;
    }

    private UIElement KeyRow(ProviderKind provider, string help)
    {
        var hasKey = ApiKeyStore.HasKey(provider);
        _keys.TryGetValue(provider, out var st);
        var box = new PasswordBox { MinWidth = 260, Padding = new Thickness(6, 4, 6, 4) };
        var shown = U.Field("", _ => { }, hasKey ? "Chave salva — cole outra para trocar" : "Cole a chave aqui");
        shown.MinWidth = 260;
        shown.Visibility = Visibility.Collapsed;
        var hint = U.Caption(hasKey ? "Chave salva — cole outra para trocar" : "Cole a chave aqui");
        string Value() => shown.Visibility == Visibility.Visible ? shown.Text : box.Password;
        void Save()
        {
            try
            {
                ApiKeyStore.Save(Value(), provider);
                AppLog.Info(LogCategory.Configuracoes, $"Chave do {provider.Label()} salva.");
                _keys[provider] = ("Chave salva neste computador.", true, false);
                _ = ModelCatalog.Shared.Refresh();
            }
            catch (Exception e)
            {
                _keys[provider] = (e.Message, false, false);
                AppLog.Error(LogCategory.Configuracoes, $"Falha ao salvar a chave do {provider.Label()}: {e.Message}");
            }
            Model.Poke();
            Rerender();
        }
        async void Test()
        {
            _keys[provider] = (st.Status, st.Ok, true);
            Rerender();
            try
            {
                var p = ProviderFactory.Make(new ModelChoice(provider, AIStage.Analysis.DefaultModel(provider)), new ProviderConfig(S));
                await p.TestKey();
                _keys[provider] = ("Chave funcionando.", true, false);
                AppLog.Success(LogCategory.Configuracoes, $"Teste da chave do {provider.Label()}: funcionando.");
            }
            catch (Exception e)
            {
                _keys[provider] = ($"Falhou: {e.Message}", false, false);
                AppLog.Error(LogCategory.Configuracoes, $"Teste da chave do {provider.Label()} falhou: {e.Message}",
                    details: string.Join("\n", new[] { e.AiDetails(), $"Sugestão: {e.AiKind().Hint()}" }.Where(x => x != null)));
            }
            Rerender();
        }
        var eye = U.Btn("👁", () =>
        {
            if (shown.Visibility == Visibility.Visible) { box.Password = shown.Text; shown.Visibility = Visibility.Collapsed; box.Visibility = Visibility.Visible; }
            else { shown.Text = box.Password; shown.Visibility = Visibility.Visible; box.Visibility = Visibility.Collapsed; }
        }, tooltip: "Mostrar o que foi colado");
        var paste = U.Btn("Colar", () =>
        {
            try { var t = Clipboard.GetText().Trim(); box.Password = t; shown.Text = t; } catch { }
        }, tooltip: "Cola a chave copiada");
        var save = U.Btn("Salvar", Save, primary: true);
        var test = U.Btn(st.Testing ? "Testando…" : "Testar", Test, enabled: hasKey && !st.Testing);
        var row = U.H(8, Sized(U.T(provider.Label(), wrap: false), 100), new Grid { Children = { box, shown } }, eye, paste, save, test);
        box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter && box.Password.Length > 0) Save(); };
        if (hasKey)
            row.Children.Add(U.Btn("🗑", () =>
            {
                ApiKeyStore.Delete(provider);
                AppLog.Warning(LogCategory.Configuracoes, $"Chave do {provider.Label()} removida.");
                _keys[provider] = ("Chave removida.", false, false);
                Model.Poke();
                Rerender();
            }, tooltip: "Remover chave"));
        var foot = st.Status != null ? U.IconText(st.Ok ? "✔" : "ℹ", st.Status, st.Ok ? Brand.Success : Brand.Secondary, 11.5) : (UIElement)U.Caption(help);
        return U.V(6, row, foot);
    }

    private static FrameworkElement Sized(FrameworkElement e, double w) { e.Width = w; return e; }

    private UIElement UpdateRow()
    {
        var up = Model.Updater;
        var status = up.State switch
        {
            Updater.StateKind.Idle when up.LastChecked is DateTime d => U.Caption($"Última verificação: {Short(d)}"),
            Updater.StateKind.Checking => U.Caption("Verificando…"),
            Updater.StateKind.UpToDate => U.IconText("✔", "Você está na versão mais recente.", Brand.Success),
            Updater.StateKind.Downloading => U.Caption("Baixando…"),
            Updater.StateKind.Installing => U.Caption("Instalando… o app vai reiniciar."),
            Updater.StateKind.Failed => U.Error(up.Error ?? "Erro"),
            _ => (UIElement?)null,
        };
        var busy = up.State is Updater.StateKind.Checking or Updater.StateKind.Downloading or Updater.StateKind.Installing;
        var s = U.V(10, U.H(10, U.Btn("⟳ Buscar atualização", () => _ = up.Check(S.IncludeBetaUpdates), enabled: !busy), status));
        if (up.AvailableRelease is ReleaseInfo r)
        {
            var head = U.Row(new UIElement?[]
            {
                U.T($"Versão {r.Version} disponível", 15, bold: true),
                r.Prerelease ? U.Pill("beta", Brand.RedColor) : null,
            }, new UIElement?[] { r.PageUrl != null ? U.Link("Ver no GitHub", () => Shell.Open(r.PageUrl)) : null });
            var notes = new TextBox
            {
                Text = r.Notes, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 160, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                BorderThickness = new Thickness(0), Background = System.Windows.Media.Brushes.Transparent, Foreground = Brand.Text,
            };
            var install = U.Btn("⬇ Instalar e reiniciar", () =>
            {
                if (Model.Runner.HasActiveWork)
                {
                    if (!Confirm("Há um lote em andamento", "O lote é retomado de onde parou depois que o app reiniciar.\n\nPausar o lote e atualizar?")) return;
                    Model.Runner.PauseAll();
                }
                _ = up.Install(r);
            }, primary: true, enabled: !busy);
            s.Children.Add(U.Card(U.V(8, head, r.Notes.Length > 0 ? notes : null, install), 12));
        }
        return s;
    }

    /// <summary>1.0.0-beta.19: velocidade original, Modo rápido com segurança e o estado de cada IA.</summary>
    private UIElement SpeedSection()
    {
        var rows = new List<UIElement?>
        {
            Stepper($"Velocidade original: {S.MaxImageRequests} pedidos de imagem ao mesmo tempo por IA", S.MaxImageRequests, 1, 6, v =>
            {
                S.MaxImageRequests = v;
                if (S.FastImageCeiling < v) S.FastImageCeiling = v;
                S.ApplySpeed();
            }, "Somando todos os lotes. É para onde o app volta quando algo indica risco."),
            ToggleDesc("Modo rápido com segurança automática",
                "Sobe um pedido por vez enquanto a IA responde bem. Ao primeiro sinal de risco (IA ocupada, limite de uso, tempo esgotado, IA mais lenta, computador sem espaço ou na bateria fraca, ou lote parado) volta na hora para a velocidade original e só tenta subir de novo depois de 10 minutos (30 se repetir).",
                S.FastMode, v => { S.FastMode = v; S.ApplySpeed(); Rerender(); }),
        };
        var ceiling = Stepper($"Teto do modo rápido: {Math.Max(S.FastImageCeiling, S.MaxImageRequests)} pedidos de imagem ao mesmo tempo por IA",
            S.FastImageCeiling, Math.Max(1, S.MaxImageRequests), 8, v => { S.FastImageCeiling = v; S.ApplySpeed(); },
            "Limite máximo, mesmo com tudo indo bem. Contas novas na OpenAI costumam ter limite baixo por minuto; o app desce sozinho se bater nele.");
        if (ceiling is FrameworkElement fe) fe.IsEnabled = S.FastMode;
        rows.Add(ceiling);
        foreach (var p in ProviderKindExt.All)
            if (SpeedMonitor.Shared.Snapshots.TryGetValue(p, out var snap))
                rows.Add(U.IconText(snap.InSafeMode ? "🛡" : "⏱", snap.Line, snap.InSafeMode ? Brand.Warning : Brand.Secondary, 11.5));
        return U.V(8, U.Section("Velocidade", rows.ToArray()),
            U.Caption("A velocidade só muda quantos pedidos vão juntos. Modelo, qualidade, prompts, checagens e refações continuam os mesmos, e cada imagem é conferida (abre no computador e está no disco) antes de contar como pronta. As variações de um mesmo criativo saem em paralelo até esse limite."));
    }
}
