# 创建或复用家庭成员，授予一个或多个媒体源，并签发仅显示一次的设备 Token。
[CmdletBinding(DefaultParameterSetName = 'NewMember')]
param(
    [Parameter(Mandatory, ParameterSetName = 'NewMember')]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory, ParameterSetName = 'ExistingMember')]
    [ValidateNotNullOrEmpty()]
    [string]$UserId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$SourceId,

    [ValidateNotNullOrEmpty()]
    [string]$TokenName = '家庭设备',

    [string]$ExpiresAt,
    [string]$Server = 'http://127.0.0.1:8080',
    [string]$AdminTokenFile,
    [string]$AdminExecutable,
    [switch]$AllowInsecure
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($AdminTokenFile)) {
    $AdminTokenFile = Join-Path $ProjectDir 'data\secrets\api_token'
}
if ([string]::IsNullOrWhiteSpace($AdminExecutable)) {
    $AdminExecutable = Join-Path $ProjectDir 'dist\luma-admin.exe'
}

if (-not (Test-Path -LiteralPath $AdminExecutable -PathType Leaf)) {
    $DistDir = Split-Path -Parent $AdminExecutable
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    Push-Location $ProjectDir
    try {
        Write-Host '未找到 luma-admin，正在构建…'
        & go build -trimpath -o $AdminExecutable ./cmd/admin
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    finally {
        Pop-Location
    }
}

$AdminArgs = @('-server', $Server, '-token-file', $AdminTokenFile)
if ($AllowInsecure) { $AdminArgs += '-allow-insecure' }
$AdminArgs += @('family', 'issue')
if ($PSCmdlet.ParameterSetName -eq 'ExistingMember') {
    $AdminArgs += @('-user', $UserId)
}
else {
    $AdminArgs += @('-name', $Name)
}
foreach ($Id in $SourceId) {
    $AdminArgs += @('-source', $Id)
}
$AdminArgs += @('-token-name', $TokenName)
if (-not [string]::IsNullOrWhiteSpace($ExpiresAt)) {
    $AdminArgs += @('-expires', $ExpiresAt)
}

Write-Warning '响应中的 issued_token.token 明文只显示一次，请立即保存到目标设备的安全凭据存储。'
& $AdminExecutable @AdminArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

