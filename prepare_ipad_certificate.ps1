param([string]$OutputDirectory = "", [int]$ValidDays = 30)
$ErrorActionPreference = "Stop"
# Self-signed leaf only: root trust was NOT installed by this script.
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:LOCALAPPDATA "AI_PRONOTE\v1.5\ipad-cert-v2" }
$address = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
    Sort-Object InterfaceMetric | Select-Object -First 1 -ExpandProperty IPAddress
if (-not $address) { throw "No LAN IPv4 address found" }
$cert = Join-Path $OutputDirectory "pronote-ipad.pem"
$key = Join-Path $OutputDirectory "pronote-ipad-key.pem"
$caCert = Join-Path $OutputDirectory "AI-PRONOTE-iPad-CA.cer"
$caKey = Join-Path $OutputDirectory "pronote-ipad-ca-key.pem"
if ((Test-Path -LiteralPath $cert) -or (Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath $caCert) -or (Test-Path -LiteralPath $caKey)) {
    throw "Certificate output already exists; refusing overwrite."
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$caRsa = [Security.Cryptography.RSA]::Create(3072)
$caReq = [Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=AI PRONOTE v1.5 iPad Local CA", $caRsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$caReq.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
$caReq.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign,$true))
$caReq.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($caReq.PublicKey,$false))
$caObj = $caReq.CreateSelfSigned([DateTimeOffset]::Now.AddMinutes(-5), [DateTimeOffset]::Now.AddDays([Math]::Max(2,[Math]::Min($ValidDays+1,91))))
$rsa = [Security.Cryptography.RSA]::Create(3072)
$req = [Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=AI PRONOTE v1.5 iPad Test", $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
$san.AddIpAddress([Net.IPAddress]::Parse($address)); $san.AddIpAddress([Net.IPAddress]::Loopback); $san.AddDnsName("localhost")
$req.CertificateExtensions.Add($san.Build())
$req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
$req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment,$true))
$oids = [Security.Cryptography.OidCollection]::new(); [void]$oids.Add([Security.Cryptography.Oid]::new("1.3.6.1.5.5.7.3.1"))
$req.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
$serial = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Fill($serial)
$certObj = $req.Create($caObj,[DateTimeOffset]::Now.AddMinutes(-5),[DateTimeOffset]::Now.AddDays([Math]::Max(1,[Math]::Min($ValidDays,90))),$serial)
function Write-Pem([string]$Label,[byte[]]$Bytes,[string]$Path) {
    $body=[Convert]::ToBase64String($Bytes,[Base64FormattingOptions]::InsertLineBreaks)
    [IO.File]::WriteAllText($Path,"-----BEGIN $Label-----`r`n$body`r`n-----END $Label-----`r`n",[Text.UTF8Encoding]::new($false))
}
Write-Pem "CERTIFICATE" $certObj.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert) $cert
Write-Pem "PRIVATE KEY" $rsa.ExportPkcs8PrivateKey() $key
Write-Pem "PRIVATE KEY" $caRsa.ExportPkcs8PrivateKey() $caKey
[IO.File]::WriteAllBytes($caCert,$caObj.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
icacls $OutputDirectory /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null
[pscustomobject]@{Certificate=$cert;PrivateKey=$key;IPadPublicCA=$caCert;LanAddress=$address;NotAfter=$certObj.NotAfter.ToString("o");LeafSha1Fingerprint=$certObj.Thumbprint;CASha1Fingerprint=$caObj.Thumbprint;TrustInstalled=$false} | ConvertTo-Json
