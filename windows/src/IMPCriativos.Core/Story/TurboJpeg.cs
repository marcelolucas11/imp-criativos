using System.Reflection;
using System.Runtime.InteropServices;

namespace IMPCriativos.Core.Story;

/// <summary>
/// Ponte para a libjpeg-turbo (TurboJPEG 3), a mesma versão do Mac (<c>scripts/build_libjpeg_turbo.sh</c>).
/// No Windows a <c>turbojpeg.dll</c> vai junto do app; nos testes do Linux, a <c>libturbojpeg.so</c> compilada no CI.
/// As funções são carregadas na hora (NativeLibrary) para o app não cair se a biblioteca faltar: aí o JPEG sai pelo Skia.
/// Os números das constantes são os de <c>turbojpeg.h</c> (o teste <c>TurboJpegHeaderTests</c> confere no cabeçalho baixado).
/// </summary>
public static unsafe class TurboJpeg
{
    public const int TJINIT_COMPRESS = 0;
    public const int TJPARAM_QUALITY = 3;
    public const int TJPARAM_SUBSAMP = 4;
    public const int TJPARAM_OPTIMIZE = 11;
    public const int TJPARAM_PROGRESSIVE = 12;
    public const int TJSAMP_444 = 0;
    public const int TJSAMP_420 = 2;
    public const int TJPF_RGBX = 2;
    /// <summary>TURBOJPEG_VERSION_NUMBER da 3.2.1 (usado só se a biblioteca exportar tj3InitVersion no lugar de tj3Init).</summary>
    public const int VersionNumber = 3002001;

    private static readonly object Lock = new();
    private static bool _tried;
    private static IntPtr _lib;
    private static delegate* unmanaged[Cdecl]<int, IntPtr> _init;
    private static delegate* unmanaged[Cdecl]<int, int, IntPtr> _initVersion;
    private static delegate* unmanaged[Cdecl]<IntPtr, int, int, int> _set;
    private static delegate* unmanaged[Cdecl]<IntPtr, byte*, nuint, int> _setIcc;
    private static delegate* unmanaged[Cdecl]<IntPtr, byte*, int, int, int, int, byte**, nuint*, int> _compress8;
    private static delegate* unmanaged[Cdecl]<void*, void> _free;
    private static delegate* unmanaged[Cdecl]<IntPtr, void> _destroy;
    private static delegate* unmanaged[Cdecl]<IntPtr, IntPtr> _errorStr;

    /// <summary>Pasta extra onde procurar a biblioteca (testes).</summary>
    public static string? SearchFolder { get; set; } = Environment.GetEnvironmentVariable("IMP_TURBOJPEG_DIR");

    public static string? LoadError { get; private set; }

    public static bool Available
    {
        get
        {
            lock (Lock)
            {
                if (!_tried) { _tried = true; TryLoad(); }
                return _lib != IntPtr.Zero && _set != null && _compress8 != null && (_init != null || _initVersion != null);
            }
        }
    }

    private static void TryLoad()
    {
        var names = OperatingSystem.IsWindows()
            ? new[] { "turbojpeg.dll", "turbojpeg" }
            : OperatingSystem.IsMacOS() ? new[] { "libturbojpeg.dylib", "turbojpeg" } : new[] { "libturbojpeg.so", "libturbojpeg.so.0", "turbojpeg" };
        var folders = new List<string?> { SearchFolder, AppContext.BaseDirectory, Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) };
        var found = false;
        foreach (var folder in folders.Where(f => !string.IsNullOrEmpty(f)))
        {
            foreach (var n in names)
            {
                var p = Path.Combine(folder!, n);
                if (File.Exists(p) && NativeLibrary.TryLoad(p, out _lib)) { found = true; break; }
            }
            if (found) break;
        }
        if (!found)
            foreach (var n in names)
                if (NativeLibrary.TryLoad(n, out _lib)) { found = true; break; }
        if (!found)
        {
            LoadError = "libjpeg-turbo não encontrada";
            return;
        }
        IntPtr F(string name) => NativeLibrary.TryGetExport(_lib, name, out var f) ? f : IntPtr.Zero;
        _init = (delegate* unmanaged[Cdecl]<int, IntPtr>)F("tj3Init");
        _initVersion = (delegate* unmanaged[Cdecl]<int, int, IntPtr>)F("tj3InitVersion");
        _set = (delegate* unmanaged[Cdecl]<IntPtr, int, int, int>)F("tj3Set");
        _setIcc = (delegate* unmanaged[Cdecl]<IntPtr, byte*, nuint, int>)F("tj3SetICCProfile");
        _compress8 = (delegate* unmanaged[Cdecl]<IntPtr, byte*, int, int, int, int, byte**, nuint*, int>)F("tj3Compress8");
        _free = (delegate* unmanaged[Cdecl]<void*, void>)F("tj3Free");
        _destroy = (delegate* unmanaged[Cdecl]<IntPtr, void>)F("tj3Destroy");
        _errorStr = (delegate* unmanaged[Cdecl]<IntPtr, IntPtr>)F("tj3GetErrorStr");
    }

    /// <summary>
    /// JPEG com qualidade, baseline/progressivo e subamostragem 4:2:0/4:4:4 do sorteio,
    /// com perfil sRGB e nenhum outro metadado (sem EXIF, XMP, IPTC nem comentário).
    /// </summary>
    public static byte[] Compress(byte[] rgbx, int width, int height, int quality, bool chroma444, bool progressive, byte[]? icc)
    {
        if (!Available) throw new InvalidOperationException(LoadError ?? "libjpeg-turbo indisponível");
        var handle = _init != null ? _init(TJINIT_COMPRESS) : _initVersion(TJINIT_COMPRESS, VersionNumber);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("libjpeg-turbo não iniciou");
        try
        {
            void Check(int code)
            {
                if (code != 0)
                {
                    var msg = _errorStr != null ? Marshal.PtrToStringAnsi(_errorStr(handle)) : null;
                    throw new InvalidOperationException(msg ?? $"libjpeg-turbo erro {code}");
                }
            }
            Check(_set(handle, TJPARAM_QUALITY, quality));
            Check(_set(handle, TJPARAM_SUBSAMP, chroma444 ? TJSAMP_444 : TJSAMP_420));
            Check(_set(handle, TJPARAM_PROGRESSIVE, progressive ? 1 : 0));
            Check(_set(handle, TJPARAM_OPTIMIZE, 1));
            if (icc is { Length: > 0 } && _setIcc != null)
                fixed (byte* ip = icc) Check(_setIcc(handle, ip, (nuint)icc.Length));
            byte* jpeg = null;
            nuint size = 0;
            fixed (byte* src = rgbx)
                Check(_compress8(handle, src, width, width * 4, height, TJPF_RGBX, &jpeg, &size));
            if (jpeg == null || size == 0) throw new InvalidOperationException("JPEG vazio");
            try
            {
                var o = new byte[(int)size];
                Marshal.Copy((IntPtr)jpeg, o, 0, o.Length);
                return o;
            }
            finally
            {
                if (_free != null) _free(jpeg);
            }
        }
        finally
        {
            if (_destroy != null) _destroy(handle);
        }
    }
}
