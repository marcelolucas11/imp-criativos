using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Util;

namespace IMPCriativos.App.Views;

public sealed class ClientsView : Page
{
    private Guid? _selected;
    private ClientProfile? _original;
    private ClientProfile? _draft;
    private TextBlock? _savedFlash;
    private Button? _saveBtn, _discardBtn;

    public ClientsView()
    {
        _selected = Model.Clients.Clients.FirstOrDefault()?.Id;
    }

    private void Select(Guid? id)
    {
        _selected = id;
        _original = Model.Clients.Client(id);
        _draft = _original?.Clone();
        Rerender();
    }

    private bool Dirty => _draft != null && _original != null && Json.Serialize(_draft) != Json.Serialize(_original);

    private void UpdateButtons()
    {
        if (_saveBtn != null) _saveBtn.IsEnabled = Dirty;
        if (_discardBtn != null) _discardBtn.IsEnabled = Dirty;
    }

    protected override UIElement Render()
    {
        if (_draft == null || _draft.Id != _selected)
        {
            _original = Model.Clients.Client(_selected);
            _draft = _original?.Clone();
        }
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // lista
        var list = new StackPanel { Margin = new Thickness(0, 8, 0, 8) };
        foreach (var c in Model.Clients.Clients)
        {
            var row = new Border
            {
                Padding = new Thickness(14, 8, 14, 8),
                Margin = new Thickness(6, 1, 6, 1),
                CornerRadius = new CornerRadius(6),
                Background = c.Id == _selected ? Brand.SurfaceRaised : System.Windows.Media.Brushes.Transparent,
                Child = U.V(2, U.T(c.Name, 13, wrap: false), U.Caption($"{c.RemoveItems.Count} itens · {c.Axes.Count} eixos")),
                Cursor = Cursors.Hand,
            };
            var id = c.Id;
            row.MouseLeftButtonUp += (_, _) =>
            {
                if (Dirty && !Confirm("Clientes", "Há alterações não salvas neste cliente. Descartar?")) return;
                Select(id);
            };
            list.Children.Add(row);
        }
        var bottom = U.H(6,
            U.Btn("＋", () =>
            {
                var p = ClientProfile.NewProfile();
                Model.Clients.Save(p);
                AppLog.Info(LogCategory.Clientes, "Novo perfil de cliente criado.");
                Select(p.Id);
            }, tooltip: "Novo cliente"),
            U.Btn("⬇ Importar", ImportProfile, tooltip: "Importar perfil (.impcliente)"));
        bottom.Margin = new Thickness(8);
        var left = new DockPanel { Background = Brand.HeaderBackground };
        DockPanel.SetDock(bottom, Dock.Bottom);
        left.Children.Add(bottom);
        left.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        grid.Children.Add(left);

        UIElement right;
        if (_draft != null) right = Editor(_draft);
        else
        {
            var empty = U.V(10,
                U.T("👥", 40, color: Brand.Secondary),
                U.T("Selecione ou crie um cliente", color: Brand.Secondary),
                U.Caption("Cada cliente guarda o que remover, os eixos de variação e instruções extras.\nOs perfis ficam só no seu computador."));
            empty.HorizontalAlignment = HorizontalAlignment.Center;
            empty.VerticalAlignment = VerticalAlignment.Center;
            right = empty;
        }
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private void ImportProfile()
    {
        var path = Pickers.OpenFile("Importar perfil de cliente", "Perfil de cliente (*.impcliente;*.json)|*.impcliente;*.json");
        if (path == null) return;
        try
        {
            var p = Model.Clients.ImportProfile(path);
            AppLog.Info(LogCategory.Clientes, $"Perfil \"{p.Name}\" importado.", details: Path.GetFileName(path));
            Select(p.Id);
        }
        catch (Exception e)
        {
            Alert("Clientes", $"Arquivo inválido: {e.Message}");
            AppLog.Error(LogCategory.Clientes, $"Falha ao importar perfil: {e.Message}", details: path);
        }
    }

    private UIElement Editor(ClientProfile d)
    {
        var form = new StackPanel { MaxWidth = 900, HorizontalAlignment = HorizontalAlignment.Left };

        U.Add(form, U.Section("Cliente",
            U.Labeled("Nome", Sized(U.Field(d.Name, v => { d.Name = v; UpdateButtons(); }), 380)),
            U.Labeled($"Variações padrão por criativo: {d.DefaultVariations}", U.H(6,
                U.Btn("−", () => { d.DefaultVariations = Math.Max(1, d.DefaultVariations - 1); Rerender(); }),
                U.Btn("+", () => { d.DefaultVariations = Math.Min(10, d.DefaultVariations + 1); Rerender(); })))), 0);

        // O que remover
        var remove = new StackPanel();
        for (var i = 0; i < d.RemoveItems.Count; i++)
        {
            var idx = i;
            var f = U.Field(d.RemoveItems[i], v => { if (idx < d.RemoveItems.Count) d.RemoveItems[idx] = v; UpdateButtons(); }, "Item a remover");
            f.Width = 560;
            U.Add(remove, U.H(6, f, U.Btn("−", () => { if (idx < d.RemoveItems.Count) d.RemoveItems.RemoveAt(idx); Rerender(); })), 6);
        }
        U.Add(remove, U.Btn("＋ Adicionar item", () => { d.RemoveItems.Add(""); Rerender(); }), 8);
        U.Add(form, U.V(8, U.T("O que remover", 13, bold: true, color: Brand.Secondary), U.Card(remove, 14),
            U.Caption("Seja específico: \"Nome MinhaBet\", \"@minhabet\", \"site minhabet.bet.br\", \"logo da coroa dourada no topo\". Quanto mais claro, melhor a limpeza. Os avisos 18+ e de jogo responsável seguem a opção em Configurações → Avisos do criativo (de fábrica, são removidos).")), 14);

        // Eixos
        var axes = new StackPanel();
        for (var i = 0; i < d.Axes.Count; i++)
        {
            var axis = d.Axes[i];
            var pos = i;
            var name = U.Field(axis.Name, v => { axis.Name = v; UpdateButtons(); }, "Nome do eixo");
            name.Width = 300;
            name.FontWeight = FontWeights.SemiBold;
            var entry = AxisCatalog.Entry(axis);
            var tag = entry != null ? U.Caption($"Catálogo nº {entry.Number}") : U.Caption("Meu eixo");
            if (entry != null) tag.ToolTip = $"{entry.Family} · {entry.Change} · risco de texto {entry.TextRisk}";
            var order = U.T($"{pos + 1}º", 13, color: Brand.Secondary);
            order.Width = 28;
            order.ToolTip = $"Ordem de uso: v{pos + 1} usa este eixo";
            var up = U.Btn("▲", () => { Move(d, pos, -1); }, tooltip: "Subir (usar antes)", enabled: pos > 0);
            var down = U.Btn("▼", () => { Move(d, pos, 1); }, tooltip: "Descer (usar depois)", enabled: pos < d.Axes.Count - 1);
            var del = U.Btn("−", () => { d.Axes.RemoveAll(a => a.Id == axis.Id); Rerender(); });
            var instr = U.Field(axis.Instruction, v => { axis.Instruction = v; UpdateButtons(); }, "Instrução para a IA", multiline: true, minHeight: 40);
            instr.Foreground = Brand.Secondary;
            instr.Width = 760;
            U.Add(axes, U.V(6, U.H(8, order, name, tag, up, down, del), instr), i == 0 ? 0 : 12);
        }
        var axisButtons = U.Row(new UIElement[]
        {
            U.Btn("▦ Catálogo do app", () => { new AxisCatalogWindow(d.Axes) { Owner = Window.GetWindow(this) }.ShowDialog(); Rerender(); },
                tooltip: $"Abre os {AxisCatalog.BuiltIn.Length} eixos que vêm com o app, com família, o que muda e risco de texto"),
            U.Btn("◫ Meus eixos", () => { new CustomAxesWindow(d.Axes, Model.CustomAxes) { Owner = Window.GetWindow(this) }.ShowDialog(); Rerender(); },
                tooltip: "Abre a biblioteca dos eixos que você criou"),
            U.Btn("＋ Adicionar eixo", () => { d.Axes.Add(new VariationAxis("Novo eixo", "Describe how this variation should differ.")); Rerender(); }),
        }, new UIElement[]
        {
            U.Btn($"Usar os {ClientProfile.DefaultAxes.Count} padrão", () => { d.Axes = ClientProfile.DefaultAxes; Rerender(); },
                tooltip: $"Troca a lista deste cliente pelos {ClientProfile.DefaultAxes.Count} eixos do catálogo. Só vale depois de Salvar."),
        });
        U.Add(axes, axisButtons, 14);
        var rotation = U.Toggle("Rodízio", d.RotatesAxes, v => { d.RotatesAxes = v; Rerender(); },
            "Ligado: cada criativo do lote usa os próximos eixos da lista. Desligado: todo criativo usa os primeiros eixos da lista.");
        var axesHeader = U.Row(new UIElement[] { U.T("Eixos de variação", 13, bold: true, color: Brand.Secondary), U.Caption($"· {d.Axes.Count} na lista") },
            new UIElement[] { rotation });
        U.Add(form, U.V(8, axesHeader, U.Card(axes, 14), U.Caption(d.RotatesAxes
            ? "Rodízio ligado: com 4 variações, o 1º criativo usa os eixos 1 a 4, o 2º usa 5 a 8, e assim por diante; no fim da lista, recomeça. Cada eixo é uma direção de arte completa; o app já garante o mesmo jogo ou esporte, o mesmo personagem 3D, o texto exato e nenhuma promessa nova."
            : "Rodízio desligado: todo criativo usa os primeiros eixos da lista, na ordem (v1 = 1º eixo, v2 = 2º…). Os demais eixos da lista não são usados. O app já garante o mesmo jogo ou esporte, o mesmo personagem 3D, o texto exato e nenhuma promessa nova.")), 14);

        var extra = U.Field(d.ExtraInstructions, v => { d.ExtraInstructions = v; UpdateButtons(); },
            "Ex.: nunca mudar as odds nem o valor do bônus; manter o mascote do jogo", multiline: true, minHeight: 60);
        U.Add(form, U.V(8, U.T("Instruções extras", 13, bold: true, color: Brand.Secondary), U.Card(extra, 14),
            U.Caption("Vão junto em todas as etapas deste cliente.")), 14);

        // barra de baixo
        _savedFlash = U.T("Salvo", color: Brand.Success);
        _savedFlash.Visibility = Visibility.Collapsed;
        _discardBtn = U.Btn("Descartar alterações", () => { _draft = _original?.Clone(); Rerender(); }, enabled: Dirty);
        _saveBtn = U.Btn("Salvar", () => Save(d), primary: true, enabled: Dirty);
        var bar = U.Row(new UIElement[]
        {
            U.Btn("🗑 Excluir", () =>
            {
                if (_original == null || !Confirm($"Excluir {d.Name}?", "Lotes já criados não são afetados.")) return;
                Model.Clients.Delete(_original);
                AppLog.Warning(LogCategory.Clientes, $"Perfil \"{_original.Name}\" excluído.");
                Select(Model.Clients.Clients.FirstOrDefault()?.Id);
            }),
            U.Btn("⬆ Exportar", () =>
            {
                var path = Pickers.SaveFile("Exportar perfil", $"{Paths.Slug(d.Name)}.impcliente", "Perfil de cliente (*.impcliente)|*.impcliente");
                if (path == null) return;
                try
                {
                    Model.Clients.Export(d, path);
                    AppLog.Info(LogCategory.Clientes, $"Perfil \"{d.Name}\" exportado.", details: path);
                }
                catch (Exception e)
                {
                    AppLog.Error(LogCategory.Clientes, $"Falha ao exportar perfil: {e.Message}", details: path);
                }
            }, tooltip: "Gera um arquivo .impcliente para enviar ao seu sócio"),
        }, new UIElement[] { _savedFlash, _discardBtn, _saveBtn });
        bar.Margin = new Thickness(12);

        var dock = new DockPanel();
        var barBorder = new Border { Child = bar, BorderBrush = Brand.Stroke, BorderThickness = new Thickness(0, 1, 0, 0) };
        DockPanel.SetDock(barBorder, Dock.Bottom);
        dock.Children.Add(barBorder);
        dock.Children.Add(U.Scroll(form, 24));
        var page = new Grid();
        page.Children.Add(dock);
        page.InputBindings.Add(new KeyBinding(new Relay(() => { if (Dirty) Save(d); }), Key.S, ModifierKeys.Control));
        return page;
    }

    private void Move(ClientProfile d, int from, int offset)
    {
        var to = from + offset;
        if (to < 0 || to >= d.Axes.Count) return;
        (d.Axes[from], d.Axes[to]) = (d.Axes[to], d.Axes[from]);
        Rerender();
    }

    private static FrameworkElement Sized(FrameworkElement e, double w) { e.Width = w; return e; }

    private void Save(ClientProfile d)
    {
        d.RemoveItems = d.RemoveItems.Select(x => x.Trim()).Where(x => x.Length > 0).ToList();
        if (d.Name.Trim().Length == 0) d.Name = "Sem nome";
        Model.Clients.Save(d);
        Model.CustomAxes.Absorb(d.Axes);
        AppLog.Info(LogCategory.Clientes, $"Perfil \"{d.Name}\" salvo.",
            details: $"Remover ({d.RemoveItems.Count}): {string.Join(", ", d.RemoveItems)}\nEixos de variação: {d.Axes.Count} · rodízio {(d.RotatesAxes ? "ligado" : "desligado")}");
        _original = Model.Clients.Client(d.Id);
        _draft = _original?.Clone();
        Rerender();
        if (_savedFlash != null)
        {
            var flash = _savedFlash;
            flash.Visibility = Visibility.Visible;
            Task.Delay(1500).ContinueWith(_ => Dispatcher.Invoke(() => flash.Visibility = Visibility.Collapsed));
        }
    }
}

/// <summary>Bolinha de "na lista do cliente" (catálogo e Meus eixos).</summary>
internal static class Dot
{
    public static Button Create(bool on, Action toggle, bool disabled = false)
    {
        var b = new Button
        {
            Content = U.T(on ? "●" : "○", 18, color: on ? Brand.Red : Brand.Secondary),
            Background = System.Windows.Media.Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Width = 26,
            IsEnabled = !disabled,
            Cursor = Cursors.Hand,
            ToolTip = on ? "Na lista do cliente — clique para tirar" : "Fora da lista — clique para colocar",
        };
        b.Click += (_, _) => toggle();
        return b;
    }

    public static Border Risk(string risk)
    {
        var c = risk switch { "Alto" => Brand.RedColor, "Médio" => Brand.Warning.Color, _ => Brand.Success.Color };
        return new Border
        {
            Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(46, c.R, c.G, c.B)),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(7, 2, 7, 2),
            Child = U.T(risk, 11.5, bold: true, color: new System.Windows.Media.SolidColorBrush(c), wrap: false),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
    }

    public static Border PromptBox(string text) => new()
    {
        Background = Brand.SurfaceRaised,
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(10),
        Child = new TextBox
        {
            Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Background = System.Windows.Media.Brushes.Transparent,
            BorderThickness = new Thickness(0), Foreground = Brand.Secondary,
        },
    };

    public static string Fold(string s) => Paths.FoldDiacritics(s).ToLowerInvariant();
}

/// <summary>Catálogo dos 50 eixos do app, com busca, filtros e "Ver mais".</summary>
public sealed class AxisCatalogWindow : Window
{
    private readonly List<VariationAxis> _axes;
    private string _search = "";
    private string _family = "Todas";
    private string _risk = "Todos";
    private readonly HashSet<int> _expanded = new();
    private readonly ContentControl _list = new();
    private readonly TextBlock _count = U.Caption("");

    public AxisCatalogWindow(List<VariationAxis> axes)
    {
        _axes = axes;
        Title = "Catálogo de eixos do app";
        Width = 1000;
        Height = 700;
        MinWidth = 900;
        MinHeight = 560;
        Background = Brand.Background;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var head = U.Row(new UIElement[]
        {
            U.V(4, U.T("Catálogo de eixos do app", 20, bold: true),
                U.T("Marque a bolinha para colocar o eixo na lista do cliente; desmarque para tirar.", color: Brand.Secondary)),
        }, new UIElement[] { _count });
        var search = U.Field("", v => { _search = v; Fill(); }, "Buscar por nome, família ou o que muda");
        search.Width = 300;
        var filters = U.Row(new UIElement[]
        {
            search,
            U.Combo(new[] { "Todas" }.Concat(AxisCatalog.Families), _family, x => x, v => { _family = v; Fill(); }, 240),
            U.Combo(new[] { "Todos" }.Concat(AxisCatalog.Risks), _risk, x => x == "Todos" ? "Risco de texto: todos" : x, v => { _risk = v; Fill(); }, 170),
        }, new UIElement[]
        {
            U.Btn("Marcar visíveis", () => { foreach (var e in Filtered()) Set(e, true); Fill(); }),
            U.Btn("Desmarcar visíveis", () => { foreach (var e in Filtered()) Set(e, false); Fill(); }),
        });
        var footer = U.Row(new UIElement[] { U.Caption("As mudanças entram na lista do cliente. Clique em Salvar no perfil para gravar.") },
            new UIElement[] { U.Btn("Concluir", Close, primary: true) });
        var dock = new DockPanel { Margin = new Thickness(18) };
        var top = U.V(10, head, filters, CatalogHeader());
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        footer.Margin = new Thickness(0, 10, 0, 0);
        dock.Children.Add(top);
        dock.Children.Add(footer);
        dock.Children.Add(new ScrollViewer { Content = _list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Content = dock;
        Fill();
    }

    private static Grid Columns(params (UIElement E, double W)[] cells)
    {
        var g = new Grid();
        foreach (var (e, w) in cells)
        {
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = w > 0 ? new GridLength(w) : new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(e, g.ColumnDefinitions.Count - 1);
            if (e is FrameworkElement fe) { fe.VerticalAlignment = VerticalAlignment.Center; fe.Margin = new Thickness(5, 0, 5, 0); }
            g.Children.Add(e);
        }
        return g;
    }

    private static UIElement CatalogHeader() => Columns(
        (U.Caption("Usar"), 36), (U.Caption("Nº"), 34), (U.Caption("Nome"), 200), (U.Caption("Família"), 190),
        (U.Caption("O que muda"), 0), (U.Caption("Risco de texto"), 90), (U.Caption("Prompt"), 90));

    private IEnumerable<BuiltInAxis> Filtered()
    {
        var q = Dot.Fold(_search.Trim());
        return AxisCatalog.BuiltIn.Where(e => (_family == "Todas" || e.Family == _family) && (_risk == "Todos" || e.TextRisk == _risk)
            && (q.Length == 0 || Dot.Fold($"{e.Name} {e.Change} {e.Family} {e.Instruction}").Contains(q)));
    }

    private bool IsOn(BuiltInAxis e) => _axes.Any(a => a.Instruction == e.Instruction);

    private void Set(BuiltInAxis e, bool on)
    {
        if (on) { if (!IsOn(e)) _axes.Add(e.Axis); }
        else _axes.RemoveAll(a => a.Instruction == e.Instruction);
    }

    private void Fill()
    {
        _count.Text = $"{AxisCatalog.BuiltIn.Count(IsOn)} de {AxisCatalog.BuiltIn.Length} na lista";
        var s = new StackPanel();
        var any = false;
        foreach (var e in Filtered())
        {
            any = true;
            var on = IsOn(e);
            var open = _expanded.Contains(e.Number);
            var more = U.Link(open ? "Ver menos" : "Ver mais", () => { if (!_expanded.Remove(e.Number)) _expanded.Add(e.Number); Fill(); });
            var row = Columns((Dot.Create(on, () => { Set(e, !on); Fill(); }), 36), (U.Caption($"{e.Number}"), 34),
                (U.T(e.Name, 13.5, bold: true), 200), (U.T(e.Family, 12.5, color: Brand.Secondary), 190), (U.T(e.Change, 12.5), 0),
                (Dot.Risk(e.TextRisk), 90), (more, 90));
            var box = U.V(8, row, open ? Indent(Dot.PromptBox(e.Instruction)) : null);
            s.Children.Add(new Border
            {
                Padding = new Thickness(0, 8, 0, 8),
                BorderBrush = Brand.Stroke,
                BorderThickness = new Thickness(0, 0, 0, 1),
                Background = on ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromArgb(15, 255, 51, 51)) : System.Windows.Media.Brushes.Transparent,
                Child = box,
            });
        }
        if (!any) s.Children.Add(U.T("Nenhum eixo com esse filtro.", color: Brand.Secondary));
        _list.Content = s;
    }

    private static UIElement Indent(FrameworkElement e) { e.Margin = new Thickness(72, 0, 0, 0); return e; }
}

/// <summary>Biblioteca "Meus eixos" (1.0.0-beta.18), com a mesma bolinha do catálogo.</summary>
public sealed class CustomAxesWindow : Window
{
    private readonly List<VariationAxis> _axes;
    private readonly CustomAxisStore _library;
    private string _search = "";
    private readonly HashSet<Guid> _expanded = new();
    private readonly ContentControl _list = new();
    private readonly TextBlock _count = U.Caption("");

    public CustomAxesWindow(List<VariationAxis> axes, CustomAxisStore library)
    {
        _axes = axes;
        _library = library;
        Title = "Meus eixos";
        Width = 920;
        Height = 660;
        MinWidth = 820;
        MinHeight = 520;
        Background = Brand.Background;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var head = U.Row(new UIElement[]
        {
            U.V(4, U.T("Meus eixos", 20, bold: true),
                U.T("Eixos criados por você, para usar em qualquer cliente. Marque a bolinha para colocar na lista do cliente.", color: Brand.Secondary)),
        }, new UIElement[] { _count });
        var search = U.Field("", v => { _search = v; Fill(); }, "Buscar nos meus eixos");
        search.Width = 300;
        var tools = U.Row(new UIElement[] { search }, new UIElement[]
        {
            U.Btn("＋ Novo eixo", () =>
            {
                var n = _library.Add();
                _search = "";
                search.Text = "";
                _expanded.Add(n.Id);
                Fill();
            }),
        });
        var footer = U.Row(new UIElement[] { U.Caption("Editar aqui muda o eixo na biblioteca e na lista deste cliente. Clique em Salvar no perfil para gravar o cliente.") },
            new UIElement[] { U.Btn("Concluir", Close, primary: true) });
        footer.Margin = new Thickness(0, 10, 0, 0);
        var dock = new DockPanel { Margin = new Thickness(18) };
        var top = U.V(10, head, tools);
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        dock.Children.Add(top);
        dock.Children.Add(footer);
        dock.Children.Add(new ScrollViewer { Content = _list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 10, 0, 0) });
        Content = dock;
        Fill();
    }

    private bool IsOn(CustomAxis c) => _axes.Any(a => a.Id == c.Id || a.Instruction == c.Instruction);

    private void Set(CustomAxis c, bool on)
    {
        if (on) { if (!IsOn(c)) _axes.Add(c.Axis); }
        else _axes.RemoveAll(a => a.Id == c.Id || a.Instruction == c.Instruction);
    }

    private void Fill()
    {
        var all = _library.Axes;
        _count.Text = $"{all.Count(IsOn)} de {all.Count} na lista";
        var q = Dot.Fold(_search.Trim());
        var filtered = all.Where(c => q.Length == 0 || Dot.Fold($"{c.Name} {c.Note} {c.Instruction}").Contains(q)).ToList();
        var s = new StackPanel();
        foreach (var c in filtered)
        {
            var on = IsOn(c);
            var open = _expanded.Contains(c.Id);
            var empty = c.Instruction.Trim().Length == 0;
            var more = U.Link(open ? "Ver menos" : "Ver mais", () => { if (!_expanded.Remove(c.Id)) _expanded.Add(c.Id); Fill(); });
            var name = U.T(c.Name, 13.5, bold: true);
            name.Width = 220;
            var note = U.T(c.Note.Length == 0 ? "—" : c.Note, 12.5, color: c.Note.Length == 0 ? Brand.Secondary : Brand.Text);
            var row = U.Row(new UIElement[] { Dot.Create(on, () => { Set(c, !on); Fill(); }, empty && !on), name, note }, new UIElement[] { more }, 10);
            s.Children.Add(new Border
            {
                Padding = new Thickness(0, 8, 0, 8),
                BorderBrush = Brand.Stroke,
                BorderThickness = new Thickness(0, 0, 0, 1),
                Child = U.V(8, row, open ? Editor(c) : null),
            });
        }
        if (all.Count == 0)
            s.Children.Add(U.V(6, U.T("Você ainda não tem eixos personalizados.", 15, bold: true),
                U.T("Clique em Novo eixo, ou escreva um eixo na lista de um cliente e salve: ele aparece aqui.", color: Brand.Secondary)));
        else if (filtered.Count == 0)
            s.Children.Add(U.T("Nenhum eixo com essa busca.", color: Brand.Secondary));
        _list.Content = s;
    }

    private UIElement Editor(CustomAxis axis)
    {
        var d = new CustomAxis { Id = axis.Id, Name = axis.Name, Instruction = axis.Instruction, Note = axis.Note, CreatedAt = axis.CreatedAt };
        var name = U.Field(d.Name, v => d.Name = v, "Nome do eixo");
        name.Width = 220;
        var note = U.Field(d.Note, v => d.Note = v, "O que muda (opcional, em poucas palavras)");
        note.Width = 480;
        var instr = U.Field(d.Instruction, v => d.Instruction = v,
            "Prompt do eixo para a IA (em inglês costuma funcionar melhor). Ex.: Complete redesign …", multiline: true, minHeight: 60);
        var bar = U.Row(new UIElement[]
        {
            U.Btn("🗑 Apagar da biblioteca", () =>
            {
                if (MessageBox.Show(this, "Clientes que já usam este eixo continuam com ele na lista; desmarque a bolinha para tirar deste cliente.",
                        $"Apagar \"{axis.Name}\" de Meus eixos?", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
                _library.Delete(axis);
                Fill();
            }),
        }, new UIElement[]
        {
            U.Btn("Desfazer", Fill),
            U.Btn("Salvar eixo", () =>
            {
                d.Name = d.Name.Trim();
                d.Note = d.Note.Trim();
                d.Instruction = d.Instruction.Trim();
                if (d.Name.Length == 0) d.Name = "Sem nome";
                _library.Update(d);
                foreach (var a in _axes.Where(a => a.Id == d.Id))
                {
                    a.Name = d.Name;
                    a.Instruction = d.Instruction;
                }
                Fill();
            }),
        });
        return new Border
        {
            Margin = new Thickness(36, 0, 0, 0),
            Background = Brand.SurfaceRaised,
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10),
            Child = U.V(8, U.H(10, name, note), instr, bar),
        };
    }
}
