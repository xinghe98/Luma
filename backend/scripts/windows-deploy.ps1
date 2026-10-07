# 本脚本构建和部署 Windows 服务端；构建依赖 Go，并在卸载服务时保留数据。
param(
    [ValidateSet('BuildServer', 'InstallServer', 'UninstallServer')]
    [string]$Action = 'InstallServer',
    [string]$Version = 'dev',
    [string]$ServiceName = 'LumaServer',
    [string]$ConfigPath = 'C:\ProgramData\Luma\config.yaml',
    [string]$InstallDir = 'C:\Program Files\Luma',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot

if (-not $IsWindows) {
    throw 'Windows 部署脚本只能在 Windows 上运行。'
}

# 服务注册和 ACL 变更要求管理员权限，普通构建不需要提升权限。
function Assert-Administrator {
    $Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '请从管理员 PowerShell 会话运行此操作。'
    }
}

# 构建带版本信息的 Windows 服务端与管理工具，失败时原样返回 Go 的退出码。
function Build-ServerBinaries {
    $DistDir = Join-Path $ProjectDir 'dist'
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    Push-Location $ProjectDir
    $PreviousCGOEnabled = $env:CGO_ENABLED
    try {
        $env:CGO_ENABLED = '0'
        & go build -trimpath -ldflags "-s -w -X main.version=$Version" -o (Join-Path $DistDir 'luma-server.exe') ./cmd/server
        if ($LASTEXITCODE -ne 0) { throw "luma-server 构建失败，退出码：$LASTEXITCODE" }
        & go build -trimpath -ldflags '-s -w' -o (Join-Path $DistDir 'luma-admin.exe') ./cmd/admin
        if ($LASTEXITCODE -ne 0) { throw "luma-admin 构建失败，退出码：$LASTEXITCODE" }
    }
    finally {
        $env:CGO_ENABLED = $PreviousCGOEnabled
        Pop-Location
    }
}

# 丢弃目录继承权限，仅保留服务身份、SYSTEM 与管理员所需权限。
function Set-RestrictedDirectoryAcl {
    param(
        [string]$Path,
        [System.Security.Principal.SecurityIdentifier]$ServiceSid,
        [System.Security.AccessControl.FileSystemRights]$ServiceRights
    )

    $SystemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $AdministratorsSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $Inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $Propagation = [Security.AccessControl.PropagationFlags]::None
    $Allow = [Security.AccessControl.AccessControlType]::Allow
    $Acl = New-Object Security.AccessControl.DirectorySecurity
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.SetOwner($AdministratorsSid)
    $Acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($ServiceSid, $ServiceRights, $Inheritance, $Propagation, $Allow)))
    $Acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($SystemSid, 'FullControl', $Inheritance, $Propagation, $Allow)))
    $Acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($AdministratorsSid, 'FullControl', $Inheritance, $Propagation, $Allow)))
    Set-Acl -LiteralPath $Path -AclObject $Acl
}

# 校验配置并创建或更新 Windows 服务；更新时先停止旧服务再替换二进制。
function Install-ServerService {
    Assert-Administrator
    if (-not $SkipBuild) {
        Build-ServerBinaries
    }

    $SourceBinary = Join-Path $ProjectDir 'dist\luma-server.exe'
    if (-not (Test-Path -LiteralPath $SourceBinary -PathType Leaf)) {
        throw "找不到服务端二进制：$SourceBinary"
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "找不到配置：$ConfigPath。请先复制并编辑 configs\config.windows.example.yaml。"
    }

    $ResolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $DataDir = Split-Path -Parent $ResolvedConfig
    $ServiceIdentity = "NT SERVICE\$ServiceName"

    & $SourceBinary -config $ResolvedConfig -check-config -log-format text
    if ($LASTEXITCODE -ne 0) { throw '配置或运行依赖检查失败。' }

    $ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -ne $ExistingService -and $ExistingService.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
        $ExistingService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $InstalledBinary = Join-Path $InstallDir 'luma-server.exe'
    Copy-Item -LiteralPath $SourceBinary -Destination $InstalledBinary -Force
    $ResolvedBinary = (Resolve-Path -LiteralPath $InstalledBinary).Path
    $CommandLine = ('"{0}" -config "{1}" -service-name "{2}"' -f $ResolvedBinary, $ResolvedConfig, $ServiceName)

    if ($null -ne $ExistingService) {
        & sc.exe config $ServiceName binPath= $CommandLine start= auto obj= $ServiceIdentity password= ''
    }
    else {
        & sc.exe create $ServiceName binPath= $CommandLine start= auto obj= $ServiceIdentity password= '' DisplayName= 'Luma Media Server'
    }
    if ($LASTEXITCODE -ne 0) { throw "无法安装服务 $ServiceName" }

    & sc.exe sidtype $ServiceName unrestricted
    if ($LASTEXITCODE -ne 0) { throw "无法启用服务 SID：$ServiceName" }
    $ServiceSid = (New-Object Security.Principal.NTAccount($ServiceIdentity)).Translate([Security.Principal.SecurityIdentifier])
    & sc.exe description $ServiceName 'Luma local media server'
    if ($LASTEXITCODE -ne 0) { throw "无法设置服务说明：$ServiceName" }
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/15000/restart/30000
    if ($LASTEXITCODE -ne 0) { throw "无法设置服务恢复策略：$ServiceName" }

    Set-RestrictedDirectoryAcl -Path $DataDir -ServiceSid $ServiceSid -ServiceRights Modify
    Set-RestrictedDirectoryAcl -Path $InstallDir -ServiceSid $ServiceSid -ServiceRights ReadAndExecute

    Start-Service -Name $ServiceName
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Host "已从 $ResolvedBinary 安装并启动 $ServiceName。"
}

# 删除 Windows 服务注册但保留安装目录、配置、数据库和媒体文件。
function Uninstall-ServerService {
    Assert-Administrator
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $Service) {
        Write-Host "服务 $ServiceName 未安装。"
        return
    }
    if ($Service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
        $Service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    & sc.exe delete $ServiceName
    if ($LASTEXITCODE -ne 0) { throw "无法删除服务 $ServiceName" }
    Write-Host "已删除 $ServiceName，配置、数据库和媒体数据均已保留。"
}

switch ($Action) {
    'BuildServer' { Build-ServerBinaries }
    'InstallServer' { Install-ServerService }
    'UninstallServer' { Uninstall-ServerService }
}
