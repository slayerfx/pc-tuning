<#
.SYNOPSIS
    pc-tuning: Windows tuning for a desktop gaming and creation PC.
    Every setting can be checked, re-applied and undone.

.DESCRIPTION
    Check       Lists every setting and the real state of the hardware.
                Changes nothing, no administrator rights needed.
    Apply       Creates a restore point, saves the current state in backups\,
                then fixes only the settings that drifted.
    Undo        Restores the state saved by the last Apply.
    SecureBoot  Re-deploys Microsoft's 2023 Secure Boot certificates, which a
                BIOS update wipes out.

    Windows Update, driver installs and some apps quietly revert settings:
    run Check after big updates, and Apply when something drifted.

    Settings come from config.json next to this script (copy config.example.json).
    Without it, the defaults below are used: the opinionated options are off.
#>

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply', 'Undo', 'SecureBoot')]
    [string]$Mode = 'Check',

    # JSON configuration file (default: config.json next to the script)
    [string]$Config,

    # fr or en (default: Windows display language)
    [string]$Language,

    # Walk through Apply, Undo or SecureBoot without changing anything (no admin rights needed)
    [switch]$DryRun,

    # State file to write (Apply) or read (Undo) instead of the latest one in backups\
    [string]$StateFile,

    # Do not wait for Enter at the end
    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$Root      = $PSScriptRoot
$BackupDir = Join-Path $Root 'backups'
$LogDir    = Join-Path $Root 'logs'
$Stamp     = Get-Date -Format 'yyyy-MM-dd_HHmm'
$script:RebootNeeded = $false
$script:ManualCount  = 0

if ($Language -notin 'fr', 'en') {
    $Language = 'en'
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { $Language = 'fr' }
}
function T([string]$Fr, [string]$En) { if ($Language -eq 'fr') { $Fr } else { $En } }

# The elevated copy starts in System32: relative paths must be resolved first
if ($Config)    { $Config    = [IO.Path]::GetFullPath($Config) }
if ($StateFile) { $StateFile = [IO.Path]::GetFullPath($StateFile) }

# ===================================================================== OUTPUT

$TagOk        = '[OK]'
$TagTodo      = T '[À FAIRE]' '[TO DO]'
$TagFixed     = T '[CORRIGÉ]' '[FIXED]'
$TagReview    = T '[À REVOIR]' '[REVIEW]'
$TagFailed    = T '[ÉCHEC]' '[FAILED]'
$TagRestored  = T '[RESTAURÉ]' '[RESTORED]'
$TagToRestore = T '[À REMETTRE]' '[TO RESTORE]'

function Write-Title($Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Row($Tag, $Color, $Text, $Detail) {
    $line = '  {0,-12} {1}' -f $Tag, $Text
    if ($Detail) { $line += "  ($Detail)" }
    Write-Host $line -ForegroundColor $Color
}
function Write-Info($Text) { Write-Row '[i]' Gray $Text }
function Write-Warn($Text) { Write-Row '[!]' Yellow $Text }
function New-Result($Ok, $Detail) { [pscustomobject]@{ Ok = $Ok; Detail = $Detail } }
function Wait-End {
    if (-not $NoPause) { Write-Host ''; Read-Host (T '  Appuie sur Entrée pour fermer' '  Press Enter to close') | Out-Null }
}

# ================================================================ ELEVATION

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$IsAdmin = Test-Admin

if ($Mode -ne 'Check' -and -not $DryRun -and -not $IsAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Language', $Language)
    if ($Config)    { $argList += @('-Config', "`"$Config`"") }
    if ($StateFile) { $argList += @('-StateFile', "`"$StateFile`"") }
    if ($NoPause)   { $argList += '-NoPause' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Warn (T "Droits administrateur refusés : rien n'a été modifié." 'Administrator rights denied: nothing was changed.')
        Wait-End
    }
    exit
}

# ============================================================ CONFIGURATION
# Opinionated options (security trade-offs, personal preferences) are off by default.

$Cfg = @{
    disableMemoryIntegrity   = $false
    removeNahimic            = $false
    disableTelemetry         = $true
    removeApps               = @(
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.MicrosoftSolitaireCollection', 'Clipchamp.Clipchamp',
        'Microsoft.GetHelp', 'Microsoft.WindowsFeedbackHub', 'Microsoft.Todos', 'Microsoft.Windows.DevHome',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.MountainDwellings', 'Microsoft.StartExperiencesApp',
        'MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime', 'MSTeams'
    )
    extraApps                = @()
    manualServices           = @('DusmSvc', 'InventorySvc')
    disableGameDvr           = $true
    hardwareGpuScheduling    = $true
    desktopPowerPlan         = $true
    disableHibernation       = $false
    snappierInterface        = $true
    disableTransparency      = $false
    disableMouseAcceleration = $true
    disableChromeAutostart   = $false
    wallpaperEnginePause     = $true
    network  = @{ adapter = ''; dnsServers = @(); disablePowerSaving = $true; disableThrottling = $true }
    defender = @{ excludeSteamLibraries = $false; extraExclusions = @() }
    checks   = @{ latestBiosVersion = ''; minLinkSpeedMbps = 1000 }
}

function Merge-Settings([hashtable]$Base, $Override, [string]$Prefix) {
    foreach ($p in $Override.PSObject.Properties) {
        if (-not $Base.ContainsKey($p.Name)) {
            Write-Warn ((T 'Clé inconnue dans la configuration, ignorée : {0}' 'Unknown configuration key, ignored: {0}') -f "$Prefix$($p.Name)")
            continue
        }
        if ($Base[$p.Name] -is [hashtable] -and $p.Value -is [System.Management.Automation.PSCustomObject]) {
            Merge-Settings $Base[$p.Name] $p.Value "$Prefix$($p.Name)."
        } else {
            $Base[$p.Name] = $p.Value
        }
    }
}

$ConfigPath = $Config
if (-not $ConfigPath) { $ConfigPath = Join-Path $Root 'config.json' }
$ConfigName = T 'réglages par défaut' 'defaults'
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Merge-Settings $Cfg $json ''
        $ConfigName = Split-Path -Leaf $ConfigPath
    } catch {
        Write-Warn ((T 'Configuration illisible ({0}) : {1}' 'Unreadable configuration ({0}): {1}') -f $ConfigPath, $_.Exception.Message)
        Wait-End
        exit 1
    }
} elseif ($Config) {
    Write-Warn ((T 'Configuration introuvable : {0}' 'Configuration not found: {0}') -f $Config)
    Wait-End
    exit 1
}

# =================================================================== HELPERS

# ------------------------------------------------------------------ Registry

function Get-RegValue([string]$Path, [string]$Name) {
    $k = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $k) { return $null }
    $d = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    if ($null -eq $d) { return $null }
    [pscustomobject]@{ Data = $d; Kind = $k.GetValueKind($Name).ToString() }
}

function Set-RegValue([string]$Path, [string]$Name, $Data, [string]$Kind) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Data -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
}

function Remove-RegValue([string]$Path, [string]$Name) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

# The JSON state file gives back generic arrays: restore the registry type.
# The leading comma stops PowerShell from unrolling the array on output.
function ConvertTo-RegData($Data, [string]$Kind) {
    switch ($Kind) {
        'Binary'      { return , ([byte[]]@($Data)) }
        'MultiString' { return , ([string[]]@($Data)) }
        'DWord'       { return [int]$Data }
        'QWord'       { return [long]$Data }
        default       { return [string]$Data }
    }
}

# ------------------------------------------------------------------ Services

$StartTypes     = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
$StartTypeNames = @{
    Automatic = (T 'automatique' 'automatic'); Manual = (T 'manuel' 'manual'); Disabled = (T 'désactivé' 'disabled')
}

function Get-ServiceStartType([string]$Name) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    if ($StartTypes.ContainsKey($s.StartMode)) { $StartTypes[$s.StartMode] } else { $s.StartMode }
}

# --------------------------------------------------------------------- Power

$UltimateGuid  = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$UltimateNames = 'Ultimate Performance|Performances optimales'

function Get-PowerPlans {
    foreach ($l in @(& powercfg /list 2>$null)) {
        if ($l -match '([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\s+\((.+)\)\s*(\*)?\s*$') {
            [pscustomobject]@{ Guid = $Matches[1]; Name = $Matches[2]; Active = ($Matches[3] -eq '*') }
        }
    }
}
function Get-ActivePowerPlan { @(Get-PowerPlans | Where-Object Active)[0] }

# powercfg answers in the Windows language: only its hexadecimal values are read.
# The last two of the output are the plugged-in index, then the battery index.
function Get-AcIndex([string]$SubGroup, [string]$Setting) {
    $out = (@(& powercfg /query SCHEME_CURRENT $SubGroup $Setting 2>$null)) -join "`n"
    $m = [regex]::Matches($out, ':\s*0x([0-9a-fA-F]+)')
    if ($m.Count -lt 2) { return $null }
    [Convert]::ToInt32($m[$m.Count - 2].Groups[1].Value, 16)
}

# --------------------------------------------------------------------- Steam

function Get-SteamLibraries {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $steam = $steam -replace '/', '\'
    $libs = @($steam)
    foreach ($vdf in (Join-Path $steam 'config\libraryfolders.vdf'), (Join-Path $steam 'steamapps\libraryfolders.vdf')) {
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        foreach ($m in @(Select-String -LiteralPath $vdf -Pattern '"path"\s+"(.+?)"')) {
            $libs += ($m.Matches[0].Groups[1].Value -replace '\\\\', '\')
        }
    }
    # Sort-Object -Unique ignores case: Steam writes the same path in different cases
    @($libs | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}

# ------------------------------------------------------------------- Network

function Get-TunedAdapter {
    if ($Cfg.network.adapter) { return Get-NetAdapter -Name $Cfg.network.adapter -ErrorAction SilentlyContinue }
    # Default: the first connected wired adapter
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' -and $_.MediaType -eq '802.3' } | Sort-Object ifIndex)[0]
}
$Adapter     = Get-TunedAdapter
$AdapterName = $null
if ($Adapter) { $AdapterName = $Adapter.Name }

# ================================================================== CATALOG
# Each setting knows how to check itself (Test), apply itself, record its
# previous state (Read) and, when possible, go back (Restore).
# Ids are written to the state files in backups\: keep them stable.

$Catalog = New-Object System.Collections.Generic.List[object]

function Add-Registry {
    param($Group, $Name, $Path, $Value, $Data, $Kind = 'DWord', [switch]$Reboot)
    $Catalog.Add([pscustomobject]@{
        Id = "registry|$Path|$Value"; Type = 'Registry'; Group = $Group; Name = $Name
        Path = $Path; Value = $Value; Data = $Data; Kind = $Kind; Reboot = [bool]$Reboot
    })
}
function Add-Service {
    param($Group, $Service, $StartType, $Name)
    $Catalog.Add([pscustomobject]@{
        Id = "service|$Service"; Type = 'Service'; Group = $Group; Name = $Name
        Service = $Service; StartType = $StartType; Reboot = $false
    })
}
function Add-PowerSetting {
    param($Group, $Name, $SubGroup, $Setting, $Index)
    $Catalog.Add([pscustomobject]@{
        Id = "power|$SubGroup|$Setting"; Type = 'Power'; Group = $Group; Name = $Name
        SubGroup = $SubGroup; Setting = $Setting; Index = $Index; Reboot = $false
    })
}
function Add-Custom([hashtable]$Def) {
    $o = [ordered]@{ Type = 'Custom'; Reboot = $false; Read = $null; Restore = $null; NotReversible = $null }
    foreach ($k in $Def.Keys) { $o[$k] = $Def[$k] }
    $Catalog.Add([pscustomobject]$o)
}

# ----------------------------------------------------- 1. Memory integrity
# Before 10th gen, Intel CPUs lack MBEC: Windows emulates memory integrity
# (HVCI) in software, which costs noticeably more in games. The hypervisor
# itself stays loaded, so Docker Desktop and WSL keep working. The Policies
# value locks the choice: Windows Update can otherwise turn it back on.

if ($Cfg.disableMemoryIntegrity) {
    $G = T 'Isolation du noyau' 'Core isolation'
    Add-Registry $G (T 'Intégrité de la mémoire (HVCI) coupée' 'Memory integrity (HVCI) off') 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 -Reboot
    Add-Registry $G (T 'Sécurité basée sur la virtualisation (VBS) coupée' 'Virtualization-based security (VBS) off') 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 -Reboot
    Add-Registry $G (T 'Verrou : Windows ne peut plus les réactiver seul' 'Lock: Windows cannot turn them back on') 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 -Reboot
    Add-Registry $G (T 'Credential Guard coupé' 'Credential Guard off') 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LsaCfgFlags' 0 -Reboot
}

# ------------------------------------------------------------- 2. Nahimic
# Audio layer shipped with MSI boards, reinstalled by Windows Update: its
# driver packages are removed, then its hardware IDs, and only those, are
# denied installation.

$NahimicIds   = @('SWC\VEN_AVOL&AID_0300', 'ROOT\Nahimic_Mirroring')
$DenyKey      = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$DenyListKey  = "$DenyKey\DenyDeviceIDs"

function Get-NahimicDevices {
    @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Nahimic|A-Volute' })
}
function Get-WantedDenyIds {
    $ids = @($NahimicIds)
    foreach ($d in Get-NahimicDevices) {
        $hw = @((Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_HardwareIds -ErrorAction SilentlyContinue).Data)
        if ($hw.Count -and $hw[0]) { $ids += $hw[0] }
    }
    @($ids | Sort-Object -Unique)
}
function Get-DeniedIds {
    $k = Get-Item -LiteralPath $DenyListKey -ErrorAction SilentlyContinue
    if ($k) { @($k.GetValueNames() | ForEach-Object { $k.GetValue($_) }) }
}
function Get-MissingDenyIds {
    $denied = @(Get-DeniedIds)
    @(Get-WantedDenyIds | Where-Object { $denied -notcontains $_ })
}
# Only packages published by A-Volute or Nahimic: never the audio driver itself.
# Extension packages go last, after the components they declare.
function Get-NahimicInfs {
    $infs = @(Get-ChildItem "$env:windir\INF\oem*.inf" -ErrorAction SilentlyContinue | Where-Object {
        Select-String -LiteralPath $_.FullName -Pattern '^\s*Provider(Name)?\s*=\s*"?(A-Volute|Nahimic)' -Quiet
    })
    @($infs | Sort-Object { [bool](Select-String -LiteralPath $_.FullName -Pattern '^\s*Class\s*=\s*Extension' -Quiet) }, Name)
}

if ($Cfg.removeNahimic) {
    $G = 'Nahimic'
    Add-Service $G 'NahimicService' 'Disabled' (T 'Service Nahimic désactivé' 'Nahimic service disabled')

    Add-Custom @{
        Id = 'nahimic-block'; Group = $G; Name = (T 'Réinstallation par Windows Update bloquée' 'Reinstall by Windows Update blocked')
        Test = {
            $flag = Get-RegValue $DenyKey 'DenyDeviceIDs'
            if ($flag -and $flag.Data -eq 1 -and @(Get-MissingDenyIds).Count -eq 0) { return New-Result $true $null }
            New-Result $false (T 'aucun blocage en place' 'not blocked')
        }
        Read = {
            $flag = Get-RegValue $DenyKey 'DenyDeviceIDs'
            @{ Flag = $(if ($flag) { $flag.Data } else { $null }); Added = @(Get-MissingDenyIds) }
        }
        Apply = {
            $missing = @(Get-MissingDenyIds)
            Set-RegValue $DenyKey 'DenyDeviceIDs' 1 'DWord'
            if (-not (Test-Path -LiteralPath $DenyListKey)) { New-Item -Path $DenyListKey -Force | Out-Null }
            $numbers = @((Get-Item -LiteralPath $DenyListKey).GetValueNames() | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
            $n = 0
            if ($numbers.Count) { $n = ($numbers | Measure-Object -Maximum).Maximum }
            foreach ($id in $missing) { $n++; Set-RegValue $DenyListKey "$n" $id 'String' }
        }
        Restore = {
            param($Before)
            $k = Get-Item -LiteralPath $DenyListKey -ErrorAction SilentlyContinue
            if ($k) {
                foreach ($name in $k.GetValueNames()) {
                    if (@($Before.Added) -contains $k.GetValue($name)) { Remove-RegValue $DenyListKey $name }
                }
                if (@(Get-DeniedIds).Count -eq 0) { Remove-Item -LiteralPath $DenyListKey -Force -ErrorAction SilentlyContinue }
            }
            if ($null -eq $Before.Flag) { Remove-RegValue $DenyKey 'DenyDeviceIDs' }
            else { Set-RegValue $DenyKey 'DenyDeviceIDs' ([int]$Before.Flag) 'DWord' }
        }
    }

    Add-Custom @{
        Id = 'nahimic-drivers'; Group = $G; Name = (T 'Pilotes Nahimic / A-Volute retirés' 'Nahimic / A-Volute drivers removed'); Reboot = $true
        NotReversible = (T 'réinstalle le pack audio de ta carte mère si besoin' "reinstall your motherboard's audio package if needed")
        Test = {
            $dev = @(Get-NahimicDevices); $inf = @(Get-NahimicInfs)
            if ($dev.Count -eq 0 -and $inf.Count -eq 0) { return New-Result $true $null }
            New-Result $false ((T '{0} périphérique(s), paquets : {1}' '{0} device(s), packages: {1}') -f $dev.Count, ((@($inf) | ForEach-Object Name) -join ', '))
        }
        Apply = {
            foreach ($inf in @(Get-NahimicInfs)) {
                & pnputil /delete-driver $inf.Name /uninstall /force 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Info ((T 'Paquet supprimé : {0}' 'Package removed: {0}') -f $inf.Name) }
                elseif ($LASTEXITCODE -eq 3010) { Write-Info ((T 'Paquet supprimé : {0} (redémarrage requis)' 'Package removed: {0} (restart required)') -f $inf.Name); $script:RebootNeeded = $true }
                else { Write-Warn ((T '{0} : encore verrouillé (code {1}), redémarre puis relance Apply' '{0}: still locked (code {1}), restart then run Apply again') -f $inf.Name, $LASTEXITCODE) }
            }
            foreach ($d in @(Get-NahimicDevices)) {
                & pnputil /remove-device "$($d.InstanceId)" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) { Write-Info ((T 'Périphérique retiré : {0}' 'Device removed: {0}') -f $d.FriendlyName) }
                else { Write-Warn ((T '{0} : échec du retrait (code {1})' '{0}: removal failed (code {1})') -f $d.FriendlyName, $LASTEXITCODE) }
            }
        }
    }
}

# ------------------------------------------------ 3. Telemetry and services
# SysMain stays on on purpose: on an SSD with enough RAM, it helps.

$TelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Maps\MapsToastTask',
    '\Microsoft\Windows\Maps\MapsUpdateTask',
    '\Microsoft\Windows\Device Information\Device',
    '\Microsoft\Windows\Device Information\Device User',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\XblGameSave\XblGameSaveTask'
)
# Whole folders: SoftLanding (Windows promotions, one subfolder per account) and
# GoogleUserPEH (Chrome telemetry). PcaPatchDbTask is not listed: Windows turns
# it back on at every boot.
$CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$TelemetryTaskFolders = @("\SoftLanding\$CurrentSid\", '\GoogleUserPEH\')

function Get-ActiveTelemetryTasks {
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        if ($t.State -eq 'Disabled') { continue }
        $inFolder = $false
        foreach ($f in $TelemetryTaskFolders) { if ($t.TaskPath -like "$f*") { $inFolder = $true } }
        if ($inFolder -or ($TelemetryTasks -contains ($t.TaskPath + $t.TaskName))) { $t }
    }
}

if ($Cfg.disableTelemetry) {
    $G = T 'Télémétrie' 'Telemetry'
    Add-Service $G 'DiagTrack'  'Disabled' (T 'Service de télémétrie (DiagTrack) désactivé' 'Telemetry service (DiagTrack) disabled')
    Add-Service $G 'wuqisvc'    'Disabled' (T "Service d'informations d'utilisation et de qualité désactivé" 'Usage and quality insights service disabled')
    Add-Service $G 'MapsBroker' 'Disabled' (T 'Service des cartes hors connexion désactivé' 'Offline maps service disabled')

    Add-Custom @{
        Id = 'telemetry-tasks'; Group = $G
        Name = ((T 'Tâches de télémétrie et de promotion coupées ({0} + 2 dossiers)' 'Telemetry and promotion tasks off ({0} + 2 folders)') -f $TelemetryTasks.Count)
        Test = {
            $active = @(Get-ActiveTelemetryTasks)
            if ($active.Count -eq 0) { return New-Result $true $null }
            New-Result $false ((T 'réactivées : {0}' 'turned back on: {0}') -f ((@($active) | ForEach-Object TaskName) -join ', '))
        }
        Read = { @(Get-ActiveTelemetryTasks | ForEach-Object { $_.TaskPath + '|' + $_.TaskName }) }
        Apply = {
            foreach ($t in @(Get-ActiveTelemetryTasks)) {
                try { Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null }
                catch { Write-Warn "$($t.TaskName) : $($_.Exception.Message)" }
            }
        }
        Restore = {
            param($Before)
            foreach ($b in @($Before)) {
                if (-not $b) { continue }
                $path, $name = $b -split '\|', 2
                Enable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }

    # On Windows Pro, AllowTelemetry = 0 behaves like the "Required" level:
    # the lowest Microsoft allows on that edition.
    $Dc  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    $Cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    Add-Registry $G (T 'Télémétrie au minimum autorisé' 'Telemetry at the lowest allowed level') $Dc 'AllowTelemetry' 0
    Add-Registry $G (T 'Nom du PC exclu de la télémétrie' 'PC name left out of telemetry') $Dc 'AllowDeviceNameInTelemetry' 0
    Add-Registry $G (T "Demandes d'avis coupées" 'Feedback requests off') $Dc 'DoNotShowFeedbackNotifications' 1
    Add-Registry $G (T 'Suggestions web du menu Démarrer coupées' 'Web suggestions in Start off') 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Add-Registry $G (T 'Recherche Bing coupée' 'Bing search off') 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Add-Registry $G (T "Installations silencieuses d'applis promues coupées" 'Silent installs of promoted apps off') $Cdm 'SilentInstalledAppsEnabled' 0
    Add-Registry $G (T 'Suggestions dans Démarrer coupées' 'Start suggestions off') $Cdm 'SystemPaneSuggestionsEnabled' 0
    Add-Registry $G (T 'Contenus sponsorisés coupés' 'Sponsored content off') $Cdm 'SubscribedContentEnabled' 0
    Add-Registry $G (T 'Identifiant publicitaire coupé' 'Advertising ID off') 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
}

if (@($Cfg.manualServices).Count) {
    $G = 'Services'
    foreach ($s in @($Cfg.manualServices)) {
        Add-Service $G $s 'Manual' ((T 'Service {0} en démarrage manuel' 'Service {0} set to manual') -f $s)
    }
}

# ------------------------------------------------------------ 4. Apps

$AppsToRemove = @(@($Cfg.removeApps) + @($Cfg.extraApps) | Where-Object { $_ } | Sort-Object -Unique)

function Get-PresentApps {
    @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $AppsToRemove -contains $_.Name })
}

if ($AppsToRemove.Count) {
    Add-Custom @{
        Id = 'apps'; Group = (T 'Applications' 'Apps'); Name = ((T 'Applis préinstallées retirées ({0})' 'Preinstalled apps removed ({0})') -f $AppsToRemove.Count)
        NotReversible = (T 'elles se réinstallent depuis le Microsoft Store' 'reinstall them from the Microsoft Store')
        Test = {
            $present = @(Get-PresentApps)
            if ($present.Count -eq 0) { return New-Result $true $null }
            New-Result $false ((T 'présentes : {0}' 'present: {0}') -f ((@($present) | ForEach-Object Name) -join ', '))
        }
        Apply = {
            foreach ($p in @(Get-PresentApps)) {
                try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Write-Info ((T 'Retirée : {0}' 'Removed: {0}') -f $p.Name) }
                catch { Write-Warn "$($p.Name) : $($_.Exception.Message)" }
            }
            # Keeps them away from new user profiles. Refused on some machines, harmless here.
            try {
                foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $AppsToRemove -contains $_.DisplayName })) {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                }
            } catch { }
        }
    }
}

# ------------------------------------------------- 5. Gaming and performance

$G = T 'Jeu et performances' 'Gaming and performance'

if ($Cfg.disableGameDvr) {
    Add-Registry $G (T 'Enregistrement Game DVR bloqué' 'Game DVR recording blocked') 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Add-Registry $G (T 'Game DVR coupé (utilisateur)' 'Game DVR off (user)') 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
}
if ($Cfg.hardwareGpuScheduling) {
    Add-Registry $G (T 'Planification GPU accélérée (HAGS)' 'Hardware-accelerated GPU scheduling (HAGS)') 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 -Reboot
}

if ($Cfg.desktopPowerPlan) {
    # The plan goes first: the power settings below apply to the active plan
    Add-Custom @{
        Id = 'power-plan'; Group = $G; Name = (T 'Plan « Performances optimales » actif' 'Ultimate Performance power plan active')
        Test = {
            $active = Get-ActivePowerPlan
            if ($active -and $active.Name -match $UltimateNames) { return New-Result $true $null }
            New-Result $false ((T 'plan actif : {0}' 'active plan: {0}') -f $(if ($active) { $active.Name } else { '?' }))
        }
        Read = { (Get-ActivePowerPlan).Guid }
        Apply = {
            $plan = @(Get-PowerPlans | Where-Object { $_.Name -match $UltimateNames })[0]
            if ($plan) { $guid = $plan.Guid }
            else {
                $out = (@(& powercfg -duplicatescheme $UltimateGuid 2>&1)) -join ' '
                if ($out -match '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') { $guid = $Matches[0] }
                else { throw ((T "powercfg n'a pas pu créer le plan : {0}" 'powercfg could not create the plan: {0}') -f $out) }
            }
            & powercfg /setactive $guid | Out-Null
        }
        Restore = { param($Before) if ($Before) { & powercfg /setactive $Before | Out-Null } }
    }
    Add-PowerSetting $G (T "Économie d'énergie PCI Express coupée" 'PCI Express power saving off') 'SUB_PCIEXPRESS' 'ASPM' 0
    Add-PowerSetting $G (T 'Suspension sélective USB coupée' 'USB selective suspend off') '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0
}

$NtfsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
Add-Custom @{
    Id = 'ntfs-last-access'; Group = $G; Name = (T 'NTFS : horodatage du dernier accès coupé' 'NTFS last-access timestamps off')
    Test = {
        $v = Get-RegValue $NtfsKey 'NtfsDisableLastAccessUpdate'
        if ($v -and (([int64]$v.Data -band 1) -eq 1)) { return New-Result $true $null }
        New-Result $false (T 'activé' 'on')
    }
    Read = {
        $v = Get-RegValue $NtfsKey 'NtfsDisableLastAccessUpdate'
        if ($v) { [int]([int64]$v.Data -band 3) } else { 2 }
    }
    Apply   = { & fsutil behavior set disablelastaccess 1 | Out-Null }
    Restore = { param($Before) & fsutil behavior set disablelastaccess ([int]$Before) | Out-Null }
}

if ($Cfg.disableHibernation) {
    $PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    Add-Custom @{
        Id = 'hibernation'; Group = $G; Name = (T 'Hibernation coupée (libère la taille de la RAM sur C:)' 'Hibernation off (frees the size of your RAM on C:)')
        Test = {
            $v = Get-RegValue $PowerKey 'HibernateEnabled'
            if ($v -and $v.Data -eq 0) { return New-Result $true $null }
            New-Result $false (T 'activée' 'on')
        }
        Read = {
            $v = Get-RegValue $PowerKey 'HibernateEnabled'
            if ($v) { [int]$v.Data } else { 1 }
        }
        Apply   = { & powercfg /hibernate off | Out-Null }
        Restore = { param($Before) if ($Before -eq 1) { & powercfg /hibernate on | Out-Null } }
    }
}

# --------------------------------------------------------- 6. Interface

$G = T 'Interface et souris' 'Interface and mouse'
if ($Cfg.snappierInterface) {
    Add-Registry $G (T "Menus sans délai d'ouverture" 'Menus open without delay') 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    Add-Registry $G (T 'Animations de la barre des tâches coupées' 'Taskbar animations off') 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
}
if ($Cfg.disableTransparency) {
    Add-Registry $G (T 'Transparence coupée' 'Transparency off') 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
}
if ($Cfg.disableMouseAcceleration) {
    $MouseKey    = 'HKCU:\Control Panel\Mouse'
    $MouseValues = @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2')
    Add-Custom @{
        Id = 'mouse-acceleration'; Group = $G; Name = (T 'Accélération de la souris coupée' 'Mouse acceleration off'); Reboot = $true
        Test = {
            $vals = foreach ($n in $MouseValues) { [string](Get-RegValue $MouseKey $n).Data }
            if (($vals -join ',') -eq '0,0,0') { return New-Result $true $null }
            New-Result $false ((T 'actuel : {0}' 'current: {0}') -f ($vals -join ', '))
        }
        Read    = { $h = @{}; foreach ($n in $MouseValues) { $h[$n] = [string](Get-RegValue $MouseKey $n).Data }; $h }
        Apply   = { foreach ($n in $MouseValues) { Set-RegValue $MouseKey $n '0' 'String' } }
        Restore = { param($Before) foreach ($n in $MouseValues) { Set-RegValue $MouseKey $n ([string]$Before.$n) 'String' } }
    }
}

# ----------------------------------------------------------- 7. Startup
# Turned off the way Task Manager does it (StartupApproved): Chrome can
# recreate its Run entry, but not undo this choice.

$G = T 'Démarrage' 'Startup'
$RunKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$ApprovedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'

function Get-RunNames([string]$Pattern) {
    $k = Get-Item -LiteralPath $RunKey -ErrorAction SilentlyContinue
    if ($k) { @($k.GetValueNames() | Where-Object { $_ -like $Pattern }) }
}
function Test-StartupDisabled([string]$Name) {
    $v = Get-RegValue $ApprovedKey $Name
    [bool]($v -and ($v.Data[0] -band 1))
}

if ($Cfg.disableChromeAutostart) {
    Add-Custom @{
        Id = 'startup-chrome'; Group = $G; Name = (T 'Chrome ne se lance plus avec Windows' 'Chrome no longer starts with Windows')
        Test = {
            $on = @(Get-RunNames 'GoogleChromeAutoLaunch_*' | Where-Object { -not (Test-StartupDisabled $_) })
            if ($on.Count -eq 0) { return New-Result $true $null }
            New-Result $false (T 'lancé au démarrage' 'starts with Windows')
        }
        Read = {
            foreach ($n in @(Get-RunNames 'GoogleChromeAutoLaunch_*')) {
                $v = Get-RegValue $ApprovedKey $n
                @{ Name = $n; Exists = [bool]$v; Data = $(if ($v) { [int[]]$v.Data } else { $null }) }
            }
        }
        Apply = {
            $off = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()))
            foreach ($n in @(Get-RunNames 'GoogleChromeAutoLaunch_*')) { Set-RegValue $ApprovedKey $n $off 'Binary' }
        }
        Restore = {
            param($Before)
            foreach ($b in @($Before)) {
                if (-not $b) { continue }
                if ($b.Exists) { Set-RegValue $ApprovedKey $b.Name ([byte[]]@($b.Data)) 'Binary' }
                else { Remove-RegValue $ApprovedKey $b.Name }
            }
        }
    }
}

# Left behind when the new Teams app is removed: harmless, but listed for nothing
Add-Custom @{
    Id = 'startup-teams'; Group = $G; Name = (T 'Entrée « Teams » orpheline retirée' 'Orphan "Teams" startup entry removed')
    Test = {
        if (-not (Get-RegValue $ApprovedKey 'Teams')) { return New-Result $true $null }
        $installed = (Get-RegValue $RunKey 'Teams') -or (Get-RegValue 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' 'Teams') -or
                     (Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue)
        if ($installed) { return New-Result $true (T 'Teams est installé' 'Teams is installed') }
        New-Result $false (T "Teams n'est plus installé" 'Teams is no longer installed')
    }
    Read    = { $v = Get-RegValue $ApprovedKey 'Teams'; if ($v) { , ([int[]]$v.Data) } }
    Apply   = { Remove-RegValue $ApprovedKey 'Teams' }
    Restore = { param($Before) if ($Before) { Set-RegValue $ApprovedKey 'Teams' ([byte[]]@($Before)) 'Binary' } }
}

# --------------------------------------------------- 8. Wallpaper Engine
# Wallpaper Engine rewrites its config when it quits: it is closed during
# the change, and not restarted here (it would run as administrator).

function Get-WallpaperConfig {
    $candidates = @()
    $run = Get-RegValue $RunKey 'WallpaperEngine'
    if ($run -and $run.Data -match '"?([^"]+\\)wallpaper(32|64)\.exe') { $candidates += (Join-Path $Matches[1] 'config.json') }
    foreach ($lib in Get-SteamLibraries) { $candidates += (Join-Path $lib 'steamapps\common\wallpaper_engine\config.json') }
    @($candidates | Where-Object { Test-Path -LiteralPath $_ })[0]
}
function Get-WallpaperPlayback([string]$File) {
    $txt = [IO.File]::ReadAllText($File)
    $r = @{}
    foreach ($key in 'playbackfullscreen', 'playbackmaximized') {
        if ($txt -match ('"' + $key + '"\s*:\s*"([^"]*)"')) { $r[$key] = $Matches[1] }
    }
    $r
}
function Set-WallpaperPlayback([string]$File, $Values) {
    $txt = [IO.File]::ReadAllText($File)
    foreach ($key in 'playbackfullscreen', 'playbackmaximized') {
        $v = $Values.$key
        if ($v) { $txt = [regex]::Replace($txt, '("' + $key + '"\s*:\s*)"[^"]*"', ('$1"' + $v + '"')) }
    }
    [IO.File]::WriteAllText($File, $txt, (New-Object Text.UTF8Encoding($false)))
}
function Stop-Wallpaper {
    $procs = @(Get-Process -Name 'wallpaper32', 'wallpaper64', 'webwallpaper32', 'ui32' -ErrorAction SilentlyContinue)
    if ($procs.Count) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Info (T 'Wallpaper Engine fermé, il se relancera au prochain démarrage' 'Wallpaper Engine closed, it will start again at next sign-in')
    }
}

if ($Cfg.wallpaperEnginePause) {
    Add-Custom @{
        Id = 'wallpaper-engine'; Group = 'Wallpaper Engine'; Name = (T 'En pause en plein écran et en fenêtre maximisée' 'Paused while a game is fullscreen or maximized')
        Test = {
            $f = Get-WallpaperConfig
            if (-not $f) { return New-Result $true (T 'non installé' 'not installed') }
            $r = Get-WallpaperPlayback $f
            if (($r.playbackfullscreen -in 'stop', 'pause') -and ($r.playbackmaximized -in 'stop', 'pause')) { return New-Result $true $null }
            New-Result $false ((T 'plein écran : {0}, maximisée : {1}' 'fullscreen: {0}, maximized: {1}') -f $r.playbackfullscreen, $r.playbackmaximized)
        }
        Read = { $f = Get-WallpaperConfig; if ($f) { Get-WallpaperPlayback $f } }
        Apply = {
            $f = Get-WallpaperConfig
            Stop-Wallpaper
            New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
            Copy-Item -LiteralPath $f -Destination (Join-Path $BackupDir "wallpaper-engine-config-$Stamp.json") -Force
            $r = Get-WallpaperPlayback $f
            $v = @{}
            if ($r.playbackfullscreen -notin 'stop', 'pause') { $v.playbackfullscreen = 'stop' }
            if ($r.playbackmaximized -notin 'stop', 'pause')  { $v.playbackmaximized = 'pause' }
            Set-WallpaperPlayback $f $v
        }
        Restore = {
            param($Before)
            $f = Get-WallpaperConfig
            if ($f -and $Before) { Stop-Wallpaper; Set-WallpaperPlayback $f $Before }
        }
    }
}

# ---------------------------------------------------------- 9. Defender
# Game libraries and generated media only. Keep source code folders
# (node_modules and the like) scanned: that is where npm attacks land.

function Get-WantedExclusions {
    $list = @()
    if ($Cfg.defender.excludeSteamLibraries) { foreach ($lib in Get-SteamLibraries) { $list += (Join-Path $lib 'steamapps') } }
    foreach ($p in @($Cfg.defender.extraExclusions)) { if ($p) { $list += [Environment]::ExpandEnvironmentVariables($p) } }
    @($list | Where-Object { Test-Path -LiteralPath $_ } | Sort-Object -Unique)
}
function Get-MissingExclusions {
    $current = @((Get-MpPreference).ExclusionPath)
    @(Get-WantedExclusions | Where-Object { $current -notcontains $_ })
}

if ($Cfg.defender.excludeSteamLibraries -or @($Cfg.defender.extraExclusions).Count) {
    Add-Custom @{
        Id = 'defender-exclusions'; Group = 'Defender'; Name = ((T 'Exclusions Defender ({0} dossiers)' 'Defender exclusions ({0} folders)') -f @(Get-WantedExclusions).Count)
        Test = {
            if (-not $IsAdmin) { return New-Result $null (T 'vérifiable seulement en administrateur' 'can only be checked as administrator') }
            # Another antivirus turns Defender off: nothing to exclude then
            if (-not (Get-MpPreference -ErrorAction SilentlyContinue)) { return New-Result $null (T 'Defender indisponible' 'Defender unavailable') }
            $missing = @(Get-MissingExclusions)
            if ($missing.Count -eq 0) { return New-Result $true $null }
            New-Result $false ((T 'manquantes : {0}' 'missing: {0}') -f ($missing -join ', '))
        }
        Read    = { @(Get-MissingExclusions) }
        Apply   = { foreach ($p in @(Get-MissingExclusions)) { Add-MpPreference -ExclusionPath $p -ErrorAction Stop } }
        Restore = { param($Before) foreach ($p in @($Before)) { if ($p) { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue } } }
    }
}

# ----------------------------------------------------------- 10. Network
# A driver update can bring the adapter's power saving back: it adds latency
# every time the link wakes up. Keywords cover Intel and Realtek adapters.

$G = T 'Réseau' 'Network'
$NicPowerSaving = [ordered]@{
    '*EEE'                   = 'Energy Efficient Ethernet'
    EEELinkAdvertisement     = 'Energy Efficient Ethernet'
    AdvancedEEE              = 'Advanced EEE'
    EnableGreenEthernet      = 'Green Ethernet'
    PowerSavingMode          = 'Power Saving Mode'
    ULPMode                  = 'Ultra Low Power'
    SipsEnabled              = 'System Idle Power Saver'
    AutoPowerSaveModeEnabled = 'Link Speed Battery Saver'
}
$NoAdapter = (T 'aucune carte réseau filaire trouvée' 'no wired network adapter found')

function Get-ActiveNicPowerSaving {
    if (-not $AdapterName) { return }
    foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue)) {
        if ($NicPowerSaving.Contains($p.RegistryKeyword) -and "$($p.RegistryValue)" -ne '0') { $p }
    }
}

if (@($Cfg.network.dnsServers).Count) {
    $WantedDns = @($Cfg.network.dnsServers)
    Add-Custom @{
        Id = 'network-dns'; Group = $G; Name = ((T 'Serveurs DNS : {0}' 'DNS servers: {0}') -f ($WantedDns -join ', '))
        Test = {
            if (-not $AdapterName) { return New-Result $null $NoAdapter }
            $a = @((Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
            if (($a -join ',') -eq ($WantedDns -join ',')) { return New-Result $true $null }
            New-Result $false ((T 'actuel : {0}' 'current: {0}') -f $(if ($a.Count) { $a -join ', ' } else { '-' }))
        }
        # Value set by hand; empty means "given by the router"
        Read = {
            $v = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($Adapter.InterfaceGuid)" 'NameServer'
            if ($v) { [string]$v.Data } else { '' }
        }
        Apply = { Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $WantedDns -ErrorAction Stop }
        Restore = {
            param($Before)
            if ($Before) { Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses ($Before -split ',') }
            else { Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses }
        }
    }
}

if ($Cfg.network.disablePowerSaving) {
    Add-Custom @{
        Id = 'network-power-saving'; Group = $G; Name = (T "Économies d'énergie de la carte réseau coupées" 'Network adapter power saving off')
        Test = {
            if (-not $AdapterName) { return New-Result $null $NoAdapter }
            $on = @(Get-ActiveNicPowerSaving)
            if ($on.Count -eq 0) { return New-Result $true $null }
            New-Result $false ((T 'actives : {0}' 'on: {0}') -f ((@($on) | ForEach-Object { $NicPowerSaving[$_.RegistryKeyword] } | Sort-Object -Unique) -join ', '))
        }
        Read = { $h = @{}; foreach ($p in @(Get-ActiveNicPowerSaving)) { $h[$p.RegistryKeyword] = "$($p.RegistryValue)" }; $h }
        Apply = {
            foreach ($p in @(Get-ActiveNicPowerSaving)) { $p | Set-NetAdapterAdvancedProperty -RegistryValue '0' -NoRestart -ErrorAction Stop }
            Write-Info (T 'Redémarrage de la carte réseau : la connexion coupe quelques secondes' 'Restarting the network adapter: the connection drops for a few seconds')
            Restart-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
        }
        Restore = {
            param($Before)
            $all = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue)
            foreach ($b in @($Before.PSObject.Properties)) {
                $p = @($all | Where-Object { $_.RegistryKeyword -eq $b.Name })[0]
                if ($p) { $p | Set-NetAdapterAdvancedProperty -RegistryValue "$($b.Value)" -NoRestart -ErrorAction SilentlyContinue }
            }
            Restart-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
        }
    }
}

if ($Cfg.network.disableThrottling) {
    Add-Registry $G (T 'Bridage réseau du planificateur multimédia désactivé' 'Multimedia network throttling off') 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' -1
}

# =================================================================== ENGINE

function Invoke-Test($e) {
    switch ($e.Type) {
        'Registry' {
            $v = Get-RegValue $e.Path $e.Value
            if ($null -eq $v) { return New-Result $false (T 'absent' 'missing') }
            if ($e.Kind -eq 'DWord') { $ok = ([int64]$v.Data -eq [int64]$e.Data) }
            else { $ok = ([string]$v.Data -eq [string]$e.Data) }
            if ($ok) { return New-Result $true $null }
            return New-Result $false ((T 'actuel : {0}, attendu : {1}' 'current: {0}, expected: {1}') -f $v.Data, $e.Data)
        }
        'Service' {
            $s = Get-ServiceStartType $e.Service
            if ($null -eq $s) { return New-Result $true (T 'absent' 'not installed') }
            if ($s -eq $e.StartType) { return New-Result $true $null }
            return New-Result $false ((T 'actuel : {0}' 'current: {0}') -f $StartTypeNames[$s])
        }
        'Power' {
            $i = Get-AcIndex $e.SubGroup $e.Setting
            if ($null -eq $i) { return New-Result $null (T 'illisible' 'unreadable') }
            if ($i -eq $e.Index) { return New-Result $true $null }
            return New-Result $false ((T 'actuel : {0}' 'current: {0}') -f $i)
        }
        'Custom' { return (& $e.Test) }
    }
}

function Invoke-Read($e) {
    switch ($e.Type) {
        'Registry' {
            $v = Get-RegValue $e.Path $e.Value
            if (-not $v) { return @{ Exists = $false } }
            $d = $v.Data
            if ($v.Kind -eq 'Binary') { $d = [int[]]$d }
            return @{ Exists = $true; Data = $d; Kind = $v.Kind }
        }
        'Service' { return (Get-ServiceStartType $e.Service) }
        'Power'   { return @{ Plan = (Get-ActivePowerPlan).Guid; Index = (Get-AcIndex $e.SubGroup $e.Setting) } }
        'Custom'  { if ($e.Read) { return (& $e.Read) } else { return $null } }
    }
}

function Invoke-Apply($e) {
    switch ($e.Type) {
        'Registry' { Set-RegValue $e.Path $e.Value $e.Data $e.Kind }
        'Service' {
            if ($e.StartType -eq 'Disabled') { Stop-Service -Name $e.Service -Force -ErrorAction SilentlyContinue }
            Set-Service -Name $e.Service -StartupType $e.StartType -ErrorAction Stop
        }
        'Power' {
            & powercfg /setacvalueindex SCHEME_CURRENT $e.SubGroup $e.Setting $e.Index | Out-Null
            & powercfg /setactive SCHEME_CURRENT | Out-Null
        }
        'Custom' { & $e.Apply }
    }
}

function Invoke-Restore($e, $Before) {
    switch ($e.Type) {
        'Registry' {
            if ($Before.Exists) { Set-RegValue $e.Path $e.Value (ConvertTo-RegData $Before.Data $Before.Kind) $Before.Kind }
            else { Remove-RegValue $e.Path $e.Value }
        }
        'Service' { if ($Before) { Set-Service -Name $e.Service -StartupType $Before -ErrorAction Stop } }
        'Power' {
            if ($Before.Plan -and $null -ne $Before.Index) {
                & powercfg /setacvalueindex $Before.Plan $e.SubGroup $e.Setting ([int]$Before.Index) | Out-Null
                & powercfg /setactive SCHEME_CURRENT | Out-Null
            }
        }
        'Custom' { & $e.Restore $Before }
    }
}

function Get-Groups { @($Catalog | Select-Object -ExpandProperty Group -Unique) }

# -------------------------------------------------------------------- Check

function Invoke-Check {
    $count = @{ Ok = 0; Todo = 0; Unknown = 0 }
    foreach ($group in Get-Groups) {
        Write-Title $group
        foreach ($e in @($Catalog | Where-Object Group -eq $group)) {
            $r = Invoke-Test $e
            if ($r.Ok -eq $true)      { Write-Row $TagOk Green $e.Name $r.Detail; $count.Ok++ }
            elseif ($r.Ok -eq $false) { Write-Row $TagTodo Yellow $e.Name $r.Detail; $count.Todo++ }
            else                      { Write-Row '[?]' DarkGray $e.Name $r.Detail; $count.Unknown++ }
        }
    }
    $count
}

# What the script cannot change itself: BIOS, hardware, display, drivers.
function Show-HardwareChecks {
    Write-Title (T 'État réel et matériel (voir docs\)' 'Real state and hardware (see docs\)')

    function Todo($Text, $Hint) { Write-Row $TagTodo Yellow $Text $Hint; $script:ManualCount++ }

    # What costs frames is memory integrity (service 2). VBS may stay on to
    # protect Windows Hello keys: the hypervisor already runs for WSL/Docker.
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        $hvci = @($dg.SecurityServicesRunning) -contains 2
        if ($Cfg.disableMemoryIntegrity -and $hvci) { Todo (T 'Intégrité de la mémoire encore en marche' 'Memory integrity still running') (T 'redémarre après Apply' 'restart after Apply') }
        elseif ($hvci) { Write-Info (T 'Intégrité de la mémoire active (réglage Windows par défaut)' 'Memory integrity on (Windows default)') }
        else { Write-Row $TagOk Green (T "Intégrité de la mémoire à l'arrêt" 'Memory integrity off') }
    }
    if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { Write-Info (T 'Hyperviseur chargé (WSL, Docker, Hyper-V…)' 'Hypervisor loaded (WSL, Docker, Hyper-V…)') }

    # BIOS: without latestBiosVersion in the config, the version is only shown
    $bios = Get-CimInstance Win32_BIOS
    $text = "BIOS $($bios.SMBIOSBIOSVersion)"
    if ($bios.ReleaseDate) { $text += " ($($bios.ReleaseDate.ToString('yyyy-MM-dd')))" }
    $latest = "$($Cfg.checks.latestBiosVersion)"
    if (-not $latest) { Write-Info ((T '{0} : compare avec le site du fabricant de ta carte mère' '{0}: compare with your motherboard maker''s website') -f $text) }
    elseif ([string]::CompareOrdinal("$($bios.SMBIOSBIOSVersion)".ToUpper(), $latest.ToUpper()) -lt 0) { Todo $text ((T 'la version {0} est disponible' 'version {0} is available') -f $latest) }
    else { Write-Row $TagOk Green $text }

    # A BIOS update restores the factory Secure Boot keys, without the 2023
    # certificates Windows had added: turning Secure Boot on without them can stop Windows from booting.
    $sb = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    $ca = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' 'WindowsUEFICA2023Capable'
    if ($sb -and $sb.Data -eq 1) { Write-Row $TagOk Green (T 'Secure Boot actif' 'Secure Boot on') }
    elseif ($ca -and [int]$ca.Data -ge 1) { Todo (T 'Secure Boot désactivé' 'Secure Boot off') (T 'certificats 2023 en place : à activer dans le BIOS' '2023 certificates in place: turn it on in the BIOS') }
    else { Todo (T 'Secure Boot désactivé' 'Secure Boot off') (T "d'abord SecureBoot.cmd, puis l'activer dans le BIOS" 'run SecureBoot.cmd first, then turn it on in the BIOS') }

    $post = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'FwPOSTTime'
    if ($post) {
        $s = [int]$post.Data / 1000
        $text = (T 'Démarrage du BIOS : {0:N1} s' 'BIOS boot time: {0:N1} s') -f $s
        if ($s -gt 12) { Todo $text (T 'Fast Boot dans le BIOS' 'Fast Boot in the BIOS') } else { Write-Row $TagOk Green $text }
    }

    # The XMP/EXPO profile is lost at every BIOS update: RAM falls back to its base speed.
    # The rated speed is read from part numbers like CMK16GX4M2B3200C16 or F4-3600C16.
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    if ($ram.Count) {
        $current = ($ram | Measure-Object -Property ConfiguredClockSpeed -Minimum).Minimum
        $rated = 0
        if ("$($ram[0].PartNumber)" -match '(\d{4})C\d{2}') { $rated = [int]$Matches[1] }
        $text = (T 'RAM à {0} MHz' 'RAM at {0} MHz') -f $current
        if ($rated -and $current -lt $rated) { Todo $text ((T 'prévue pour {0} : profil XMP à activer dans le BIOS' 'rated {0}: turn on the XMP profile in the BIOS') -f $rated) }
        else { Write-Row $TagOk Green $text }
    }

    $disk = Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue
    if ($disk) {
        $text = (T 'Disque système : {0} ({1})' 'System drive: {0} ({1})') -f $disk.FriendlyName, $disk.BusType
        if ("$($disk.BusType)" -eq 'NVMe') { Write-Row $TagOk Green $text }
        else { Todo $text (T 'un SSD NVMe serait le plus gros gain de réactivité' 'an NVMe SSD would be the biggest responsiveness gain') }
    }

    $hz = $null
    try { $hz = @(Get-DisplayRefresh) } catch { }
    if ($hz -and $hz.Count -eq 2) {
        $text = (T 'Écran principal à {0} Hz' 'Main display at {0} Hz') -f $hz[0]
        if ($hz[0] -lt $hz[1] - 1) { Todo $text ((T '{0} Hz disponibles dans Paramètres > Écran > Affichage avancé' '{0} Hz available in Settings > Display > Advanced display') -f $hz[1]) }
        else { Write-Row $TagOk Green $text }
    }

    $smi = Join-Path $env:windir 'System32\nvidia-smi.exe'
    if (Test-Path -LiteralPath $smi) {
        $q = @(& $smi -q 2>$null)
        for ($i = 0; $i -lt $q.Count - 1; $i++) {
            if ($q[$i] -match 'BAR1 Memory Usage' -and $q[$i + 1] -match ':\s*(\d+)\s*MiB') {
                $bar = [int]$Matches[1]
                if ($bar -gt 256) { Write-Row $TagOk Green (T 'Resizable BAR actif' 'Resizable BAR on') ((T '{0} Mo' '{0} MB') -f $bar) }
                else { Todo (T 'Resizable BAR inactif' 'Resizable BAR off') (T 'Above 4G + Re-Size BAR dans le BIOS, CSM coupé' 'Above 4G + Re-Size BAR in the BIOS, CSM off') }
                break
            }
        }
    }

    # Drivers without a date (virtual machines) are skipped
    $drivers = @()
    $date = [datetime]::MinValue
    if ($Adapter -and [datetime]::TryParse("$($Adapter.DriverDate)", [ref]$date)) {
        $drivers += [pscustomobject]@{ Name = $Adapter.InterfaceDescription; Version = $Adapter.DriverVersionString; Date = $date }
    }
    foreach ($p in @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceName LIKE '%Management Engine Interface%'" -ErrorAction SilentlyContinue)) {
        if ($p.DriverDate) { $drivers += [pscustomobject]@{ Name = $p.DeviceName; Version = $p.DriverVersion; Date = $p.DriverDate } }
    }
    foreach ($d in $drivers) {
        $text = (T 'Pilote {0} : {1} ({2})' 'Driver {0}: {1} ({2})') -f $d.Name, $d.Version, $d.Date.ToString('yyyy-MM-dd')
        if ($d.Date -lt (Get-Date).AddYears(-2)) { Todo $text (T 'plus de 2 ans' 'over 2 years old') } else { Write-Row $TagOk Green $text }
    }

    # Gigabit needs all 4 pairs of the cable: a damaged pair drops the link to 100 Mbps
    if ($Adapter -and $Adapter.Status -eq 'Up') {
        $min = [int64]$Cfg.checks.minLinkSpeedMbps * 1000000
        $text = (T 'Liaison réseau à {0}' 'Network link at {0}') -f $Adapter.LinkSpeed
        if ($Adapter.Speed -lt $min) { Todo $text (T 'câble ou port du routeur' 'cable or router port') } else { Write-Row $TagOk Green $text }
    }

    $c = Get-Volume -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
    if ($c) { Write-Info ((T '{0} : {1:N0} Go libres sur {2:N0}' '{0}: {1:N0} GB free of {2:N0}') -f $env:SystemDrive, ($c.SizeRemaining / 1GB), ($c.Size / 1GB)) }
}

# Current refresh rate of the main display, and the highest one it offers at the current resolution
function Get-DisplayRefresh {
    if (-not ('PcTuning.Display' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PcTuning {
    public static class Display {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);

        public static int[] Refresh() {
            DEVMODE cur = new DEVMODE();
            cur.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(null, -1, ref cur)) return null;
            int max = 0;
            DEVMODE m = new DEVMODE();
            m.dmSize = cur.dmSize;
            for (int i = 0; EnumDisplaySettings(null, i, ref m); i++)
                if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency > max)
                    max = m.dmDisplayFrequency;
            return new int[] { cur.dmDisplayFrequency, max };
        }
    }
}
'@
    }
    [PcTuning.Display]::Refresh()
}

# -------------------------------------------------------------------- Apply

function New-RestorePoint {
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop } catch { }
    # Windows allows one restore point per 24 h: the limit is lifted while creating this one
    $sr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $before = Get-RegValue $sr 'SystemRestorePointCreationFrequency'
    Set-RegValue $sr 'SystemRestorePointCreationFrequency' 0 'DWord'
    try {
        Checkpoint-Computer -Description "pc-tuning $Stamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Row $TagOk Green (T 'Point de restauration créé' 'Restore point created')
    } catch {
        Write-Warn ((T 'Point de restauration impossible : {0}' 'Could not create a restore point: {0}') -f $_.Exception.Message)
        Write-Warn (T "L'état d'avant reste noté dans backups\ pour Undo" 'The previous state is still saved in backups\ for Undo')
    }
    if ($before) { Set-RegValue $sr 'SystemRestorePointCreationFrequency' $before.Data 'DWord' }
    else { Remove-RegValue $sr 'SystemRestorePointCreationFrequency' }
}

function Invoke-ApplyAll {
    if (-not $DryRun) { Write-Title (T 'Filet de sécurité' 'Safety net'); New-RestorePoint }

    $changes = New-Object System.Collections.Generic.List[object]
    $count = @{ Ok = 0; Fixed = 0; Review = 0; Unknown = 0 }

    foreach ($group in Get-Groups) {
        Write-Title $group
        foreach ($e in @($Catalog | Where-Object Group -eq $group)) {
            $r = Invoke-Test $e
            if ($r.Ok -eq $true) { Write-Row $TagOk Green $e.Name $r.Detail; $count.Ok++; continue }
            if ($null -eq $r.Ok) { Write-Row '[?]' DarkGray $e.Name $r.Detail; $count.Unknown++; continue }

            $before = $null
            try { $before = Invoke-Read $e } catch { Write-Warn ((T "État d'avant illisible : {0}" 'Could not read the previous state: {0}') -f $_.Exception.Message) }
            $changes.Add([pscustomobject]@{ Id = $e.Id; Name = $e.Name; Before = $before })

            if ($DryRun) { Write-Row $TagTodo Yellow $e.Name $r.Detail; $count.Fixed++; continue }

            try { Invoke-Apply $e } catch { Write-Warn $_.Exception.Message }
            $r2 = Invoke-Test $e
            if ($r2.Ok -eq $true) {
                $note = $null
                if ($e.Reboot) { $note = T 'effectif après redémarrage' 'takes effect after a restart'; $script:RebootNeeded = $true }
                Write-Row $TagFixed Green $e.Name $note
                $count.Fixed++
            } elseif ($e.Reboot) {
                # A driver still loaded goes away at the next restart
                Write-Row $TagReview Yellow $e.Name (T 'redémarre, puis relance Check.cmd' 'restart, then run Check.cmd')
                $script:RebootNeeded = $true
                $count.Review++
            } else {
                Write-Row $TagFailed Red $e.Name $r2.Detail
                $count.Review++
            }
        }
    }

    Write-Title (T 'Bilan' 'Summary')
    if ($changes.Count) {
        $json = [pscustomobject]@{ Date = (Get-Date).ToString('s'); Changes = $changes } | ConvertTo-Json -Depth 8
        $target = $StateFile
        if (-not $target -and -not $DryRun) { $target = Join-Path $BackupDir "state-before-$Stamp.json" }
        if ($target) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Set-Content -LiteralPath $target -Value $json -Encoding UTF8
            Write-Info ((T "État d'avant noté dans {0}" 'Previous state saved to {0}') -f $target)
        }
    }
    if ($DryRun) {
        Write-Info ((T "Simulation : {0} déjà en place, {1} seraient corrigés. Rien n'a été modifié." 'Dry run: {0} already in place, {1} would be fixed. Nothing was changed.') -f $count.Ok, $count.Fixed)
    } else {
        Write-Info ((T 'Déjà en place : {0}   Corrigés : {1}   À revoir : {2}' 'Already in place: {0}   Fixed: {1}   To review: {2}') -f $count.Ok, $count.Fixed, $count.Review)
        if ($count.Fixed) { Write-Info (T 'Pour revenir en arrière : Undo.cmd' 'To go back: Undo.cmd') }
    }
}

# --------------------------------------------------------------------- Undo

function Invoke-Undo {
    $file = $null
    if ($StateFile) { $file = Get-Item -LiteralPath $StateFile -ErrorAction SilentlyContinue }
    else {
        $file = Get-ChildItem -LiteralPath $BackupDir -Filter 'state-before-*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike '*-undone.json' } | Sort-Object Name -Descending | Select-Object -First 1
    }
    if (-not $file) { Write-Warn (T 'Aucune sauvegarde à restaurer dans backups\' 'No saved state to restore in backups\'); return }
    Write-Info ((T 'Sauvegarde utilisée : {0}' 'Saved state used: {0}') -f $file.Name)

    $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    # Reverse order of Apply: power settings before the plan, and so on
    $list = @($data.Changes)
    [array]::Reverse($list)

    Write-Title (T 'Restauration' 'Restore')
    foreach ($c in $list) {
        $e = @($Catalog | Where-Object Id -eq $c.Id)[0]
        if (-not $e) { Write-Warn ((T 'Réglage absent de la configuration actuelle, ignoré : {0}' 'Setting not in the current configuration, skipped: {0}') -f $c.Name); continue }
        if ($e.Type -eq 'Custom' -and -not $e.Restore) { Write-Row '[-]' Gray $e.Name $e.NotReversible; continue }
        if ($DryRun) { Write-Row $TagToRestore Yellow $e.Name; continue }
        try {
            Invoke-Restore $e $c.Before
            Write-Row $TagRestored Green $e.Name
            if ($e.Reboot) { $script:RebootNeeded = $true }
        } catch {
            Write-Row $TagFailed Red $e.Name $_.Exception.Message
        }
    }
    if (-not $DryRun) {
        Rename-Item -LiteralPath $file.FullName -NewName ($file.BaseName + '-undone.json')
        Write-Info (T 'Sauvegarde marquée comme annulée' 'Saved state marked as undone')
    }
}

# --------------------------------------------------------------- SecureBoot
# Microsoft procedure ("Registry key updates for Secure Boot"):
#   AvailableUpdates = 0x5944, run the Secure-Boot-Update task  -> 0x4100, restart
#   run the task a second time                                  -> 0x4000, done
# When the 2023 boot manager is already in place, 0x4000 comes in one step.

function Invoke-SecureBoot {
    $key     = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
    $service = "$key\Servicing"

    $srv = Get-ItemProperty -LiteralPath $service -ErrorAction SilentlyContinue
    $pending = [int](Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).AvailableUpdates
    Write-Title (T 'Certificats Secure Boot 2023' '2023 Secure Boot certificates')
    Write-Info ((T 'Statut : {0}   certificat 2023 dans le BIOS : {1}   en attente : 0x{2:X}' 'Status: {0}   2023 certificate in the BIOS: {1}   pending: 0x{2:X}') -f $srv.UEFICA2023Status, $srv.WindowsUEFICA2023Capable, $pending)

    if ($srv.UEFICA2023Status -eq 'Updated' -and [int]$srv.WindowsUEFICA2023Capable -ge 1) {
        Write-Row $TagOk Green (T 'Certificats 2023 en place' '2023 certificates in place')
        Write-Info (T 'Tu peux activer Secure Boot dans le BIOS (docs\bios.fr.md)' 'You can turn Secure Boot on in the BIOS (docs\bios.md)')
        return
    }
    if ($pending -eq 0x4000) {
        Write-Row $TagOk Green (T 'Windows a terminé sa part' 'Windows has done its part')
        Write-Info (T 'Redémarre, puis relance Check.cmd' 'Restart, then run Check.cmd')
        $script:RebootNeeded = $true
        return
    }

    # Without keys ("Setup" mode) the update has nothing to build on, and
    # installing the factory keys AFTER it would wipe the 2023 certificates again.
    $setup = $null
    try { $setup = (Get-SecureBootUEFI -Name SetupMode -ErrorAction Stop).Bytes[0] } catch { }
    if ($setup -eq 1) {
        Write-Warn (T "Le BIOS n'a pas de clés Secure Boot (mode Setup)." 'The BIOS has no Secure Boot keys (Setup mode).')
        Write-Warn (T 'Dans le BIOS : installe les clés d''usine (Restore Factory Keys, ou Secure Boot en mode Standard),' 'In the BIOS: install the factory keys (Restore Factory Keys, or Secure Boot in Standard mode),')
        Write-Warn (T 'redémarre, puis relance SecureBoot.cmd.' 'restart, then run SecureBoot.cmd again.')
        return
    }

    if ($pending -eq 0x4100) { $step = 2; $target = 0x4000 } else { $step = 1; $target = 0x4100 }
    Write-Info ((T 'Étape {0} sur 2' 'Step {0} of 2') -f $step)
    if ($DryRun) { Write-Info (T "Simulation : rien n'a été lancé" 'Dry run: nothing was started'); return }

    if ($step -eq 1) { Set-RegValue $key 'AvailableUpdates' 0x5944 'DWord' }
    Start-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction Stop
    Write-Info (T "Tâche Windows lancée, attente du résultat (jusqu'à 3 minutes)..." 'Windows task started, waiting for the result (up to 3 minutes)...')

    $end = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Seconds 5
        $pending = [int](Get-ItemProperty -LiteralPath $key).AvailableUpdates
    } while ($pending -ne $target -and $pending -ne 0x4000 -and (Get-Date) -lt $end)

    $srv = Get-ItemProperty -LiteralPath $service -ErrorAction SilentlyContinue
    if ($srv.UEFICA2023Error) { Write-Warn ((T "Windows signale l'erreur {0} : journal Système, source TPM-WMI" 'Windows reports error {0}: System log, source TPM-WMI') -f $srv.UEFICA2023Error) }

    if ($pending -eq 0x4000) {
        Write-Row $TagOk Green (T 'Certificats 2023 installés' '2023 certificates installed')
        Write-Info (T 'Redémarre, puis relance Check.cmd' 'Restart, then run Check.cmd')
        $script:RebootNeeded = $true
    } elseif ($pending -eq $target) {
        Write-Row $TagOk Green ((T 'Étape {0} terminée' 'Step {0} done') -f $step)
        Write-Info (T "Redémarre, puis relance SecureBoot.cmd pour l'étape 2" 'Restart, then run SecureBoot.cmd for step 2')
        $script:RebootNeeded = $true
    } else {
        Write-Warn ((T "La tâche n'a pas fini dans le délai (en attente : 0x{0:X}). Redémarre, puis relance SecureBoot.cmd." 'The task did not finish in time (pending: 0x{0:X}). Restart, then run SecureBoot.cmd again.') -f $pending)
    }
}

# ===================================================================== MAIN

Write-Host ''
$header = "  pc-tuning - $Mode"
if ($DryRun) { $header += (T ' (simulation)' ' (dry run)') }
Write-Host $header -ForegroundColor White
Write-Host ("  {0}   {1} : {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), (T 'configuration' 'configuration'), $ConfigName) -ForegroundColor DarkGray

$transcript = ($Mode -ne 'Check' -and -not $DryRun)
if ($transcript) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Start-Transcript -Path (Join-Path $LogDir "$($Mode.ToLower())-$Stamp.txt") | Out-Null
}

switch ($Mode) {
    'Check' {
        $c = Invoke-Check
        Show-HardwareChecks
        Write-Title (T 'Bilan' 'Summary')
        if ($c.Todo -eq 0) { Write-Row $TagOk Green ((T 'Les {0} réglages sont en place' 'All {0} settings are in place') -f $c.Ok) }
        else { Write-Row $TagTodo Yellow ((T '{0} réglage(s) à corriger' '{0} setting(s) to fix') -f $c.Todo) (T 'lance Apply.cmd' 'run Apply.cmd') }
        if ($script:ManualCount) { Write-Info ((T '{0} point(s) à faire à la main : voir docs\' '{0} thing(s) to do by hand: see docs\') -f $script:ManualCount) }
    }
    'Apply'      { Invoke-ApplyAll }
    'Undo'       { Invoke-Undo }
    'SecureBoot' { Invoke-SecureBoot }
}

if ($script:RebootNeeded -and -not $DryRun) {
    Write-Host ''
    Write-Warn (T 'Un redémarrage est nécessaire pour que tout prenne effet.' 'A restart is needed for everything to take effect.')
    if (-not $NoPause) {
        $answer = Read-Host (T '  Enregistre ton travail, puis tape o pour redémarrer maintenant (o/N)' '  Save your work, then type y to restart now (y/N)')
        if ($answer -match '^[oOyY]') {
            if ($transcript) { Stop-Transcript | Out-Null }
            Restart-Computer
            exit
        }
    }
}

if ($transcript) { Stop-Transcript | Out-Null }
Wait-End
