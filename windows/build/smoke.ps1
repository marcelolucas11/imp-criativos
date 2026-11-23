# 1.0.0-beta.27: teste de fumaça do app publicado. Abre cada tela com dados de exemplo (pasta própria, não usa a sua),
# salva capturas PNG, roda o Otimizador em 3 imagens e confere 1080×1920, sem EXIF/GPS/XMP e mesma semente = mesmo arquivo.
# Saída: windows/artifacts/smoke (capturas/ e resultado.txt). Uso: pwsh windows/build/smoke.ps1
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$exe = Join-Path $root 'windows/artifacts/publish/IMP Criativos.exe'
if (-not (Test-Path $exe)) { throw "Rode antes windows/build/publish.ps1 ($exe não existe)" }
$out = Join-Path $root 'windows/artifacts/smoke'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out | Out-Null

$p = Start-Process -FilePath $exe -ArgumentList @('--smoke-test', "`"$out`"") -PassThru
if (-not $p.WaitForExit(300000)) { $p.Kill(); throw 'Teste de fumaça passou de 5 minutos' }
$result = Join-Path $out 'resultado.txt'
if (Test-Path $result) { Get-Content $result } else { Write-Host 'resultado.txt não foi gerado' }
Get-ChildItem (Join-Path $out 'capturas') -ErrorAction SilentlyContinue | Format-Table Name, Length
# prévias em base64 no log (para conferir as telas sem baixar o artefato)
Get-ChildItem (Join-Path $out 'previas') -Filter *.jpg -ErrorAction SilentlyContinue | ForEach-Object {
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
  for ($i = 0; $i -lt $b64.Length; $i += 4000) { Write-Host "CAPTURA-B64 $($_.BaseName) $($b64.Substring($i, [Math]::Min(4000, $b64.Length - $i)))" }
}
# não sobe os dados de exemplo nem as entradas, só capturas, saídas do Otimizador e o resultado
Remove-Item -Recurse -Force (Join-Path $out 'dados') -ErrorAction SilentlyContinue
if ($p.ExitCode -ne 0) { throw "Teste de fumaça falhou (código $($p.ExitCode))" }
