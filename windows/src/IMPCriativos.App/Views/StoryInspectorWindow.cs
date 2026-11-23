using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IMPCriativos.App.UI;
using IMPCriativos.Core.Story;

namespace IMPCriativos.App.Views;

public enum StoryInspectMode { Curtain, SideBySide }

/// <summary>O que aparece do lado "Antes".</summary>
public enum StoryInspectBefore { Original, Plain }

/// <summary>
/// 1.0.0-beta.23: janela de inspeção Antes / Depois do Otimizador em Lote (Stories 9:16).
/// Mostra a imagem selecionada em 1080×1920 (os mesmos pixels do arquivo final), com cortina ou lado a lado,
/// zoom Ajustar / 100% / 200% / 400% com arrastar, e "Re-randomizar".
/// </summary>
public sealed class StoryInspectorWindow : Window
{
    private static StoryBatch B => StoryBatch.Shared;
    private readonly InspectorCanvas _canvas = new();
    private readonly ContentControl _toolbar = new();
    private readonly ContentControl _footer = new();
    private readonly ProgressBar _loading = new() { IsIndeterminate = true, Width = 120, Height = 5, Foreground = Brand.Red };
    private StoryInspectBefore _before = StoryInspectBefore.Original;
    private byte[]? _lastBefore, _lastAfter;

    public static StoryInspectorWindow? Current { get; private set; }

    public static void Open(Window? owner)
    {
        var w = new StoryInspectorWindow { Owner = owner };
        w.ShowDialog();
    }

    public StoryInspectorWindow()
    {
        Title = "Inspecionar Antes / Depois";
        Width = 1180;
        Height = 820;
        MinWidth = 1100;
        MinHeight = 700;
        Background = Brand.Background;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var dock = new DockPanel();
        var top = new Border { Padding = new Thickness(16, 12, 16, 12), Child = _toolbar, BorderBrush = Brand.Stroke, BorderThickness = new Thickness(0, 0, 0, 1) };
        var bottom = new Border { Padding = new Thickness(16, 10, 16, 10), Child = _footer, BorderBrush = Brand.Stroke, BorderThickness = new Thickness(0, 1, 0, 0) };
        DockPanel.SetDock(top, Dock.Top);
        DockPanel.SetDock(bottom, Dock.Bottom);
        dock.Children.Add(top);
        dock.Children.Add(bottom);
        var center = new Grid();
        center.Children.Add(_canvas);
        center.Children.Add(_loading);
        dock.Children.Add(center);
        Content = dock;
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
        Action onChange = () => Dispatcher.BeginInvoke(Fill);
        Loaded += (_, _) =>
        {
            Current = this;
            B.Changed += onChange;
            B.Inspecting = true;
            Fill();
        };
        Closed += (_, _) =>
        {
            B.Changed -= onChange;
            B.Inspecting = false;
            if (Current == this) Current = null;
        };
    }

    private void Fill()
    {
        _toolbar.Content = U.Row(new UIElement[]
        {
            U.Segmented(new[] { StoryInspectMode.Curtain, StoryInspectMode.SideBySide }, _canvas.Mode,
                m => m == StoryInspectMode.Curtain ? "Cortina" : "Lado a lado", v => { _canvas.Mode = v; Fill(); }),
            U.Segmented(new[] { 0, 100, 200, 400 }, _canvas.Zoom, z => z == 0 ? "Ajustar" : $"{z}%", v => { _canvas.Zoom = v; Fill(); }),
            WithTip(U.Combo(new[] { StoryInspectBefore.Original, StoryInspectBefore.Plain }, _before,
                b => b == StoryInspectBefore.Original ? "Original enquadrado" : "Sem as texturas", v => { _before = v; Fill(); }, 240),
                "Original enquadrado: a imagem sem nenhuma variação. Sem as texturas: tudo igual ao arquivo final, menos linhas, serrilhado, aberração e bloom."),
        }, new UIElement[]
        {
            U.Btn("🎲 Re-randomizar Preview", () => { if (B.SelectedID is Guid id) B.Reroll(id); },
                tooltip: "Sorteia outros valores para esta imagem (outra direção das linhas, outro serrilhado, outro deslocamento) dentro dos mesmos limites",
                enabled: B.Selected != null && !B.Running),
            U.Btn("Fechar", Close),
        }, 14);

        var beforeBytes = _before == StoryInspectBefore.Original ? B.InspectOriginal : B.InspectPlain;
        if (!ReferenceEquals(beforeBytes, _lastBefore))
        {
            _lastBefore = beforeBytes;
            _canvas.Before = beforeBytes != null ? U.FromRgbx(beforeBytes, StoryOptimizer.Width, StoryOptimizer.Height) : null;
        }
        if (!ReferenceEquals(B.PreviewAfter, _lastAfter))
        {
            _lastAfter = B.PreviewAfter;
            _canvas.After = _lastAfter != null ? U.FromRgbx(_lastAfter, StoryOptimizer.Width, StoryOptimizer.Height) : null;
        }
        _canvas.BeforeLabel = _before == StoryInspectBefore.Original ? "ANTES · ORIGINAL" : "ANTES · SEM TEXTURAS";
        _canvas.InvalidateVisual();
        _loading.Visibility = B.PreviewLoading && (_canvas.Before == null || _canvas.After == null) ? Visibility.Visible : Visibility.Collapsed;

        var o = B.Options;
        var s = new StackPanel();
        var left = new List<UIElement?>();
        if (B.Selected is StoryBatch.Item item) left.Add(U.T(item.FileName, 11.5, bold: true, wrap: false));
        if (B.PreviewLoading) left.Add(new ProgressBar { IsIndeterminate = true, Width = 30, Height = 4, Foreground = Brand.Red });
        if (o.Versions > 1)
        {
            left.Add(U.Btn("−", () => B.PreviewVersion = Math.Max(1, B.PreviewVersion - 1), enabled: !B.Running && B.PreviewVersion > 1));
            left.Add(U.Btn("+", () => B.PreviewVersion = Math.Min(o.Versions, B.PreviewVersion + 1), enabled: !B.Running && B.PreviewVersion < o.Versions));
            left.Add(U.Caption($"Versão {B.PreviewVersion} de {o.Versions}"));
        }
        U.Add(s, U.Row(left, new UIElement[]
        {
            U.Caption(_canvas.Mode == StoryInspectMode.Curtain
                ? "Arraste a barra para comparar · arraste a imagem para mover (com zoom)"
                : "Arraste a imagem para mover as duas ao mesmo tempo (com zoom)"),
        }), 0);
        if (o.TexturePreset == StoryTexturePreset.Off)
            U.Add(s, U.Caption("As texturas estão desligadas. Escolha Sutil, Equilibrado, Intenso ou Personalizado em \"Intensidade das texturas\" para ver linhas, serrilhado, aberração e bloom aqui.", Brand.Warning), 3);
        if (B.PreviewSummary.Length > 0) U.Add(s, U.T(B.PreviewSummary, 10.5, color: Brand.Secondary), 3);
        U.Add(s, U.T("100% = um pixel da imagem para cada pixel da tela. O arquivo final tem exatamente estes pixels.", 10.5, color: Brand.Secondary), 3);
        _footer.Content = s;
    }

    private static T WithTip<T>(T e, string tip) where T : FrameworkElement { e.ToolTip = tip; return e; }
}

/// <summary>Desenho, zoom e arrastar do inspetor (pixel exato com zoom, sem suavizar).</summary>
public sealed class InspectorCanvas : FrameworkElement
{
    public BitmapSource? Before { get; set; }
    public BitmapSource? After { get; set; }
    public string BeforeLabel { get; set; } = "ANTES";

    private StoryInspectMode _mode = StoryInspectMode.Curtain;
    public StoryInspectMode Mode { get => _mode; set { _mode = value; InvalidateVisual(); } }

    private int _zoom;
    /// <summary>0 = Ajustar; 100, 200 ou 400 = pixels da imagem por pixel real da tela.</summary>
    public int Zoom { get => _zoom; set { _zoom = value; InvalidateVisual(); } }

    /// <summary>Ponto da imagem (em pixels, de cima para baixo) que fica no centro de cada painel quando há zoom.</summary>
    private Point _center = new(StoryOptimizer.Width / 2.0, StoryOptimizer.Height / 2.0);
    /// <summary>Posição da barra da cortina (0 a 1 da largura).</summary>
    private double _split = 0.5;
    private enum Drag { None, Pan, Divider }
    private Drag _drag;
    private Point _last;

    public InspectorCanvas()
    {
        Focusable = true;
        ClipToBounds = true;
    }

    private Size ImageSize => After != null ? new Size(After.PixelWidth, After.PixelHeight)
        : Before != null ? new Size(Before.PixelWidth, Before.PixelHeight) : new Size(StoryOptimizer.Width, StoryOptimizer.Height);

    private double Dpi => VisualTreeHelper.GetDpi(this).DpiScaleX;

    private Rect[] Panels
    {
        get
        {
            var b = new Rect(0, 0, ActualWidth, ActualHeight);
            if (Mode == StoryInspectMode.Curtain) return new[] { b };
            const double gap = 6;
            var half = (b.Width - gap) / 2;
            return new[] { new Rect(0, 0, half, b.Height), new Rect(half + gap, 0, half, b.Height) };
        }
    }

    /// <summary>Unidades de tela por pixel da imagem. 100% = 1 pixel da imagem por pixel real da tela.</summary>
    private double Scale(Rect panel) => Zoom == 0
        ? Math.Max(Math.Min(panel.Width / ImageSize.Width, panel.Height / ImageSize.Height), 0.01)
        : Zoom / 100.0 / Dpi;

    private Point EffectiveCenter => Zoom == 0 ? new Point(ImageSize.Width / 2, ImageSize.Height / 2) : _center;

    protected override void OnRender(DrawingContext dc)
    {
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        dc.DrawRectangle(Brand.Background, null, bounds);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;
        RenderOptions.SetBitmapScalingMode(this, Zoom == 0 ? BitmapScalingMode.HighQuality : BitmapScalingMode.NearestNeighbor);
        if (Mode == StoryInspectMode.Curtain)
        {
            var x = Math.Round(bounds.Width * _split);
            dc.PushClip(new RectangleGeometry(new Rect(0, 0, x, bounds.Height)));
            DrawImage(dc, Before, bounds);
            dc.Pop();
            dc.PushClip(new RectangleGeometry(new Rect(x, 0, Math.Max(0, bounds.Width - x), bounds.Height)));
            DrawImage(dc, After, bounds);
            dc.Pop();
            var white = new Pen(Brushes.White, 2);
            dc.DrawLine(white, new Point(x, 0), new Point(x, bounds.Height));
            dc.DrawEllipse(Brushes.White, null, new Point(x, bounds.Height / 2), 15, 15);
            var arrows = Text("◂▸", 13, Brushes.Black, FontWeights.Bold);
            dc.DrawText(arrows, new Point(x - arrows.Width / 2, bounds.Height / 2 - arrows.Height / 2));
            Label(dc, BeforeLabel, new Point(12, 12), false);
            Label(dc, "DEPOIS", new Point(bounds.Width - 12, 12), true);
        }
        else
        {
            var rects = Panels;
            var images = new[] { Before, After };
            var labels = new[] { BeforeLabel, "DEPOIS" };
            for (var i = 0; i < 2; i++)
            {
                dc.PushClip(new RectangleGeometry(rects[i]));
                DrawImage(dc, images[i], rects[i]);
                dc.Pop();
                Label(dc, labels[i], new Point(rects[i].Left + 12, 12), false);
            }
        }
    }

    private void DrawImage(DrawingContext dc, BitmapSource? image, Rect panel)
    {
        if (image == null)
        {
            var t = Text("Gerando a imagem…", 13, Brand.Secondary);
            dc.DrawText(t, new Point(panel.Left + panel.Width / 2 - t.Width / 2, panel.Top + panel.Height / 2 - t.Height / 2));
            return;
        }
        var s = Scale(panel);
        var c = EffectiveCenter;
        var ox = panel.Left + panel.Width / 2 - c.X * s;
        var oy = panel.Top + panel.Height / 2 - c.Y * s;
        // encaixa a origem no pixel real da tela, para cada pixel da imagem virar um quadrado inteiro com zoom
        if (Zoom != 0)
        {
            var d = Dpi;
            ox = Math.Round(ox * d) / d;
            oy = Math.Round(oy * d) / d;
        }
        dc.DrawImage(image, new Rect(ox, oy, image.PixelWidth * s, image.PixelHeight * s));
    }

    private FormattedText Text(string text, double size, Brush color, FontWeight? weight = null) =>
        new(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(U.Font, FontStyles.Normal, weight ?? FontWeights.SemiBold, FontStretches.Normal), size, color, Dpi);

    private void Label(DrawingContext dc, string text, Point at, bool alignRight)
    {
        var t = Text(text, 11, Brushes.White);
        var pill = new Rect(alignRight ? at.X - t.Width - 16 : at.X, at.Y, t.Width + 16, t.Height + 8);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(166, 0, 0, 0)), null, pill, 6, 6);
        dc.DrawText(t, new Point(pill.Left + 8, pill.Top + 4));
    }

    // MARK: Mouse

    private double DividerX => Math.Round(ActualWidth * _split);

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        var p = e.GetPosition(this);
        _last = p;
        Focus();
        CaptureMouse();
        // na cortina, a barra anda quando o clique é perto dela ou quando não há zoom (nada para mover na imagem)
        if (Mode == StoryInspectMode.Curtain && (Zoom == 0 || Math.Abs(p.X - DividerX) < 16))
        {
            _drag = Drag.Divider;
            MoveDivider(p.X);
        }
        else
        {
            _drag = Drag.Pan;
            Cursor = Cursors.SizeAll;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        var p = e.GetPosition(this);
        if (_drag == Drag.Divider) MoveDivider(p.X);
        else if (_drag == Drag.Pan) Pan(p.X - _last.X, p.Y - _last.Y);
        else Cursor = Mode == StoryInspectMode.Curtain && Math.Abs(p.X - DividerX) < 10 ? Cursors.SizeWE : Zoom != 0 ? Cursors.Hand : Cursors.Arrow;
        _last = p;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        _drag = Drag.None;
        ReleaseMouseCapture();
        Cursor = Cursors.Arrow;
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        // roda: sobe e desce; Shift + roda: para os lados
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) Pan(e.Delta / 3.0, 0);
        else Pan(0, e.Delta / 3.0);
        e.Handled = true;
    }

    private void MoveDivider(double x)
    {
        if (ActualWidth <= 0) return;
        _split = Math.Min(Math.Max(x / ActualWidth, 0.02), 0.98);
        InvalidateVisual();
    }

    /// <summary>Arrastar a imagem para a direita mostra o que está à esquerda: o centro anda no sentido contrário.</summary>
    private void Pan(double dx, double dy)
    {
        if (Zoom == 0) return;
        var s = Scale(Panels[0]);
        _center.X = Math.Min(Math.Max(_center.X - dx / s, 0), ImageSize.Width);
        _center.Y = Math.Min(Math.Max(_center.Y - dy / s, 0), ImageSize.Height);
        InvalidateVisual();
    }
}
