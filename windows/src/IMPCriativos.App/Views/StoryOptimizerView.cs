using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;
using IMPCriativos.App.Services;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Story;

namespace IMPCriativos.App.Views;

/// <summary>1.0.0-beta.21: aba "Otimizador em Lote (Stories 9:16)". Tudo no computador, sem IA.</summary>
public sealed class StoryOptimizerView : Page
{
    private static StoryBatch B => StoryBatch.Shared;
    private readonly ContentControl _files = new();
    private readonly ContentControl _preview = new();
    private readonly ContentControl _run = new();
    private readonly ContentControl _notice = new();
    private FrameworkElement? _controls;
    private string _lastStructure = "";

    protected override void Attach()
    {
        Action onChange = () => Dispatcher.BeginInvoke(FillDynamic);
        Subscribe(() => B.Changed += onChange, () => B.Changed -= onChange);
    }

    /// <summary>O que muda o desenho dos controles (os sliders não entram, para não perder o arrasto).</summary>
    private static string Structure(StoryOptions o) => string.Join("|", o.Fit, o.SolidColor, o.Intensity, o.LinesEnabled, o.LineStyle,
        o.LineDirection, o.TexturePreset, o.Format, o.Versions, o.Naming, o.Mirror, o.Custom.Geometry, o.Custom.Perspective, o.Custom.Photometric,
        o.Custom.Temperature, o.Custom.Noise, o.Custom.Diagonal, o.Custom.ChromaticShift, o.Custom.ChromaticMaxPixels, o.Custom.FilmGrain,
        o.Custom.Vignette, o.Custom.Detail, o.Custom.JpegVariation, o.CustomTexture.Jitter, o.CustomTexture.Aberration, o.CustomTexture.Bloom,
        o.CustomLines.Blend, B.OutputFolder);

    private void Edit(Action<StoryOptions> change, bool rebuild = true)
    {
        B.Edit(change);
        if (rebuild && Structure(B.Options) != _lastStructure) Rerender();
    }

    protected override UIElement Render()
    {
        var o = B.Options;
        _lastStructure = Structure(o);
        var root = new StackPanel { MaxWidth = 1120, HorizontalAlignment = HorizontalAlignment.Left };
        U.Add(root, U.Header("Otimizador em Lote (Stories 9:16)",
            $"Até {StoryBatch.MaxItems} imagens por vez em 1080×1920, sem metadados e com variações sutis. Roda 100% no computador: sem internet, sem IA e sem custo."), 0);
        U.Add(root, _files, 18);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(320) });
        _controls = Controls(o);
        grid.Children.Add(_controls);
        Grid.SetColumn(_preview, 2);
        _preview.VerticalAlignment = VerticalAlignment.Top;
        grid.Children.Add(_preview);
        U.Add(root, grid, 18);
        U.Add(root, _run, 18);
        U.Add(root, _notice, 10);
        FillDynamic();
        return U.Scroll(root);
    }

    private void FillDynamic()
    {
        _files.Content = FilesCard();
        _preview.Content = PreviewCard();
        _run.Content = RunCard();
        _notice.Content = B.Notice is string n ? U.T(n, 12.5, color: Brand.Secondary) : null;
        if (_controls != null) _controls.IsEnabled = !B.Running;
    }

    // MARK: - Imagens

    private UIElement FilesCard()
    {
        var items = B.Items;
        var count = U.T($"{items.Count}/{StoryBatch.MaxItems}", 12.5, color: items.Count >= StoryBatch.MaxItems ? Brand.Warning : Brand.Secondary);
        var head = U.Row(new UIElement[] { U.T("Imagens", 15, bold: true), count }, new UIElement[]
        {
            U.Btn("+ Adicionar…", () => { if (Pickers.Images("Adicionar imagens") is { } files) B.Add(files); },
                enabled: !B.Running && items.Count < StoryBatch.MaxItems),
            U.Btn("🗑 Limpar tudo", B.Clear, enabled: !B.Running && items.Count > 0),
        });
        UIElement body;
        if (items.Count == 0)
        {
            var v = U.V(8, U.T("⇩", 30, color: Brand.Secondary),
                U.T($"Arraste até {StoryBatch.MaxItems} imagens (JPG, PNG, WebP) ou uma pasta para cá", color: Brand.Secondary),
                U.Caption("ou clique em Adicionar…"));
            foreach (var c in v.Children.OfType<FrameworkElement>()) c.HorizontalAlignment = HorizontalAlignment.Center;
            v.VerticalAlignment = VerticalAlignment.Center;
            var dashed = new Grid { MinHeight = 150 };
            dashed.Children.Add(new Rectangle
            {
                Stroke = new SolidColorBrush(Color.FromArgb(51, 255, 255, 255)), StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection { 4, 3.5 },
                RadiusX = 10, RadiusY = 10,
            });
            dashed.Children.Add(v);
            body = dashed;
        }
        else
        {
            var wrap = new WrapPanel();
            foreach (var item in items)
            {
                var tile = Tile(item, item.Id == B.SelectedID, !B.Running);
                tile.Margin = new Thickness(0, 0, 10, 10);
                wrap.Children.Add(tile);
            }
            body = U.V(4, wrap, U.Caption("Clique numa imagem para ver o antes e depois. Arraste mais imagens para adicionar."));
        }
        var card = U.Card(U.V(12, head, body));
        card.AllowDrop = true;
        card.DragOver += (_, e) =>
        {
            e.Effects = !B.Running && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            card.BorderBrush = e.Effects == DragDropEffects.Copy ? Brand.Red : Brand.Stroke;
            e.Handled = true;
        };
        card.DragLeave += (_, _) => card.BorderBrush = Brand.Stroke;
        card.Drop += (_, e) =>
        {
            card.BorderBrush = Brand.Stroke;
            if (!B.Running && e.Data.GetData(DataFormats.FileDrop) is string[] paths) B.Add(paths);
        };
        return card;
    }

    private FrameworkElement Tile(StoryBatch.Item item, bool selected, bool canRemove)
    {
        var g = new Grid { Width = 86, Height = 86, Cursor = System.Windows.Input.Cursors.Hand };
        var thumb = U.Thumb(item.Path, 86, 200);
        g.Children.Add(thumb);
        g.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderBrush = selected ? Brand.Red : Brand.Stroke,
            BorderThickness = new Thickness(selected ? 2 : 1),
        });
        string? badge = item.Status.Kind switch
        {
            StoryBatch.StatusKind.Processing => "…",
            StoryBatch.StatusKind.Done => "✔",
            StoryBatch.StatusKind.Failed => "⚠",
            StoryBatch.StatusKind.Cancelled => "−",
            _ => null,
        };
        if (badge != null)
        {
            var color = item.Status.Kind switch
            {
                StoryBatch.StatusKind.Done => Brand.Success,
                StoryBatch.StatusKind.Failed => Brand.Red,
                StoryBatch.StatusKind.Cancelled => Brand.Secondary,
                _ => Brand.Black35,
            };
            g.Children.Add(new Border
            {
                Width = 18, Height = 18, CornerRadius = new CornerRadius(9), Background = color, Margin = new Thickness(5),
                HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom,
                Child = new TextBlock { Text = badge, FontSize = 11, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            });
        }
        if (canRemove)
        {
            var x = new Button
            {
                Content = "✕", FontSize = 10, Width = 18, Height = 18, Padding = new Thickness(0), Margin = new Thickness(4),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Background = new SolidColorBrush(Color.FromArgb(166, 0, 0, 0)), Foreground = Brushes.White, BorderThickness = new Thickness(0),
                ToolTip = "Remover da lista",
            };
            var id = item.Id;
            x.Click += (_, e) => { e.Handled = true; B.Remove(id); };
            g.Children.Add(x);
        }
        g.ToolTip = $"{item.FileName}\n{item.Status.Label}" + (item.Summary != null ? $"\n{item.Summary}" : "");
        var sel = item.Id;
        g.MouseLeftButtonUp += (_, _) => B.SelectedID = sel;
        return g;
    }

    // MARK: - Controles

    private static string Fmt(string format, double v) => string.Format(CultureInfo.InvariantCulture, format, v).Replace(".", ",");

    private UIElement SliderRow(string title, double value, (double Lo, double Hi) range, double step, string format, Action<StoryOptions, double> set)
    {
        var label = U.Caption(Fmt(format, value));
        label.Width = 110;
        label.TextAlignment = TextAlignment.Right;
        var s = U.Slider(range.Lo, range.Hi, value, v =>
        {
            label.Text = Fmt(format, v);
            Edit(o => set(o, v), rebuild: false);
        }, step);
        s.Width = 160;
        s.MinWidth = 160;
        return U.Labeled(title, U.H(8, s, label));
    }

    private UIElement Toggle(string text, bool value, Action<StoryOptions, bool> set, Brush? hintColor = null, string? hint = null)
    {
        var c = U.Toggle(text, value, v => Edit(o => set(o, v)));
        if (hint == null) return c;
        c.Content = U.V(2, U.T(text), U.Caption(hint, hintColor));
        return c;
    }

    private FrameworkElement Controls(StoryOptions o)
    {
        var s = new StackPanel();

        // Enquadramento
        var fit = new List<UIElement?>
        {
            U.Labeled("Modo", U.Segmented(StoryLabels.Fits, o.Fit, f => f.Label(), v => Edit(x => x.Fit = v)), 120),
            U.Caption(o.Fit.Hint()),
        };
        if (o.Fit == StoryFit.Solid)
        {
            fit.Add(U.Labeled("Cor de fundo", U.Combo(StoryLabels.SolidColors, o.SolidColor, c => c.Label(), v => Edit(x => x.SolidColor = v), 200), 120));
            if (o.SolidColor == StorySolidColor.Custom)
            {
                var c = o.CustomColor;
                var swatch = new Border
                {
                    Width = 40, Height = 22, CornerRadius = new CornerRadius(4), BorderBrush = Brand.Stroke, BorderThickness = new Thickness(1),
                    Background = new SolidColorBrush(Color.FromRgb((byte)Math.Round(c.R * 255), (byte)Math.Round(c.G * 255), (byte)Math.Round(c.B * 255))),
                };
                var pick = U.Btn("Escolher cor…", () =>
                {
                    using var dlg = new System.Windows.Forms.ColorDialog { FullOpen = true, Color = System.Drawing.Color.FromArgb((int)Math.Round(c.R * 255), (int)Math.Round(c.G * 255), (int)Math.Round(c.B * 255)) };
                    if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                    {
                        var k = dlg.Color;
                        Edit(x => x.CustomColor = new RGBColor(k.R / 255.0, k.G / 255.0, k.B / 255.0), rebuild: false);
                        Rerender();
                    }
                });
                fit.Add(U.Labeled("Cor", U.H(8, swatch, pick), 120));
            }
        }
        U.Add(s, U.Section("Enquadramento 9:16", fit.ToArray()), 0);

        // Variações sutis
        var vars = new List<UIElement?>
        {
            U.Labeled("Intensidade", U.Segmented(StoryLabels.Intensities, o.Intensity, i => i.Label(), v => Edit(x => x.Intensity = v)), 120),
            U.Caption(o.Intensity.Hint(), o.Intensity == StoryIntensity.Aggressive ? Brand.Warning : null),
        };
        if (o.Intensity == StoryIntensity.Custom) vars.AddRange(CustomControls(o));
        else vars.Add(U.Caption(Describe(o.Adjustments, o.Format)));
        vars.Add(Toggle("Espelhar horizontalmente", o.Mirror, (x, v) => x.Mirror = v, Brand.Warning, "Usar apenas em imagens sem texto."));
        U.Add(s, U.Section("Variações sutis", vars.ToArray()), 14);

        // Linhas diagonais
        var lines = new List<UIElement?> { U.Toggle("Linhas diagonais", o.LinesEnabled, v => Edit(x => x.SetLinesEnabled(v))) };
        if (o.LinesEnabled)
        {
            lines.Add(U.Labeled("Estilo", U.Segmented(StoryLabels.Styles, o.LineStyle, st => st.Label(), v => Edit(x => x.LineStyle = v)), 120));
            lines.Add(U.Caption(o.LineStyle.Hint()));
            lines.Add(U.V(6, U.T("Direção"), DirectionPicker(o.LineDirection)));
            lines.Add(U.Caption("A força e as medidas das linhas vêm do nível escolhido em \"Intensidade das texturas\", logo abaixo. Cada estilo tem os próprios níveis Sutil, Equilibrado e Intenso."));
            if (o.TexturePreset == StoryTexturePreset.Off)
                lines.Add(U.Caption("O nível está em Desligado: escolha Sutil, Equilibrado, Intenso ou Personalizado abaixo para as linhas aparecerem.", Brand.Warning));
        }
        else
        {
            lines.Add(U.Caption("Desligado: nenhuma linha. O nível abaixo continua valendo para serrilhado, aberração e ofuscação."));
        }
        U.Add(s, U.Section("Linhas diagonais", lines.ToArray()), 14);

        // Intensidade das texturas
        var tex = new List<UIElement?>
        {
            U.Labeled("Nível", U.Segmented(StoryLabels.Presets, o.TexturePreset, p => p.Label(), v => Edit(x => x.SelectTexturePreset(v))), 120),
            U.Caption(o.TexturePreset.Hint(), o.TexturePreset == StoryTexturePreset.Intense ? Brand.Warning : null),
        };
        if (o.TexturePreset == StoryTexturePreset.Custom) tex.AddRange(TextureControls(o));
        else if (o.TexturePreset != StoryTexturePreset.Off) tex.Add(U.Caption(Describe(o.Texture)));
        if (o.TexturePreset != StoryTexturePreset.Off)
            tex.Add(U.Caption("Vale junto com a Intensidade acima. Use \"Inspecionar Antes / Depois\" para dar zoom nas letras antes de processar o lote."));
        U.Add(s, U.Section("Intensidade das texturas", tex.ToArray()), 14);

        // Saída
        var outRows = new List<UIElement?>
        {
            U.Labeled("Formato", U.Segmented(StoryLabels.Formats, o.Format, f => f.Label(), v => Edit(x => x.Format = v)), 120),
            U.Caption(o.Format == StoryOutputFormat.Jpg
                ? "JPEG pela libjpeg-turbo, qualidade sorteada entre 88 e 93, só com perfil sRGB (sem EXIF, XMP, IPTC nem comentários)."
                : "PNG sem perda (arquivos bem maiores). Sem metadados, só com perfil sRGB."),
            U.Labeled("Versões por imagem", U.H(8,
                U.Btn("−", () => Edit(x => x.VersionsPerImage = Math.Max(StoryOptions.VersionsMin, x.Versions - 1)), enabled: o.Versions > StoryOptions.VersionsMin),
                U.T($"{o.Versions}", bold: true),
                U.Btn("+", () => Edit(x => x.VersionsPerImage = Math.Min(StoryOptions.VersionsMax, x.Versions + 1)), enabled: o.Versions < StoryOptions.VersionsMax)), 160),
        };
        if (o.Versions > 1)
            outRows.Add(U.Caption($"Cada versão sai com um sorteio diferente (story_001_v1, story_001_v2…). Total: {B.Items.Count * o.Versions} arquivos."));
        outRows.Add(U.Labeled("Nomes", U.Combo(StoryLabels.Namings, o.Naming, n => n.Label(), v => Edit(x => x.Naming = v), 240), 120));
        var example = U.Caption("");
        void UpdateExample(string prefix) => example.Text = "Exemplo: " + StoryNames.FileName(1, Math.Max(B.Items.Count, 1), prefix, "a8f3k", B.Options.Naming,
            B.Options.Format.FileExtension(), B.Options.Versions > 1 ? 1 : null);
        example.FontFamily = new FontFamily("Cascadia Mono, Consolas");
        var prefix = U.Field(o.Prefix, v => { Edit(x => x.Prefix = v, rebuild: false); UpdateExample(v); }, "story");
        prefix.Width = 240;
        UpdateExample(o.Prefix);
        outRows.Add(U.Labeled("Prefixo", prefix, 120));
        outRows.Add(example);
        var folder = B.OutputFolder;
        outRows.Add(U.Row(new UIElement?[]
        {
            U.V(2, U.T(folder != null ? System.IO.Path.GetFileName(folder.TrimEnd('\\', '/')) : "Nenhuma pasta escolhida"),
                folder != null ? U.Caption(folder) : null,
                U.Caption("Cada lote cria uma pasta stories_data_hora dentro dela.")),
        }, new UIElement[]
        {
            U.Btn("Escolher pasta…", () =>
            {
                if (Pickers.Folder("Pasta de saída dos stories", B.OutputFolder) is string f) { B.SetOutputFolder(f); Rerender(); }
            }),
        }));
        U.Add(s, U.Section("Saída", outRows.ToArray()), 14);
        s.IsEnabled = !B.Running;
        return s;
    }

    private UIElement DirectionPicker(StoryLineDirection selection)
    {
        var g = new UniformGrid { Rows = 1 };
        foreach (var d in StoryLabels.Directions)
        {
            var selected = d == selection;
            var glyph = Glyph(d);
            var b = new Button
            {
                Content = U.V(5, glyph, U.T(d.ShortLabel(), 11.5, weight: selected ? FontWeights.SemiBold : FontWeights.Normal)),
                Padding = new Thickness(6, 8, 6, 8),
                Margin = new Thickness(0, 0, 8, 0),
                Background = selected ? new SolidColorBrush(Color.FromArgb(56, 255, 51, 51)) : new SolidColorBrush(Color.FromArgb(10, 255, 255, 255)),
                BorderBrush = selected ? Brand.Red : new SolidColorBrush(Color.FromArgb(31, 255, 255, 255)),
                BorderThickness = new Thickness(selected ? 2 : 1),
                ToolTip = d.Label(),
            };
            var dir = d;
            b.Click += (_, _) => Edit(x => x.LineDirection = dir);
            g.Children.Add(b);
        }
        return g;
    }

    /// <summary>Desenho pequeno de cada direção: \, /, X ou o símbolo de sorteio.</summary>
    private static FrameworkElement Glyph(StoryLineDirection d)
    {
        if (d == StoryLineDirection.Random)
            return new TextBlock { Text = "🔀", FontSize = 17, Height = 30, HorizontalAlignment = HorizontalAlignment.Center, TextAlignment = TextAlignment.Center };
        const double w = 48, h = 30;
        var c = new Canvas { Width = w, Height = h, ClipToBounds = true, HorizontalAlignment = HorizontalAlignment.Center };
        for (var x = -h; x < w + h; x += 9)
        {
            if (d != StoryLineDirection.Slash)
                c.Children.Add(new Line { X1 = x, Y1 = 0, X2 = x + h, Y2 = h, Stroke = Brand.Text, StrokeThickness = 1.6 });
            if (d != StoryLineDirection.Backslash)
                c.Children.Add(new Line { X1 = x + h, Y1 = 0, X2 = x, Y2 = h, Stroke = Brand.Text, StrokeThickness = 1.6 });
        }
        return c;
    }

    private IEnumerable<UIElement?> CustomControls(StoryOptions o)
    {
        var c = o.Custom;
        yield return Toggle("Micro-recorte e micro-rotação", c.Geometry, (x, v) => x.Custom.Geometry = v);
        if (c.Geometry)
        {
            yield return SliderRow("Recorte máximo por borda", c.CropMaxPercent, StoryAdjustments.CropRange, 0.1, "até {0:0.0}%", (x, v) => x.Custom.CropMaxPercent = v);
            yield return SliderRow("Rotação máxima", c.RotationMaxDegrees, StoryAdjustments.RotationRange, 0.05, "±{0:0.00}°", (x, v) => x.Custom.RotationMaxDegrees = v);
        }
        yield return Toggle("Micro-perspectiva (cantos)", c.Perspective, (x, v) => x.Custom.Perspective = v);
        if (c.Perspective)
            yield return SliderRow("Deslocamento máximo dos cantos", c.PerspectiveMaxPercent, StoryAdjustments.PerspectiveRange, 0.1, "±{0:0.0}%", (x, v) => x.Custom.PerspectiveMaxPercent = v);
        yield return Toggle("Brilho, contraste e saturação", c.Photometric, (x, v) => x.Custom.Photometric = v);
        if (c.Photometric)
        {
            yield return SliderRow("Brilho", c.BrightnessMaxPercent, StoryAdjustments.BrightnessRange, 0.1, "±{0:0.0}%", (x, v) => x.Custom.BrightnessMaxPercent = v);
            yield return SliderRow("Contraste", c.ContrastMaxPercent, StoryAdjustments.ContrastRange, 0.1, "±{0:0.0}%", (x, v) => x.Custom.ContrastMaxPercent = v);
            yield return SliderRow("Saturação", c.SaturationMaxPercent, StoryAdjustments.SaturationRange, 0.1, "±{0:0.0}%", (x, v) => x.Custom.SaturationMaxPercent = v);
        }
        yield return Toggle("Temperatura de cor (mais quente / mais fria)", c.Temperature, (x, v) => x.Custom.Temperature = v);
        if (c.Temperature)
            yield return SliderRow("Temperatura máxima", c.TemperatureMaxKelvin, StoryAdjustments.TemperatureRange, 25, "±{0:0}K", (x, v) => x.Custom.TemperatureMaxKelvin = v);
        yield return Toggle("Micro-ruído (anti-banding)", c.Noise, (x, v) => x.Custom.Noise = v);
        if (c.Noise)
            yield return SliderRow("Amplitude máxima", c.NoiseMaxAmplitude, StoryAdjustments.NoiseRange, 0.25, "até ±{0:0.00} níveis", (x, v) => x.Custom.NoiseMaxAmplitude = v);
        yield return Toggle("Riscos diagonais pixel a pixel (escurece, clareia, mantém)", c.Diagonal, (x, v) => x.Custom.Diagonal = v);
        if (c.Diagonal)
            yield return SliderRow("Intensidade máxima dos riscos", c.DiagonalMaxAmplitude, StoryAdjustments.DiagonalRange, 0.5, "até ±{0:0.0} níveis", (x, v) => x.Custom.DiagonalMaxAmplitude = v);
        yield return Toggle("Deslocamento de canal (R ou B)", c.ChromaticShift, (x, v) => x.Custom.ChromaticShift = v);
        if (c.ChromaticShift)
            yield return U.Labeled("Deslocamento máximo", U.Segmented(new[] { 1, 2 }, c.ChromaticMaxPixels, p => p == 1 ? "1px" : "até 2px",
                v => Edit(x => x.Custom.ChromaticMaxPixels = v)));
        yield return Toggle("Granulação de filme (overlay / soft-light)", c.FilmGrain, (x, v) => x.Custom.FilmGrain = v);
        if (c.FilmGrain)
            yield return SliderRow("Opacidade máxima", c.GrainMaxOpacityPercent, StoryAdjustments.GrainRange, 0.25, "até {0:0.00}%", (x, v) => x.Custom.GrainMaxOpacityPercent = v);
        yield return Toggle("Vinheta (bordas mais escuras ou mais claras)", c.Vignette, (x, v) => x.Custom.Vignette = v);
        if (c.Vignette)
            yield return SliderRow("Vinheta máxima nos cantos", c.VignetteMaxPercent, StoryAdjustments.VignetteRange, 0.5, "±{0:0.0}%", (x, v) => x.Custom.VignetteMaxPercent = v);
        yield return Toggle("Micro-nitidez ou suavização (sorteado)", c.Detail, (x, v) => x.Custom.Detail = v);
        var jpeg = (CheckBox)Toggle("Variar compressão JPEG (baseline/progressivo, 4:2:0/4:4:4)", c.JpegVariation, (x, v) => x.Custom.JpegVariation = v);
        jpeg.IsEnabled = o.Format == StoryOutputFormat.Jpg;
        yield return jpeg;
    }

    private IEnumerable<UIElement?> TextureControls(StoryOptions o)
    {
        if (o.LinesEnabled)
        {
            var l = o.CustomLines;
            yield return U.T($"Linhas — {o.LineStyle.Label()}", bold: true);
            yield return SliderRow("Intensidade das linhas", l.OpacityPercent, StoryTexture.PercentRange, 1, "{0:0}%", (x, v) => { var c = x.CustomLines; c.OpacityPercent = v; x.CustomLines = c; });
            yield return SliderRow("Espaçamento", l.Spacing, StoryTexture.SpacingRange, 1, "{0:0} px", (x, v) => { var c = x.CustomLines; c.Spacing = v; x.CustomLines = c; });
            yield return SliderRow("Espessura", l.Thickness, StoryTexture.ThicknessRange, 1, "{0:0} px", (x, v) => { var c = x.CustomLines; c.Thickness = v; x.CustomLines = c; });
            if (o.LineStyle == StoryLineStyle.Tone)
            {
                yield return SliderRow("Ângulo", l.Angle, StoryTexture.AngleRange, 1, "{0:0}°", (x, v) => { var c = x.CustomLines; c.Angle = v; x.CustomLines = c; });
                yield return SliderRow("Irregularidade", l.Irregularity, StoryTexture.PercentRange, 1, "{0:0}%", (x, v) => { var c = x.CustomLines; c.Irregularity = v; x.CustomLines = c; });
                yield return U.Caption("Medidas em pixels da saída 1080×1920. Espaçamento é a distância de uma linha à próxima, e a espessura é o miolo escuro (a borda é suave). Ângulo a partir da horizontal: 45° é a diagonal exata, mais alto deixa as linhas mais em pé (cada imagem sorteia ±3°). Irregularidade: 0% são linhas contínuas e iguais; quanto mais alto, mais elas variam de força, têm falhas e saem um pouco do lugar. Intensidade: 10–25% quase imperceptível, 50% visível (±20% de brilho), 100% forte (±35%).");
            }
            else
            {
                yield return U.Labeled("Mistura", U.Segmented(StoryLabels.Blends, l.Blend, b => b.Label(), v => Edit(x => { var c = x.CustomLines; c.Blend = v; x.CustomLines = c; })));
                yield return U.Caption("Hard-light: a faixa escura puxa para o preto e o realce para o branco com a mesma força em qualquer cor. É o mais contrastado: aparece até sobre texto branco e fundo preto.");
                yield return U.Caption("Overlay: depende do tom de baixo. Nas áreas escuras o realce quase some, e nas claras a faixa escura fica mais leve. Fica mais integrado à imagem e menos marcado.");
                yield return U.Caption("Medidas em pixels da saída 1080×1920, na horizontal, sempre a 45° e pixel exato. A espessura nunca passa do espaçamento menos 2 px. Intensidade: 10–25% sutil, 50% bem marcado, 80–100% forte.");
            }
            yield return U.Divider();
        }
        var t = o.CustomTexture;
        yield return Toggle("Serrilhado das bordas (quebra o anti-aliasing)", t.Jitter, (x, v) => x.CustomTexture.Jitter = v);
        if (t.Jitter)
        {
            yield return SliderRow("Nível de serrilhado", t.JitterPercent, StoryTexture.PercentRange, 1, "{0:0}%", (x, v) => x.CustomTexture.JitterPercent = v);
            yield return U.Caption("Só nas bordas de alto contraste (texto, botões e contornos). O resto da foto não muda.");
        }
        yield return Toggle("Aberração cromática RGB (R e B em sentidos opostos)", t.Aberration, (x, v) => x.CustomTexture.Aberration = v);
        if (t.Aberration)
        {
            var px = 1 + (int)Math.Round((StoryTexture.AberrationMaxPixels - 1) * t.AberrationPercent / 100, MidpointRounding.AwayFromZero);
            var note = U.Caption($"Cerca de {px} px no nível escolhido (1 a {StoryTexture.AberrationMaxPixels} px).");
            yield return SliderRow("Deslocamento RGB", t.AberrationPercent, StoryTexture.PercentRange, 1, "{0:0}%", (x, v) =>
            {
                x.CustomTexture.AberrationPercent = v;
                var p = 1 + (int)Math.Round((StoryTexture.AberrationMaxPixels - 1) * v / 100, MidpointRounding.AwayFromZero);
                note.Text = $"Cerca de {p} px no nível escolhido (1 a {StoryTexture.AberrationMaxPixels} px).";
            });
            yield return note;
        }
        yield return Toggle("Ofuscação do contraste (bloom + micro-desfoque)", t.Bloom, (x, v) => x.CustomTexture.Bloom = v);
        if (t.Bloom)
        {
            yield return SliderRow("Nível de ofuscação", t.BloomPercent, StoryTexture.PercentRange, 1, "{0:0}%", (x, v) => x.CustomTexture.BloomPercent = v);
            yield return U.Caption("Baixo: letras só levemente estilizadas. Alto: perto do limite da leitura.");
        }
    }

    /// <summary>Resumo das texturas do preset em uma linha.</summary>
    public static string Describe(StoryTexture t)
    {
        var parts = new List<string>();
        if (!t.Lines) parts.Add("sem linhas");
        else if (t.LineStyle == StoryLineStyle.Tone)
            parts.Add($"linhas no tom (mantêm a cor) {t.LineDirection.Label().ToLowerInvariant()}, {(int)t.LineOpacityPercent}%, {(int)t.LineAngle}°, espaçamento {(int)t.LineSpacing} px, espessura {(int)t.LineThickness} px, irregularidade {(int)t.LineIrregularity}%");
        else
            parts.Add($"linhas em gravura {t.LineDirection.Label().ToLowerInvariant()}, {(int)t.LineOpacityPercent}%, espaçamento {(int)t.LineSpacing} px, espessura {(int)t.LineThickness} px, {t.LineBlend.Label()}");
        if (t.Jitter) parts.Add($"serrilhado {(int)t.JitterPercent}%");
        if (t.Aberration) parts.Add($"aberração RGB {(int)t.AberrationPercent}%");
        if (t.Bloom) parts.Add($"ofuscação {(int)t.BloomPercent}%");
        return "Sorteado por imagem (70% a 100% do nível): " + (parts.Count == 0 ? "nenhum efeito" : string.Join(" · ", parts)) + ".";
    }

    private static string F(string format, params object[] args) => string.Format(CultureInfo.InvariantCulture, format, args);

    /// <summary>Resumo do preset em uma linha.</summary>
    public static string Describe(StoryAdjustments a, StoryOutputFormat format)
    {
        var parts = new List<string>();
        if (a.Geometry) parts.Add(F("recorte {0:0.0}–{1:0.0}% e rotação ±{2:0.0}°", a.CropMinPercent, a.CropMaxPercent, a.RotationMaxDegrees));
        if (a.Perspective) parts.Add(F("perspectiva ±{0:0.0}%", a.PerspectiveMaxPercent));
        if (a.Photometric) parts.Add(F("brilho e contraste ±{0:0}%, saturação ±{1:0.0}%", a.BrightnessMaxPercent, a.SaturationMaxPercent));
        if (a.Temperature) parts.Add(F("temperatura ±{0:0}K", a.TemperatureMaxKelvin));
        if (a.Noise) parts.Add(F("ruído ±{0:0.0}–{1:0.0}", a.NoiseMinAmplitude, a.NoiseMaxAmplitude));
        if (a.Diagonal) parts.Add(F("riscos diagonais ±{0:0}–{1:0}", a.DiagonalMinAmplitude, a.DiagonalMaxAmplitude));
        if (a.ChromaticShift) parts.Add(a.ChromaticMaxPixels >= 2 ? "deslocamento de canal até 2px" : "deslocamento de canal 1px");
        if (a.FilmGrain) parts.Add(F("granulação {0:0}–{1:0}%", a.GrainMinOpacityPercent, a.GrainMaxOpacityPercent));
        if (a.Vignette) parts.Add(F("vinheta ±{0:0}%", a.VignetteMaxPercent));
        if (a.Detail) parts.Add("nitidez ou suavização");
        if (a.JpegVariation && format == StoryOutputFormat.Jpg) parts.Add("JPEG baseline/progressivo e 4:2:0/4:4:4");
        return "Sorteado por imagem: " + string.Join(" · ", parts).Replace(".", ",") + ".";
    }

    // MARK: - Preview

    private UIElement PreviewCard()
    {
        var item = B.Selected;
        var s = new StackPanel();
        U.Add(s, U.Row(new UIElement?[] { U.T("Antes / Depois", 15, bold: true) }, new UIElement?[]
        {
            B.PreviewLoading ? new ProgressBar { IsIndeterminate = true, Width = 30, Height = 4, Foreground = Brand.Red } : null,
            U.Btn("🎲 Novo sorteio", () => { if (B.SelectedID is Guid id) B.Reroll(id); },
                tooltip: "Sorteia outros valores para esta imagem, dentro dos mesmos limites", enabled: item != null && !B.Running),
        }), 0);
        var inspect = U.Btn("🔍 Inspecionar Antes / Depois", () => StoryInspectorWindow.Open(Window.GetWindow(this)), primary: true,
            tooltip: "Abre o antes e depois em tela grande, com cortina, zoom e arrastar", enabled: item != null);
        inspect.HorizontalAlignment = HorizontalAlignment.Stretch;
        inspect.Padding = new Thickness(12, 9, 12, 9);
        U.Add(s, inspect, 10);
        if (item != null)
        {
            U.Add(s, U.H(10, Pane("Antes", U.FromSkia(B.PreviewBefore)),
                Pane("Depois · 1080×1920", B.PreviewAfter is byte[] a ? U.FromRgbx(a, StoryOptimizer.Width, StoryOptimizer.Height) : null)), 10);
            var name = U.Caption(item.FileName);
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            name.TextWrapping = TextWrapping.NoWrap;
            U.Add(s, name, 10);
            var o = B.Options;
            if (o.Versions > 1)
                U.Add(s, U.H(8,
                    U.Btn("−", () => B.PreviewVersion = Math.Max(1, B.PreviewVersion - 1), enabled: !B.Running && B.PreviewVersion > 1),
                    U.Btn("+", () => B.PreviewVersion = Math.Min(o.Versions, B.PreviewVersion + 1), enabled: !B.Running && B.PreviewVersion < o.Versions),
                    U.Caption($"Versão {B.PreviewVersion} de {o.Versions}")), 8);
            if (B.PreviewSummary.Length > 0) U.Add(s, U.T(B.PreviewSummary, 10.5, color: Brand.Secondary), 8);
            if (item.Status.Kind == StoryBatch.StatusKind.Failed) U.Add(s, U.Error(item.Status.Message ?? "Erro"), 8);
        }
        else
        {
            var t = U.T("Adicione imagens para ver o antes e depois com as configurações atuais.", color: Brand.Secondary);
            t.MinHeight = 200;
            t.Margin = new Thickness(0, 10, 0, 0);
            s.Children.Add(t);
        }
        return U.Card(s);
    }

    private static UIElement Pane(string title, ImageSource? image)
    {
        var g = new Grid { Width = 136, Height = 242, Background = Brushes.Black };
        if (image != null)
        {
            var img = new Image { Source = image, Stretch = Stretch.Uniform };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            g.Children.Add(img);
        }
        else
        {
            g.Children.Add(new ProgressBar { IsIndeterminate = true, Width = 40, Height = 4, Foreground = Brand.Red });
        }
        var frame = new Border { CornerRadius = new CornerRadius(6), BorderBrush = Brand.Stroke, BorderThickness = new Thickness(1), Child = g, ClipToBounds = true };
        var cap = U.T(title, 10.5, color: Brand.Secondary);
        cap.HorizontalAlignment = HorizontalAlignment.Center;
        return U.V(4, frame, cap);
    }

    // MARK: - Processar

    private UIElement RunCard()
    {
        var left = new StackPanel();
        U.Add(left, U.T(StatusTitle(), 15, bold: true), 0);
        if (B.FailedCount > 0) U.Add(left, U.Caption($"{B.FailedCount} com erro — passe o mouse na miniatura para ver o motivo", Brand.Red), 3);
        if (B.LastRunFolder is string lf && !B.Running && B.DoneCount > 0) U.Add(left, U.Caption(lf), 3);
        var right = new List<UIElement>();
        if (B.Running)
        {
            right.Add(U.Btn(B.Cancelling ? "Cancelando…" : "■ Cancelar", B.Cancel, enabled: !B.Cancelling));
        }
        else
        {
            if (B.LastRunFolder is string folder && B.DoneCount > 0)
            {
                right.Add(U.Btn("📁 Abrir pasta", () => Shell.Open(folder)));
                right.Add(U.Btn(B.Zipping ? "Compactando…" : "🗜 Baixar Tudo (.ZIP)", async () =>
                {
                    var name = System.IO.Path.GetFileName(folder.TrimEnd('\\', '/')) + ".zip";
                    if (Pickers.SaveFile("Salvar o .zip", name, "Arquivo ZIP (*.zip)|*.zip") is string target)
                    {
                        var error = await B.MakeZip(target);
                        if (error == null) Shell.Reveal(target);
                        else Alert("Baixar Tudo (.ZIP)", $"Não consegui criar o ZIP: {error}");
                    }
                }, enabled: !B.Zipping));
            }
            right.Add(U.Btn("▶ Processar Lote", () => _ = B.Start(), primary: true, enabled: B.Items.Count > 0 && B.OutputFolder != null));
        }
        var s = U.V(10, U.Row(new UIElement[] { left }, right, 12));
        if (B.Running || B.ProcessedOutputs > 0)
            s.Children.Add(U.Progress(B.ProcessedOutputs / (double)Math.Max(B.TotalOutputs, 1)));
        s.Children.Add(U.Caption($"Processa {StoryBatch.Concurrency} imagens por vez. Dá para trocar de aba enquanto roda."));
        return U.Card(s);
    }

    private static string StatusTitle()
    {
        var total = B.Items.Count;
        if (B.Running)
            return B.TotalOutputs > total ? $"{B.ProcessedOutputs} de {B.TotalOutputs} arquivos processados" : $"{B.ProcessedOutputs} de {total} imagens processadas";
        if (B.FinishedCount > 0)
            return B.TotalOutputs > total ? $"{B.WrittenOutputs} de {B.TotalOutputs} arquivos prontos" : $"{B.DoneCount} de {total} imagens prontas";
        return total == 0 ? "Nenhuma imagem na lista" : $"{total} imagem(ns) prontas para processar";
    }
}
