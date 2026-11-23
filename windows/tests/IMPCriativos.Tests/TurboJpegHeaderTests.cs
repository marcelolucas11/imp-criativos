using System.Text.RegularExpressions;
using IMPCriativos.Core.Story;
using Xunit;

namespace IMPCriativos.Tests;

/// <summary>
/// Os números das constantes da TurboJPEG usados por P/Invoke conferem com o turbojpeg.h da versão compilada no CI
/// (a mesma do Mac). Sem o cabeçalho (rodando fora do CI), o teste é pulado.
/// </summary>
public class TurboJpegHeaderTests
{
    private static int EnumIndex(string header, string enumName, string member)
    {
        var m = Regex.Match(header, @"enum\s+" + enumName + @"\s*\{(?<body>[^}]*)\}", RegexOptions.Singleline);
        Assert.True(m.Success, $"enum {enumName} não encontrado");
        var body = Regex.Replace(m.Groups["body"].Value, @"/\*.*?\*/", "", RegexOptions.Singleline);
        body = Regex.Replace(body, @"//[^\n]*", "");
        var names = body.Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
        var idx = 0;
        foreach (var n in names)
        {
            var parts = n.Split('=');
            if (parts.Length > 1) idx = int.Parse(parts[1].Trim());
            if (parts[0].Trim() == member) return idx;
            idx++;
        }
        throw new Exception($"{member} não encontrado em {enumName}");
    }

    [Fact]
    public void ConstantsMatchHeader()
    {
        var dir = Environment.GetEnvironmentVariable("IMP_TURBOJPEG_DIR");
        var path = dir == null ? null : Path.Combine(dir, "turbojpeg.h");
        if (path == null || !File.Exists(path)) return;
        var h = File.ReadAllText(path);
        Assert.Equal(TurboJpeg.TJINIT_COMPRESS, EnumIndex(h, "TJINIT", "TJINIT_COMPRESS"));
        Assert.Equal(TurboJpeg.TJPARAM_QUALITY, EnumIndex(h, "TJPARAM", "TJPARAM_QUALITY"));
        Assert.Equal(TurboJpeg.TJPARAM_SUBSAMP, EnumIndex(h, "TJPARAM", "TJPARAM_SUBSAMP"));
        Assert.Equal(TurboJpeg.TJPARAM_OPTIMIZE, EnumIndex(h, "TJPARAM", "TJPARAM_OPTIMIZE"));
        Assert.Equal(TurboJpeg.TJPARAM_PROGRESSIVE, EnumIndex(h, "TJPARAM", "TJPARAM_PROGRESSIVE"));
        Assert.Equal(TurboJpeg.TJSAMP_444, EnumIndex(h, "TJSAMP", "TJSAMP_444"));
        Assert.Equal(TurboJpeg.TJSAMP_420, EnumIndex(h, "TJSAMP", "TJSAMP_420"));
        Assert.Equal(TurboJpeg.TJPF_RGBX, EnumIndex(h, "TJPF", "TJPF_RGBX"));
        Assert.True(TurboJpeg.Available, TurboJpeg.LoadError ?? "libjpeg-turbo não carregou");
    }
}
