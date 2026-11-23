using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IMPCriativos.Core.Imaging;
using SkiaSharp;

namespace IMPCriativos.App.UI;

/// <summary>Cores do tema escuro, iguais às do Mac (<c>Views/Components.swift</c> e AccentColor dos Assets).</summary>
public static class Brand
{
    public static readonly Color RedColor = Color.FromRgb(255, 51, 51);
    public static readonly SolidColorBrush Red = Freeze(new SolidColorBrush(RedColor));
    /// <summary>Superfície (cinza 0,11) e superfície elevada (cinza 0,15).</summary>
    public static readonly SolidColorBrush Surface = Freeze(new SolidColorBrush(Gray(0.11)));
    public static readonly SolidColorBrush SurfaceRaised = Freeze(new SolidColorBrush(Gray(0.15)));
    public static readonly SolidColorBrush Stroke = Freeze(new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)));
    public static readonly SolidColorBrush Warning = Freeze(new SolidColorBrush(Color.FromRgb(255, 184, 51)));
    public static readonly SolidColorBrush Success = Freeze(new SolidColorBrush(Color.FromRgb(77, 217, 128)));
    /// <summary>Fundo da área de conteúdo (cinza 0,07) e do cabeçalho do lote (0,09).</summary>
    public static readonly SolidColorBrush Background = Freeze(new SolidColorBrush(Gray(0.07)));
    public static readonly SolidColorBrush HeaderBackground = Freeze(new SolidColorBrush(Gray(0.09)));
    public static readonly SolidColorBrush Sidebar = Freeze(new SolidColorBrush(Gray(0.095)));
    public static readonly SolidColorBrush Text = Freeze(new SolidColorBrush(Color.FromRgb(240, 240, 240)));
    public static readonly SolidColorBrush Secondary = Freeze(new SolidColorBrush(Color.FromRgb(160, 160, 165)));
    public static readonly SolidColorBrush Tertiary = Freeze(new SolidColorBrush(Color.FromRgb(105, 105, 110)));
    public static readonly SolidColorBrush Black35 = Freeze(new SolidColorBrush(Color.FromArgb(89, 0, 0, 0)));
    public static readonly SolidColorBrush Field = Freeze(new SolidColorBrush(Gray(0.13)));

    private static Color Gray(double v) { var b = (byte)Math.Round(v * 255); return Color.FromRgb(b, b, b); }
    private static SolidColorBrush Freeze(SolidColorBrush b) { b.Freeze(); return b; }
}

/// <summary>Atalhos para montar as telas em código (sem XAML), com o mesmo visual em todas.</summary>
public static class U
{
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");

    public static TextBlock T(string text, double size = 13, bool bold = false, Brush? color = null, bool wrap = true,
        FontWeight? weight = null)
    {
        var t = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight ?? (bold ? FontWeights.SemiBold : FontWeights.Normal),
            Foreground = color ?? Brand.Text,
            TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
            TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis,
        };
        return t;
    }

    public static TextBlock Caption(string text, Brush? color = null) => T(text, 11.5, color: color ?? Brand.Secondary);

    public static TextBlock Title(string text) => T(text, 26, weight: FontWeights.Bold);

    public static StackPanel Header(string title, string? subtitle = null)
    {
        var s = V(4, Title(title));
        if (subtitle != null) s.Children.Add(T(subtitle, 13.5, color: Brand.Secondary));
        return s;
    }

    public static StackPanel V(double spacing, params UIElement?[] children) => Stack(Orientation.Vertical, spacing, children);
    public static StackPanel H(double spacing, params UIElement?[] children) => Stack(Orientation.Horizontal, spacing, children);

    public static StackPanel Stack(Orientation o, double spacing, IEnumerable<UIElement?> children)
    {
        var s = new StackPanel { Orientation = o };
        foreach (var c in children) Add(s, c, spacing);
        return s;
    }

    /// <summary>Acrescenta com espaçamento (como o spacing dos VStack/HStack).</summary>
    public static void Add(StackPanel s, UIElement? c, double spacing)
    {
        if (c == null) return;
        if (s.Children.Count > 0 && c is FrameworkElement fe)
        {
            var m = fe.Margin;
            fe.Margin = s.Orientation == Orientation.Vertical
                ? new Thickness(m.Left, m.Top + spacing, m.Right, m.Bottom)
                : new Thickness(m.Left + spacing, m.Top, m.Right, m.Bottom);
        }
        s.Children.Add(c);
    }

    /// <summary>Linha com itens à esquerda e à direita (Spacer no meio).</summary>
    public static DockPanel Row(IEnumerable<UIElement?> left, IEnumerable<UIElement?> right, double spacing = 8)
    {
        var d = new DockPanel { LastChildFill = true };
        var r = Stack(Orientation.Horizontal, spacing, right);
        r.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(r, Dock.Right);
        d.Children.Add(r);
        var l = Stack(Orientation.Horizontal, spacing, left);
        l.VerticalAlignment = VerticalAlignment.Center;
        d.Children.Add(l);
        return d;
    }

    public static Border Card(UIElement content, double padding = 16) => new()
    {
        Background = Brand.Surface,
        BorderBrush = Brand.Stroke,
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(12),
        Padding = new Thickness(padding),
        Child = content,
    };

    public static Border Section(string title, params UIElement?[] rows)
    {
        var s = V(10, rows);
        return new Border
        {
            Margin = new Thickness(0, 4, 0, 4),
            Child = V(8, T(title, 13, bold: true, color: Brand.Secondary), Card(s, 14)),
        };
    }

    public static Button Btn(string text, Action onClick, bool primary = false, string? tooltip = null, bool enabled = true)
    {
        var b = new Button
        {
            Content = text,
            Padding = new Thickness(14, 6, 14, 6),
            MinHeight = 30,
            IsEnabled = enabled,
            Cursor = Cursors.Hand,
        };
        if (primary)
        {
            b.Background = Brand.Red;
            b.Foreground = Brushes.White;
            b.BorderBrush = Brand.Red;
            b.FontWeight = FontWeights.SemiBold;
        }
        if (tooltip != null) b.ToolTip = tooltip;
        b.Click += (_, _) => onClick();
        return b;
    }

    public static Button Link(string text, Action onClick, Brush? color = null)
    {
        var b = new Button
        {
            Content = new TextBlock { Text = text, TextDecorations = TextDecorations.Underline, Foreground = color ?? Brand.Red },
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0),
            Cursor = Cursors.Hand,
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    public static CheckBox Toggle(string label, bool value, Action<bool> onChange, string? tooltip = null)
    {
        var c = new CheckBox { Content = T(label), IsChecked = value, VerticalContentAlignment = VerticalAlignment.Center };
        if (tooltip != null) c.ToolTip = tooltip;
        c.Checked += (_, _) => onChange(true);
        c.Unchecked += (_, _) => onChange(false);
        return c;
    }

    public static TextBox Field(string value, Action<string> onChange, string? placeholder = null, bool multiline = false,
        double minHeight = 0)
    {
        var t = new TextBox
        {
            Text = value,
            Padding = new Thickness(6, 4, 6, 4),
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            VerticalScrollBarVisibility = multiline ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled,
            MinHeight = minHeight,
            VerticalContentAlignment = multiline ? VerticalAlignment.Top : VerticalAlignment.Center,
        };
        if (placeholder != null) Placeholder.Set(t, placeholder);
        t.TextChanged += (_, _) => onChange(t.Text);
        return t;
    }

    public static ComboBox Combo<TItem>(IEnumerable<TItem> items, TItem? selected, Func<TItem, string> label, Action<TItem> onChange,
        double minWidth = 200)
    {
        var c = new ComboBox { MinWidth = minWidth };
        var list = items.ToList();
        foreach (var i in list) c.Items.Add(new ComboBoxItem { Content = label(i), Tag = i });
        var idx = list.FindIndex(i => Equals(i, selected));
        c.SelectedIndex = idx;
        c.SelectionChanged += (_, _) =>
        {
            if (c.SelectedItem is ComboBoxItem it && it.Tag is TItem v) onChange(v);
        };
        return c;
    }

    /// <summary>Botões lado a lado com um selecionado (equivalente do Picker segmentado).</summary>
    public static StackPanel Segmented<TItem>(IEnumerable<TItem> items, TItem selected, Func<TItem, string> label, Action<TItem> onChange)
    {
        var s = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var i in items)
        {
            var on = Equals(i, selected);
            var b = new ToggleButton
            {
                Content = label(i),
                IsChecked = on,
                Padding = new Thickness(12, 5, 12, 5),
                Margin = new Thickness(0, 0, 2, 0),
                Cursor = Cursors.Hand,
            };
            if (on) { b.Background = Brand.Red; b.Foreground = Brushes.White; }
            var item = i;
            b.Click += (_, _) => onChange(item);
            s.Children.Add(b);
        }
        return s;
    }

    public static Slider Slider(double min, double max, double value, Action<double> onChange, double step = 1)
    {
        var s = new Slider
        {
            Minimum = min,
            Maximum = max,
            Value = Math.Clamp(value, min, max),
            TickFrequency = step,
            IsSnapToTickEnabled = step > 0,
            MinWidth = 200,
            VerticalAlignment = VerticalAlignment.Center,
        };
        s.ValueChanged += (_, e) => onChange(e.NewValue);
        return s;
    }

    /// <summary>Rótulo à esquerda e controle à direita (como o LabeledContent).</summary>
    public static Grid Labeled(string label, UIElement control, double labelWidth = 220)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(labelWidth) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var l = T(label);
        l.VerticalAlignment = VerticalAlignment.Center;
        g.Children.Add(l);
        if (control is FrameworkElement fe) fe.HorizontalAlignment = HorizontalAlignment.Left;
        Grid.SetColumn(control, 1);
        g.Children.Add(control);
        return g;
    }

    public static StackPanel Warning(string text) => IconText("⚠", text, Brand.Warning);
    public static StackPanel Error(string text) => IconText("⛔", text, Brand.Red);

    public static StackPanel IconText(string icon, string text, Brush color, double size = 12)
    {
        var tb = T(text, size, color: color);
        tb.MaxWidth = 900;
        var s = new StackPanel { Orientation = Orientation.Horizontal };
        s.Children.Add(new TextBlock { Text = icon, Foreground = color, FontSize = size, Margin = new Thickness(0, 0, 6, 0) });
        s.Children.Add(tb);
        s.ToolTip = text;
        return s;
    }

    public static ScrollViewer Scroll(UIElement content, double padding = 28) => new()
    {
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        Content = new Border { Padding = new Thickness(padding), Child = content },
    };

    public static Border Pill(string text, Color color)
    {
        var dot = new System.Windows.Shapes.Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(color), Margin = new Thickness(0, 0, 5, 0) };
        var s = new StackPanel { Orientation = Orientation.Horizontal };
        s.Children.Add(dot);
        s.Children.Add(T(text, 11, bold: true, wrap: false));
        return new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(38, color.R, color.G, color.B)),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(8, 3, 8, 3),
            Child = s,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    public static ProgressBar Progress(double value, double width = double.NaN) => new()
    {
        Minimum = 0, Maximum = 1, Value = value, Height = 6, Width = width, Foreground = Brand.Red,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static Border Divider(bool vertical = false) => new()
    {
        Background = Brand.Stroke,
        Height = vertical ? double.NaN : 1,
        Width = vertical ? 1 : double.NaN,
        Margin = vertical ? new Thickness(6, 0, 6, 0) : new Thickness(0, 6, 0, 6),
    };

    // MARK: imagens

    public static BitmapSource? FromPng(byte[]? png)
    {
        if (png == null) return null;
        try
        {
            var img = new BitmapImage();
            using var ms = new MemoryStream(png);
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.StreamSource = ms;
            img.EndInit();
            img.Freeze();
            return img;
        }
        catch { return null; }
    }

    /// <summary>Pixels RGBX (1080×1920) do Otimizador → imagem da tela.</summary>
    public static BitmapSource FromRgbx(byte[] rgbx, int width, int height)
    {
        var bgra = new byte[rgbx.Length];
        for (var i = 0; i < rgbx.Length; i += 4)
        {
            bgra[i] = rgbx[i + 2];
            bgra[i + 1] = rgbx[i + 1];
            bgra[i + 2] = rgbx[i];
            bgra[i + 3] = 255;
        }
        var b = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, bgra, width * 4);
        b.Freeze();
        return b;
    }

    public static BitmapSource? FromSkia(SKBitmap? bmp)
    {
        if (bmp == null) return null;
        try
        {
            using var data = bmp.Encode(SKEncodedImageFormat.Png, 100);
            return FromPng(data?.ToArray());
        }
        catch { return null; }
    }

    /// <summary>Miniatura carregada fora da thread da tela (como o Thumb do Mac).</summary>
    public static Border Thumb(string? path, double size, int maxPixel = 480, Action? onClick = null, double opacity = 1)
    {
        var img = new Image { Stretch = Stretch.Uniform, Opacity = opacity };
        RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
        var host = new Grid();
        host.Children.Add(img);
        var wait = new ProgressBar { IsIndeterminate = true, Width = 40, Height = 4, Foreground = Brand.Red };
        if (path != null) host.Children.Add(wait);
        var border = new Border { Background = Brand.Black35, Width = size, Height = size, Child = host, ClipToBounds = true };
        if (onClick != null)
        {
            border.Cursor = Cursors.Hand;
            border.MouseLeftButtonUp += (_, _) => onClick();
        }
        if (path != null)
        {
            Task.Run(() => ImageTools.ThumbnailPng(path, maxPixel)).ContinueWith(t =>
            {
                img.Source = FromPng(t.Result);
                host.Children.Remove(wait);
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }
        return border;
    }
}

/// <summary>Texto de exemplo dentro do campo vazio.</summary>
public static class Placeholder
{
    public static void Set(TextBox box, string text)
    {
        var hint = new VisualBrush
        {
            AlignmentX = AlignmentX.Left,
            AlignmentY = box.AcceptsReturn ? AlignmentY.Top : AlignmentY.Center,
            Stretch = Stretch.None,
            Visual = new TextBlock { Text = text, Foreground = Brand.Tertiary, Margin = new Thickness(6, 4, 0, 0), FontSize = 13 },
        };
        void Update() => box.Background = string.IsNullOrEmpty(box.Text) ? hint : Brand.Field;
        box.TextChanged += (_, _) => Update();
        box.Loaded += (_, _) => Update();
    }
}
