# 1.0.0-beta.27: compila a libjpeg-turbo para a versão Windows (turbojpeg.dll, x64), na MESMA versão e com o
# MESMO SHA-256 de scripts/build_libjpeg_turbo.sh (Mac). Também serve para gerar a libturbojpeg.so dos testes no Linux
# (pwsh no Ubuntu do GitHub Actions).
#
# Saída (fora do Git): windows/vendor/libjpeg-turbo/<win-x64|linux-x64>/ com a biblioteca, turbojpeg.h e LICENSE.md.
# Uso: pwsh scripts/build_libjpeg_turbo_windows.ps1   (pula se já estiver compilada)
$ErrorActionPreference = 'Stop'

# Versão e SHA-256 lidos do script do Mac: fonte única, as duas versões usam exatamente a mesma libjpeg-turbo.
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$macScript = Get-Content (Join-Path $root 'scripts/build_libjpeg_turbo.sh') -Raw
$version = [regex]::Match($macScript, 'VERSION="([^"]+)"').Groups[1].Value
$sha256 = [regex]::Match($macScript, 'SHA256="([0-9a-f]+)"').Groups[1].Value
if (-not $version -or -not $sha256) { throw 'Não consegui ler VERSION/SHA256 de scripts/build_libjpeg_turbo.sh' }

$isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
$rid = if ($isWin) { 'win-x64' } else { 'linux-x64' }
$out = Join-Path $root "windows/vendor/libjpeg-turbo/$rid"
$libName = if ($isWin) { 'turbojpeg.dll' } else { 'libturbojpeg.so' }

if ((Test-Path (Join-Path $out $libName)) -and ((Get-Content (Join-Path $out 'VERSION') -ErrorAction SilentlyContinue) -eq $version)) {
  Write-Host "libjpeg-turbo $version já compilada em $out"
  exit 0
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("ljt-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $url = "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$version/libjpeg-turbo-$version.tar.gz"
  $tar = Join-Path $work 'src.tar.gz'
  Write-Host "Baixando libjpeg-turbo $version…"
  Invoke-WebRequest -Uri $url -OutFile $tar -MaximumRetryCount 3
  $actual = (Get-FileHash -Algorithm SHA256 $tar).Hash.ToLowerInvariant()
  if ($actual -ne $sha256) { throw "SHA-256 não confere: $actual (esperado $sha256)" }
  tar -xzf $tar -C $work
  $src = Join-Path $work "libjpeg-turbo-$version"
  $build = Join-Path $work 'build'
  $prefix = Join-Path $work 'install'
  $args = @('-S', $src, '-B', $build, '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_INSTALL_PREFIX=$prefix",
            '-DENABLE_SHARED=ON', '-DENABLE_STATIC=OFF', '-DWITH_TURBOJPEG=ON', '-DWITH_TOOLS=OFF', '-DWITH_JAVA=OFF')
  if ($isWin) { $args += @('-A', 'x64') }
  & cmake @args
  if ($LASTEXITCODE -ne 0) { throw 'cmake configure falhou' }
  & cmake --build $build --config Release --parallel
  if ($LASTEXITCODE -ne 0) { throw 'cmake build falhou' }
  & cmake --install $build --config Release
  if ($LASTEXITCODE -ne 0) { throw 'cmake install falhou' }

  if (Test-Path $out) { Remove-Item -Recurse -Force $out }
  New-Item -ItemType Directory -Path $out | Out-Null
  if ($isWin) {
    $dll = Get-ChildItem -Path $prefix -Recurse -Filter 'turbojpeg.dll' | Select-Object -First 1
    if (-not $dll) { throw 'turbojpeg.dll não foi gerada' }
    Copy-Item $dll.FullName (Join-Path $out 'turbojpeg.dll')
  } else {
    $so = Get-ChildItem -Path $prefix -Recurse -Filter 'libturbojpeg.so*' | Where-Object { -not $_.PSIsContainer } |
          Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1
    if (-not $so) { throw 'libturbojpeg.so não foi gerada' }
    Copy-Item $so.FullName (Join-Path $out 'libturbojpeg.so')
  }
  Copy-Item (Join-Path $prefix 'include/turbojpeg.h') (Join-Path $out 'turbojpeg.h')
  Copy-Item (Join-Path $src 'LICENSE.md') (Join-Path $out 'LICENSE.md')
  Set-Content -Path (Join-Path $out 'VERSION') -Value $version
  Write-Host "libjpeg-turbo $version pronta em $out"
  Get-ChildItem $out
}
finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
