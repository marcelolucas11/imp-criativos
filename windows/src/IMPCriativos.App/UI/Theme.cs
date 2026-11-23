using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace IMPCriativos.App.UI;

/// <summary>Tema escuro (Fluent do WPF em modo escuro) com o vermelho da marca como cor de destaque.</summary>
public static class Theme
{
    public static void Apply(Application app)
    {
        var r = app.Resources;
        var accent = Brand.RedColor;
        foreach (var key in new[] { "SystemAccentColor", "SystemAccentColorLight1", "SystemAccentColorLight2", "SystemAccentColorLight3",
                     "SystemAccentColorDark1", "SystemAccentColorDark2", "SystemAccentColorDark3" })
            r[key] = accent;
        r[SystemColors.HighlightBrushKey] = Brand.Red;
        r["AccentFillColorDefaultBrush"] = Brand.Red;
        r["AccentFillColorSecondaryBrush"] = new SolidColorBrush(Color.FromRgb(230, 46, 46));
        r["AccentFillColorTertiaryBrush"] = new SolidColorBrush(Color.FromRgb(205, 41, 41));
        r["AccentTextFillColorPrimaryBrush"] = Brand.Red;

        var text = new Style(typeof(TextBlock));
        text.Setters.Add(new Setter(TextBlock.FontFamilyProperty, U.Font));
        r[typeof(TextBlock)] = text;

        var window = new Style(typeof(Window));
        window.Setters.Add(new Setter(Control.FontFamilyProperty, U.Font));
        window.Setters.Add(new Setter(Control.BackgroundProperty, Brand.Background));
        window.Setters.Add(new Setter(Control.ForegroundProperty, Brand.Text));
        r[typeof(Window)] = window;
    }
}
