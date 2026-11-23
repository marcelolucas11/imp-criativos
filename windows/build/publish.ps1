# 1.0.0-beta.27: publica o app Windows (self-contained, x64, arquivo único + turbojpeg.dll ao lado)
# e, se o Inno Setup estiver instalado, gera o instalador IMP-Criativos-Setup-<versão>-windows-x64.exe e o .sha256.
# Saída: windows/artifacts/publish (app) e windows/artifacts/dist (instalador).
# Uso: pwsh windows/build/publish.ps1 [-NoInstaller]
param([switch]$NoInstaller)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$publish = Join-Path $root 'windows/artifacts/publish'
$dist = Join-Path $root 'windows/artifacts/dist'
Remove-Item -Recurse -Force $publish, $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $publish, $dist | Out-Null

dotnet publish (Join-Path $root 'windows/src/IMPCriativos.App/IMPCriativos.App.csproj') -c Release -r win-x64 `
  --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:DebugType=none -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish falhou ($LASTEXITCODE)" }

$exe = Join-Path $publish 'IMP Criativos.exe'
if (-not (Test-Path $exe)) { throw "Não achei $exe" }
if (-not (Test-Path (Join-Path $publish 'turbojpeg.dll'))) { throw 'turbojpeg.dll não foi copiada para a publicação (rode scripts/build_libjpeg_turbo_windows.ps1)' }
Get-ChildItem $publish | Format-Table Name, Length

if ($NoInstaller) { exit 0 }
$iscc = @(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
  Write-Host 'Inno Setup não encontrado: instalando pelo Chocolatey…'
  choco install innosetup --no-progress -y | Out-Null
  $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
& $iscc "/DAppVersion=$version" "/DPublishDir=$publish" "/DOutputDir=$dist" (Join-Path $root 'windows/installer/IMPCriativos.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC falhou ($LASTEXITCODE)" }

$setup = Join-Path $dist "IMP-Criativos-Setup-$version-windows-x64.exe"
if (-not (Test-Path $setup)) { throw "Instalador não gerado: $setup" }
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$setup.sha256" -Value $hash -NoNewline -Encoding ascii
Get-ChildItem $dist | Format-Table Name, Length
