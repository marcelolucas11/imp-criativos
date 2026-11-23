using System.Windows;
using System.Windows.Threading;
using IMPCriativos.App.Services;
using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Story;
using IMPCriativos.Core.Updates;

namespace IMPCriativos.App;

/// <summary>Entrada do programa (fora da classe App para o WPF não gerar outro Main).</summary>
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        // teste de fumaça do CI: abre cada tela, roda o Otimizador e salva capturas (sem instância única)
        var smoke = Array.IndexOf(args, "--smoke-test");
        if (smoke >= 0)
        {
            var folder = smoke + 1 < args.Length ? args[smoke + 1] : Path.Combine(Path.GetTempPath(), "imp-smoke");
            return SmokeTest.Run(folder);
        }

        Toast.RegisterProcess();
        var single = new SingleInstance();
        if (!single.IsFirst)
        {
            SingleInstance.SignalFirst();
            single.Dispose();
            return 0;
        }
        var app = new App { _single = single };
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var background = args.Contains("--background");
        app.Startup += (_, _) => app.Boot(showWindow: !background);
        var code = app.Run();
        single.Dispose();
        return code;
    }

}
