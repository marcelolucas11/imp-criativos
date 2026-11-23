using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using IMPCriativos.App.UI;

namespace IMPCriativos.App.Views;

/// <summary>
/// Base das telas: monta o conteúdo em <see cref="Render"/> e redesenha quando os dados mudam
/// (com intervalo mínimo, para não piscar enquanto um lote roda).
/// </summary>
public abstract class Page : UserControl
{
    protected AppModel Model => AppModel.Shared;
    private readonly DispatcherTimer _timer;
    private readonly List<Action> _unsubscribe = new();
    private bool _attached;

    protected Page()
    {
        Background = Brand.Background;
        Foreground = Brand.Text;
        _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(300) };
        _timer.Tick += (_, _) => { _timer.Stop(); Rerender(); };
        Loaded += (_, _) =>
        {
            if (!_attached) { _attached = true; Attach(); }
            Rerender();
        };
        Unloaded += (_, _) => Detach();
    }

    /// <summary>Assinaturas de eventos da tela (desfeitas em <see cref="Detach"/>).</summary>
    protected virtual void Attach() { }

    protected void Subscribe(Action subscribe, Action unsubscribe)
    {
        subscribe();
        _unsubscribe.Add(unsubscribe);
    }

    public void Detach()
    {
        foreach (var u in _unsubscribe) try { u(); } catch { }
        _unsubscribe.Clear();
        _attached = false;
        _timer.Stop();
    }

    /// <summary>Pede um redesenho (pode ser chamado de qualquer thread).</summary>
    public void Invalidate()
    {
        if (Dispatcher.CheckAccess()) { if (!_timer.IsEnabled) _timer.Start(); }
        else Dispatcher.BeginInvoke(() => { if (!_timer.IsEnabled) _timer.Start(); });
    }

    /// <summary>Redesenha já.</summary>
    public void Rerender()
    {
        double offset = 0;
        if (Content is ScrollViewer sv) offset = sv.VerticalOffset;
        Content = Render();
        if (Content is ScrollViewer nsv && offset > 0)
            nsv.Loaded += (_, _) => nsv.ScrollToVerticalOffset(offset);
    }

    protected abstract UIElement Render();

    public static string Short(DateTime d) => d.ToLocalTime().ToString("dd/MM/yy HH:mm", CultureInfo.InvariantCulture);

    protected void Alert(string title, string text) =>
        MessageBox.Show(Window.GetWindow(this)!, text, title, MessageBoxButton.OK, MessageBoxImage.Information);

    protected bool Confirm(string title, string text, string ok = "OK")
    {
        var r = MessageBox.Show(Window.GetWindow(this)!, text, title, MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel);
        return r == MessageBoxResult.OK;
    }
}
