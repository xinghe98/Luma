# 本脚本统一构建和部署 Windows 服务端及客户端便携包；它依赖 Go、Flutter、Visual Studio 工具链，并在卸载服务时保留数据。
param(
    [ValidateSet('BuildServer', 'InstallServer', 'UninstallServer', 'PackageClient')]
    [string]$Action = 'InstallServer',
    [string]$Version = 'dev',
    [string]$ServiceName = 'LumaServer',
    [string]$ConfigPath = 'C:\ProgramData\Luma\config.yaml',
    [string]$InstallDir = 'C:\Program Files\Luma',
    [string]$ClientBuildDirectory = 'build\windows\x64\runner\Release',
    [string]$ClientOutputDirectory = 'build\dist',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$RepositoryDir = Split-Path -Parent $ProjectDir
$MobileDir = Join-Path $RepositoryDir 'mobile'

if (-not $IsWindows) {
    throw 'Windows 部署脚本只能在 Windows 上运行。'
}

# 服务注册和 ACL 变更要求管理员权限，普通构建与客户端打包不需要提升权限。
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

# 构建并打包 Windows x64 Flutter 客户端，压缩完成后只清理受控的临时目录。
function New-ClientPackage {
    if (-not $SkipBuild) {
        Push-Location $MobileDir
        try {
            & flutter build windows --release
            if ($LASTEXITCODE -ne 0) { throw "Flutter Windows 构建失败，退出码：$LASTEXITCODE" }
        }
        finally {
            Pop-Location
        }
    }

    $BuildPath = (Resolve-Path -LiteralPath (Join-Path $MobileDir $ClientBuildDirectory)).Path
    if (-not $BuildPath.StartsWith($MobileDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Windows 构建目录不在 mobile 内：$BuildPath"
    }

    $ClientVersion = $Version
    if ($ClientVersion -eq 'dev') {
        $Pubspec = Get-Content -Raw -LiteralPath (Join-Path $MobileDir 'pubspec.yaml')
        $Match = [regex]::Match($Pubspec, '(?m)^version:\s*([^\s+]+)')
        if (-not $Match.Success) { throw '无法从 pubspec.yaml 读取客户端版本号。' }
        $ClientVersion = $Match.Groups[1].Value
    }

    $OutputPath = Join-Path $MobileDir $ClientOutputDirectory
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $ResolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
    if (-not $ResolvedOutput.StartsWith($MobileDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "客户端输出目录不在 mobile 内：$ResolvedOutput"
    }

    $PackageName = "luma-windows-x64-$ClientVersion"
    $StagePath = Join-Path $ResolvedOutput $PackageName
    if (Test-Path -LiteralPath $StagePath) {
        $ResolvedStage = (Resolve-Path -LiteralPath $StagePath).Path
        if ((Split-Path -Parent $ResolvedStage) -ne $ResolvedOutput) {
            throw "拒绝清理非预期目录：$ResolvedStage"
        }
        Remove-Item -LiteralPath $ResolvedStage -Recurse -Force
    }

    New-Item -ItemType Directory -Path $StagePath | Out-Null
    Copy-Item -Path (Join-Path $BuildPath '*') -Destination $StagePath -Recurse
    Copy-Item -LiteralPath (Join-Path $MobileDir 'windows\WINDOWS-README.txt') -Destination $StagePath
    Copy-Item -LiteralPath (Join-Path $MobileDir 'assets\fonts\MiSans-LICENSE.pdf') -Destination $StagePath

    $VswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $VswherePath)) { throw '找不到 vswhere，无法收集 Visual C++ 运行库。' }
    $VsInstall = (& $VswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if ([string]::IsNullOrWhiteSpace($VsInstall)) { throw '找不到包含 C++ 工具链的 Visual Studio。' }

    $RedistRoot = Join-Path $VsInstall 'VC\Redist\MSVC'
    $RedistVersion = Get-ChildItem -LiteralPath $RedistRoot -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $RedistVersion) { throw '找不到 Visual C++ 运行库版本目录。' }
    $CrtDirectory = Get-ChildItem -LiteralPath (Join-Path $RedistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
        Select-Object -First 1
    if ($null -eq $CrtDirectory) { throw '找不到 x64 Visual C++ 运行库。' }
    Copy-Item -Path (Join-Path $CrtDirectory.FullName '*.dll') -Destination $StagePath

    $ArchivePath = Join-Path $ResolvedOutput "$PackageName.zip"
    Compress-Archive -Path (Join-Path $StagePath '*') -DestinationPath $ArchivePath -Force
    $ResolvedStage = (Resolve-Path -LiteralPath $StagePath).Path
    if ((Split-Path -Parent $ResolvedStage) -ne $ResolvedOutput) {
        throw "拒绝清理非预期目录：$ResolvedStage"
    }
    Remove-Item -LiteralPath $ResolvedStage -Recurse -Force
    Write-Output $ArchivePath
}

switch ($Action) {
    'BuildServer' { Build-ServerBinaries }
    'InstallServer' { Install-ServerService }
    'UninstallServer' { Uninstall-ServerService }
    'PackageClient' { New-ClientPackage }
}
