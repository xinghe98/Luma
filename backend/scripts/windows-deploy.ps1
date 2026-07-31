# 本脚本统一构建和部署 Windows 服务端及客户端 NSIS 安装包；它依赖 Go、Flutter、Visual Studio 工具链与 makensis，并在卸载服务时保留数据。
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

# 读取唯一的客户端元数据来源；缺失字段会中止打包，避免包名与客户端信息不一致。
function Get-ClientAppMetadata {
    $MetadataPath = Join-Path $MobileDir 'app_metadata.json'
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
        throw "找不到客户端元数据文件：$MetadataPath"
    }
    $Metadata = Get-Content -Raw -LiteralPath $MetadataPath | ConvertFrom-Json
    foreach ($Field in @('projectName', 'version')) {
        if ([string]::IsNullOrWhiteSpace([string]$Metadata.$Field)) {
            throw "客户端元数据缺少字段：$Field"
        }
    }
    return $Metadata
}

# 校验所有客户端生成文件都对应当前元数据源；打包时不依赖 Dart 包装器以避免环境差异。
function Assert-ClientAppMetadataGenerated {
    $MetadataPath = Join-Path $MobileDir 'app_metadata.json'
    $SourceText = Get-Content -Raw -LiteralPath $MetadataPath
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($SourceText)
    $Fingerprint = [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $Marker = "元数据指纹：$Fingerprint"
    $GeneratedPaths = @(
        (Join-Path $MobileDir 'pubspec.yaml'),
        (Join-Path $MobileDir 'lib\app\app_metadata.g.dart'),
        (Join-Path $MobileDir 'android\app\app_metadata.properties'),
        (Join-Path $MobileDir 'android\app\src\main\res\values\app_metadata.xml'),
        (Join-Path $MobileDir 'windows\app_metadata.cmake'),
        (Join-Path $MobileDir 'windows\runner\app_metadata.h'),
        (Join-Path $MobileDir 'windows\WINDOWS-README.txt')
    )
    foreach ($GeneratedPath in $GeneratedPaths) {
        if (-not (Test-Path -LiteralPath $GeneratedPath -PathType Leaf)) {
            throw "客户端元数据生成文件不存在：$GeneratedPath"
        }
        if (-not (Select-String -LiteralPath $GeneratedPath -SimpleMatch -Quiet -Pattern $Marker)) {
            throw "客户端元数据生成文件已过期：$GeneratedPath。请执行 dart run tool/sync_app_metadata.dart。"
        }
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

# 解析 makensis：优先 PATH，再回退到常见安装目录。
function Get-MakensisPath {
    $FromPath = Get-Command makensis -ErrorAction SilentlyContinue
    if ($null -ne $FromPath) {
        return $FromPath.Source
    }
    foreach ($Candidate in @(
            (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'),
            (Join-Path $env:ProgramFiles 'NSIS\makensis.exe')
        )) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return $Candidate
        }
    }
    throw '找不到 makensis。请安装 NSIS 3（https://nsis.sourceforge.io/）并确保 makensis 在 PATH 中。'
}

# 将语义化版本转为 NSIS VIProductVersion 所需的四段数字版本。
function ConvertTo-NsisVersionQuad {
    param([string]$ClientVersion)

    $Core = $ClientVersion.Split('+')[0]
    $Parts = @($Core.Split('.') | Where-Object { $_ -match '^\d+$' })
    while ($Parts.Count -lt 4) {
        $Parts += '0'
    }
    if ($Parts.Count -gt 4) {
        $Parts = $Parts[0..3]
    }
    return ($Parts -join '.')
}

# 清理输出目录内受控的临时路径，拒绝越界删除。
function Remove-ClientStagingPath {
    param(
        [string]$Path,
        [string]$ResolvedOutput
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $Resolved = (Resolve-Path -LiteralPath $Path).Path
    if ((Split-Path -Parent $Resolved) -ne $ResolvedOutput) {
        throw "拒绝清理非预期目录：$Resolved"
    }
    Remove-Item -LiteralPath $Resolved -Recurse -Force
}

# 构建并打包 Windows x64 Flutter 客户端为 NSIS 安装程序，完成后只清理受控临时目录。
function New-ClientPackage {
    $ClientMetadata = Get-ClientAppMetadata
    Assert-ClientAppMetadataGenerated
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
    $VersionQuad = ConvertTo-NsisVersionQuad -ClientVersion $ClientVersion

    $OutputPath = Join-Path $MobileDir $ClientOutputDirectory
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $ResolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
    if (-not $ResolvedOutput.StartsWith($MobileDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "客户端输出目录不在 mobile 内：$ResolvedOutput"
    }

    $PackageName = "$($ClientMetadata.projectName)-windows-x64-$ClientVersion"
    $InstallerFileName = "$PackageName-setup.exe"
    $InstallerPath = Join-Path $ResolvedOutput $InstallerFileName
    $StagePath = Join-Path $ResolvedOutput $PackageName
    $NsisWorkPath = Join-Path $ResolvedOutput 'nsis-work'
    Remove-ClientStagingPath -Path $StagePath -ResolvedOutput $ResolvedOutput
    Remove-ClientStagingPath -Path $NsisWorkPath -ResolvedOutput $ResolvedOutput

    New-Item -ItemType Directory -Path $StagePath | Out-Null
    Copy-Item -Path (Join-Path $BuildPath '*') -Destination $StagePath -Recurse
    Copy-Item -LiteralPath (Join-Path $MobileDir 'windows\WINDOWS-README.txt') -Destination $StagePath
    Copy-Item -LiteralPath (Join-Path $MobileDir 'assets\fonts\MiSans-LICENSE.pdf') -Destination $StagePath

    $AppIcon = Join-Path $MobileDir 'windows\runner\resources\app_icon.ico'
    if (-not (Test-Path -LiteralPath $AppIcon -PathType Leaf)) {
        throw "找不到应用图标：$AppIcon"
    }
    # 安装目录内使用稳定文件名 luma.ico，供快捷方式与“应用和功能”引用。
    Copy-Item -LiteralPath $AppIcon -Destination (Join-Path $StagePath 'luma.ico')

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

    $ExeName = "$($ClientMetadata.windowsExecutableName).exe"
    $ExePath = Join-Path $StagePath $ExeName
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        throw "构建产物缺少可执行文件：$ExePath"
    }

    $NsiSource = Join-Path $MobileDir 'windows\installer\luma.nsi'
    if (-not (Test-Path -LiteralPath $NsiSource -PathType Leaf)) {
        throw "找不到 NSIS 脚本：$NsiSource"
    }

    New-Item -ItemType Directory -Path $NsisWorkPath | Out-Null
    $NsiWorkFile = Join-Path $NsisWorkPath 'luma.nsi'
    $DefinesPath = Join-Path $NsisWorkPath 'installer-defines.nsh'
    $ProductName = [string]$ClientMetadata.productName
    $CompanyName = [string]$ClientMetadata.companyName
    $Copyright = [string]$ClientMetadata.copyright
    $InstallDirName = $ProductName
    $ProductRegKey = [string]$ClientMetadata.projectName

    # NSIS Unicode 脚本需要带 BOM 的 UTF-8；路径使用正斜杠。
    function Format-NsisPath([string]$PathValue) {
        return ($PathValue -replace '\\', '/')
    }
    function Format-NsisLiteral([string]$Value) {
        return $Value.Replace('\', '\\').Replace('"', '$\"')
    }
    function Write-NsisUtf8File {
        param(
            [string]$Path,
            [string]$Content
        )
        $Utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Path, $Content, $Utf8Bom)
    }

    Write-NsisUtf8File -Path $NsiWorkFile -Content ([System.IO.File]::ReadAllText($NsiSource))
    $Defines = @(
        "!define PRODUCT_NAME `"$(Format-NsisLiteral $ProductName)`""
        "!define PRODUCT_VERSION `"$(Format-NsisLiteral $ClientVersion)`""
        "!define PRODUCT_VERSION_QUAD `"$VersionQuad`""
        "!define COMPANY_NAME `"$(Format-NsisLiteral $CompanyName)`""
        "!define COPYRIGHT `"$(Format-NsisLiteral $Copyright)`""
        "!define INSTALL_DIR_NAME `"$(Format-NsisLiteral $InstallDirName)`""
        "!define PRODUCT_REG_KEY `"$(Format-NsisLiteral $ProductRegKey)`""
        "!define EXE_NAME `"$(Format-NsisLiteral $ExeName)`""
        "!define INSTALLER_FILE_NAME `"$(Format-NsisLiteral $InstallerFileName)`""
        "!define STAGE_DIR `"$(Format-NsisPath $StagePath)`""
        "!define OUT_FILE `"$(Format-NsisPath $InstallerPath)`""
        "!define APP_ICON `"$(Format-NsisPath $AppIcon)`""
    ) -join "`r`n"
    Write-NsisUtf8File -Path $DefinesPath -Content ($Defines + "`r`n")

    $Makensis = Get-MakensisPath
    & $Makensis /V2 $NsiWorkFile
    if ($LASTEXITCODE -ne 0) { throw "NSIS 编译失败，退出码：$LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
        throw "NSIS 未生成安装包：$InstallerPath"
    }

    Remove-ClientStagingPath -Path $StagePath -ResolvedOutput $ResolvedOutput
    Remove-ClientStagingPath -Path $NsisWorkPath -ResolvedOutput $ResolvedOutput
    Write-Output $InstallerPath
}

switch ($Action) {
    'BuildServer' { Build-ServerBinaries }
    'InstallServer' { Install-ServerService }
    'UninstallServer' { Uninstall-ServerService }
    'PackageClient' { New-ClientPackage }
}
