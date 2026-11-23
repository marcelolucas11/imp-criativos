using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.App.UI;

/// <summary>
/// 1.0.0-beta.11: botão que abre um menu em duas camadas — plataforma › modelo.
/// Com <c>allowNone</c>, oferece "Nenhuma" (usado na reserva).
/// </summary>
public static class ModelMenu
{
    public static Button Create(ModelRole role, ModelChoice? selection, Action<ModelChoice?> onSelect, bool allowNone = false,
        string noneLabel = "Nenhuma (não trocar)", double width = 320)
    {
        var label = selection != null ? $"{selection.Provider.Label()}  ›  {selection.Model}" : noneLabel;
        var b = new Button
        {
            Content = new TextBlock { Text = label + "  ▾", TextTrimming = TextTrimming.CharacterEllipsis },
            Width = width,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(10, 5, 10, 5),
            ToolTip = selection?.Label ?? noneLabel,
        };
        b.Click += (_, _) =>
        {
            var menu = Build(role, selection, onSelect, allowNone, noneLabel);
            menu.PlacementTarget = b;
            menu.Placement = PlacementMode.Bottom;
            menu.IsOpen = true;
        };
        return b;
    }

    private static ContextMenu Build(ModelRole role, ModelChoice? selection, Action<ModelChoice?> onSelect, bool allowNone, string noneLabel)
    {
        var menu = new ContextMenu();
        var catalog = ModelCatalog.Shared;
        foreach (var p in ProviderKindExt.All)
        {
            var sub = new MenuItem { Header = p.PlatformLabel() + (ApiKeyStore.HasKey(p) ? "" : " — sem chave") };
            // 1.0.0-beta.12: lista fixa com todos os modelos, agrupada; nada de digitar nome.
            var options = catalog.Options(p, role);
            foreach (var g in ModelTierExt.All)
            {
                var inGroup = options.Where(o => o.Tier == g).ToList();
                if (inGroup.Count == 0) continue;
                if (sub.Items.Count > 0) sub.Items.Add(new Separator());
                sub.Items.Add(new MenuItem { Header = g.Title(), IsEnabled = false, FontWeight = FontWeights.SemiBold });
                foreach (var o in inGroup) sub.Items.Add(Item(p, o.Id, o.MenuLabel, selection, onSelect));
            }
            var extra = catalog.ExtraModels(p, role, selection?.Provider == p ? selection?.Model : null);
            if (extra.Count > 0)
            {
                sub.Items.Add(new Separator());
                sub.Items.Add(new MenuItem { Header = "Novos, vistos pela sua chave", IsEnabled = false, FontWeight = FontWeights.SemiBold });
                foreach (var m in extra) sub.Items.Add(Item(p, m, m, selection, onSelect));
            }
            menu.Items.Add(sub);
        }
        if (allowNone)
        {
            menu.Items.Add(new Separator());
            var none = new MenuItem { Header = noneLabel, IsCheckable = true, IsChecked = selection == null };
            none.Click += (_, _) => onSelect(null);
            menu.Items.Add(none);
        }
        return menu;
    }

    private static MenuItem Item(ProviderKind p, string model, string label, ModelChoice? selection, Action<ModelChoice?> onSelect)
    {
        var choice = new ModelChoice(p, model);
        var mi = new MenuItem { Header = label, IsCheckable = true, IsChecked = selection == choice };
        mi.Click += (_, _) => onSelect(choice);
        return mi;
    }
}
