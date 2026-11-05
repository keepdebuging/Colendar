$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

node (Join-Path $PSScriptRoot 'configure-build.mjs')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$hvigor = $env:HARMONY_HVIGOR
if (-not $hvigor) {
  $wrapper = Join-Path $root 'hvigorw.bat'
  if (Test-Path -LiteralPath $wrapper) {
    $hvigor = $wrapper
  } else {
    $command = Get-Command hvigor -ErrorAction SilentlyContinue
    if ($command) { $hvigor = $command.Source }
  }
}
if (-not $hvigor) {
  Write-Error 'Hvigor was not found. Set HARMONY_HVIGOR or install the project toolchain.'
  exit 1
}

& $hvigor --mode module -p product=default -p module=entry@default test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
