param([int]$Port=8796,[string]$CertificateDirectory=(Join-Path $env:LOCALAPPDATA "AI_PRONOTE\v1.5\ipad-cert-v2"))
$ErrorActionPreference="Stop"
& (Join-Path $PSScriptRoot "configure_ipad_firewall.ps1") -Action Rollback -Port $Port
if (Test-Path -LiteralPath $CertificateDirectory) {
  $resolved=(Resolve-Path -LiteralPath $CertificateDirectory).Path
  $allowed=(Join-Path $env:LOCALAPPDATA "AI_PRONOTE\v1.5\ipad-cert-v2")
  if ($resolved -ne $allowed) { throw "Refusing to delete unexpected certificate directory: $resolved" }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "iPad test firewall and v1.5-only certificate/key removed."
