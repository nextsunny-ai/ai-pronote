param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [string]$Version = '1.0.1',
    [string]$CandidateId = 'local'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Stage = Join-Path ([IO.Path]::GetTempPath()) ('ai-pronote-' + [guid]::NewGuid().ToString('N'))
$PackageName = "AI_PRONOTE_${Version}_desktop_full_candidate_${CandidateId}"
$PackageRoot = Join-Path $Stage $PackageName
$ZipPath = Join-Path $OutputDirectory ($PackageName + '.zip')

$RootFiles = @(
    '.env.example', '1_FIRST_SETUP.cmd', '2_AI_LOGIN.cmd', '3_START_AI_PRONOTE.vbs',
    'AI_PRONOTE_사용설명서.md', 'README.md', 'README_v15.md', 'SECURITY.md',
    'diarize.py', 'generate_meeting_report.py', 'icon_v15_pro_note.ico',
    'install_external_beta.ps1', 'main.py', 'postprocess.py', 'pronote_p0.py',
    'pronote_drive_watcher.py', 'provider_api.py', 'requirements-lock.txt', 'requirements.txt',
    'secure_credentials.py', 'stable_launcher.py', 'start_v15.ps1', 'start_v15.vbs',
    'start_v15_server_only.ps1', 'start_v15_server_only.vbs', 'start_ipad_companion.ps1',
    'prepare_ipad_certificate.ps1', 'configure_ipad_firewall.ps1',
    'rollback_ipad_test.ps1', 'setup_mac.command', 'start_mac.command', 'updater.py',
    'uninstall_mac.command', '빠른시작_가이드.md', '상황별_사용가이드.md'
)
$Directories = @('static', 'mac')
$PublicDocs = @(
    'AI_PRONOTE_v1.5_Beta10_사용설명서.pdf',
    'AI_PRONOTE_v1.5_빠른사용안내_2page.pdf',
    'FAQ_외부베타_v1.md', 'Mac_첫사용_체크리스트.md',
    '지원환경_v1.md', '알려진_제한_v1.md', '제거_롤백_v1.md',
    '휴대폰_iPad_사용가이드.md'
)

if (Test-Path -LiteralPath $ZipPath) {
    throw "Refusing to overwrite existing candidate: $ZipPath"
}

try {
    New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    foreach ($Relative in $RootFiles) {
        $Source = Join-Path $Root $Relative
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "Required release file is missing: $Relative"
        }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $PackageRoot $Relative)
    }
    foreach ($Relative in $Directories) {
        $Source = Join-Path $Root $Relative
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw "Required release directory is missing: $Relative"
        }
        Copy-Item -LiteralPath $Source -Destination $PackageRoot -Recurse
    }
    $DocsTarget = Join-Path $PackageRoot 'docs'
    New-Item -ItemType Directory -Path $DocsTarget | Out-Null
    foreach ($Relative in $PublicDocs) {
        $Source = Join-Path (Join-Path $Root 'docs') $Relative
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "Required public document is missing: $Relative"
        }
        Copy-Item -LiteralPath $Source -Destination $DocsTarget
    }
    New-Item -ItemType Directory -Path (Join-Path $PackageRoot 'data_v15') | Out-Null
    Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -CompressionLevel Optimal
    $Hash = Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256
    [pscustomobject]@{
        Path = $ZipPath
        Size = (Get-Item -LiteralPath $ZipPath).Length
        SHA256 = $Hash.Hash
    }
} finally {
    $ResolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $ResolvedStage = [IO.Path]::GetFullPath($Stage)
    if ($ResolvedStage.StartsWith($ResolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $ResolvedStage).StartsWith('ai-pronote-')) {
        Remove-Item -LiteralPath $ResolvedStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
