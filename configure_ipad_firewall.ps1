param([ValidateSet("Apply","Rollback")][string]$Action="Apply",[int]$Port=8796)
$ErrorActionPreference="Stop"
$name="AI PRONOTE v1.5 iPad test HTTPS"
if ($Action -eq "Rollback") {
  Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Write-Host "Removed firewall rule: $name"; exit 0
}
if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) { throw "Firewall rule already exists; refusing replacement." }
New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Private -RemoteAddress LocalSubnet -Description "AI PRONOTE v1.5 explicit iPad HTTPS test only" | Out-Null
Get-NetFirewallRule -DisplayName $name | Get-NetFirewallPortFilter | Select-Object Protocol,LocalPort
Get-NetFirewallRule -DisplayName $name | Get-NetFirewallAddressFilter | Select-Object RemoteAddress
