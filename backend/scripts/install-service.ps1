# 本脚本以虚拟服务账户安装 Luma，并收紧 ProgramData 与程序目录 ACL。
param(
    [string]$ServiceName = 'LumaServer',
    [string]$ConfigPath = 'C:\ProgramData\Luma\config.yaml',
    [string]$InstallDir = 'C:\Program Files\Luma'
)

$ErrorActionPreference = 'Stop'
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

# Set-RestrictedDirectoryAcl 丢弃继承和既有显式授权，仅保留服务、SYSTEM 与管理员。
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

$ProjectDir = Split-Path -Parent $PSScriptRoot
$SourceBinary = Join-Path $ProjectDir 'dist\luma-server.exe'
if (-not (Test-Path -LiteralPath $SourceBinary -PathType Leaf)) {
    throw "Server binary not found at $SourceBinary. Run scripts\build.ps1 first."
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found at $ConfigPath. Copy and edit configs\config.windows.example.yaml first."
}
$ResolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
$DataDir = Split-Path -Parent $ResolvedConfig
$ServiceIdentity = "NT SERVICE\$ServiceName"

& $SourceBinary -config $ResolvedConfig -check-config -log-format text
if ($LASTEXITCODE -ne 0) { throw 'Configuration or runtime dependency check failed.' }

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
if ($LASTEXITCODE -ne 0) { throw "Failed to install service $ServiceName" }
& sc.exe sidtype $ServiceName unrestricted
if ($LASTEXITCODE -ne 0) { throw "Failed to enable the service SID for $ServiceName" }
$ServiceSid = (New-Object Security.Principal.NTAccount($ServiceIdentity)).Translate([Security.Principal.SecurityIdentifier])
& sc.exe description $ServiceName 'Luma local media server'
if ($LASTEXITCODE -ne 0) { throw "Failed to set description for service $ServiceName" }
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/15000/restart/30000
if ($LASTEXITCODE -ne 0) { throw "Failed to configure recovery for service $ServiceName" }

# 服务仅需修改 ProgramData；SYSTEM 和本机管理员保留完全控制。
Set-RestrictedDirectoryAcl -Path $DataDir -ServiceSid $ServiceSid -ServiceRights Modify
# 程序目录对服务身份只读，防止服务进程替换自身二进制。
Set-RestrictedDirectoryAcl -Path $InstallDir -ServiceSid $ServiceSid -ServiceRights ReadAndExecute

Start-Service -Name $ServiceName
(Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
Write-Host "Installed and started $ServiceName from $ResolvedBinary."
Write-Host 'Configuration and data are preserved by uninstall.'
