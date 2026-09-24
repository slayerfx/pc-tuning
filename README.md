# pc-tuning

**Windows, BIOS and hardware tuning for a desktop gaming and creation PC. Every Windows setting can be checked, re-applied and undone.**

*Version française : [README.fr.md](README.fr.md)*

Most "optimizers" apply a pile of tweaks once and leave you guessing. `pc-tuning` keeps a list of settings it can **check** at any time. That matters because Windows Update, driver installs and some apps quietly put settings back. `Check.cmd` shows exactly what moved, and `Apply.cmd` fixes only that.

The BIOS and the hardware can't be changed by a script, so each gets a guide: [BIOS](docs/bios.md) and [hardware](docs/hardware.md).

## Quick start

1. Download the project (**Code → Download ZIP**) and extract it anywhere, for example in `Documents\pc-tuning`.
   If Windows blocks the files, right-click the ZIP → **Properties** → tick **Unblock** before extracting.
2. *Optional:* copy `config.example.json` to `config.json` and turn on the options you want (see [Configuration](#configuration)).
3. Double-click **`Check.cmd`**. It lists every setting and the state of your hardware, and changes nothing.
4. Double-click **`Apply.cmd`** and accept the administrator prompt. It creates a restore point, saves the current state, fixes what needs fixing, then offers to restart.
5. Changed your mind? **`Undo.cmd`** puts back the state saved by the last Apply.

Run `Check.cmd` again after big Windows updates or driver installs. Messages are in English or French, following the Windows display language.

## What it manages

On by default:

| Group | Settings | Why |
|---|---|---|
| Telemetry | DiagTrack, usage-and-quality and offline-maps services off. 15 telemetry scheduled tasks plus the SoftLanding and GoogleUserPEH folders. Lowest telemetry level, no Bing or web suggestions in Start, no silent installs of promoted apps, no sponsored content, no advertising ID | Less background activity, fewer ads |
| Services | Data usage (`DusmSvc`) and inventory (`InventorySvc`) set to manual | Started only when needed |
| Apps | 14 promotional apps: Bing News/Weather, Solitaire, Clipchamp, Get Help, Feedback Hub, To Do, Dev Home, Power Automate, Widgets, personal Teams… | Xbox, OneDrive, Phone Link and Media Player are kept: add them to `extraApps` if you don't use them |
| Gaming and performance | Game DVR off, hardware-accelerated GPU scheduling (required for DLSS Frame Generation), Ultimate Performance power plan, no PCI Express or USB power saving, no NTFS last-access timestamps | Fewer latency spikes and background writes |
| Interface and mouse | Menus open without delay, no taskbar animations, mouse acceleration off | Snappier desktop, consistent aim |
| Startup | Orphan "Teams" startup entry removed | Left behind when the new Teams app is uninstalled |
| Wallpaper Engine | Paused while a game is fullscreen or maximized (borderless games) | Stops a second 3D renderer running during games |
| Network | Power saving of the wired adapter off (Energy Efficient Ethernet and the like, Intel and Realtek), multimedia network throttling off | A driver update often turns them back on |

Off by default, because they are trade-offs or personal taste:

| Option | What it does | Trade-off |
|---|---|---|
| `disableMemoryIntegrity` | Turns off memory integrity (HVCI) and VBS, and locks the choice with a policy so Windows can't turn it back on. The hypervisor stays, so WSL and Docker keep working | **Less protection against malicious drivers.** The gain is real on Intel CPUs before 10th gen (no MBEC, HVCI is emulated), small on recent ones. Some anti-cheats require it: `Undo.cmd` if a game refuses to start |
| `removeNahimic` | Removes the Nahimic audio layer (MSI and others) and blocks its hardware IDs so Windows Update can't put it back | Known source of audio latency and in-game stutters, but some people like its effects |
| `disableHibernation` | `powercfg /hibernate off` | Frees a file the size of your RAM on C:, but no hibernation or Fast Startup (desktops only) |
| `disableTransparency` | No transparency effects | Taste |
| `disableChromeAutostart` | Stops Chrome from launching with Windows, the way Task Manager does | Taste |
| `defender.excludeSteamLibraries`, `defender.extraExclusions` | Defender exclusions for game libraries and generated media (video caches, recordings) | **Excluded folders are not scanned.** Never exclude source code or download folders |
| `network.dnsServers` | Sets the DNS servers of the wired adapter, for example your router then [Quad9](https://quad9.net) (`9.9.9.9`) | Leave empty to keep the ones from your router |

## What Check also reports

Things no script should change for you, with a hint when something is off:

- memory integrity really stopped (after a restart), hypervisor loaded
- BIOS version (compared with `checks.latestBiosVersion` if you set it), Secure Boot and its 2023 certificates, BIOS boot time (Fast Boot)
- RAM running at its rated speed (XMP/EXPO profile)
- system drive type (SATA or NVMe)
- main display at the highest refresh rate it offers
- Resizable BAR (NVIDIA)
- age of the network and Intel Management Engine drivers
- wired link speed (a damaged cable drops Gigabit to 100 Mbps)

## Configuration

Everything works without configuration. To customize, copy `config.example.json` to `config.json` (next to the script, ignored by git) or pass `-Config path\to\file.json`. Unknown keys are reported, so typos don't go unnoticed.

| Key | Default | Meaning |
|---|---|---|
| `disableMemoryIntegrity` | `false` | See above |
| `removeNahimic` | `false` | See above |
| `disableTelemetry` | `true` | Telemetry services, tasks and settings |
| `removeApps` | 14 apps | Apps to remove (package names, as shown by `Get-AppxPackage`) |
| `extraApps` | none | More apps to remove, for example `"Microsoft.GamingApp"`, `"Microsoft.OneDriveSync"`, `"Microsoft.OutlookForWindows"` |
| `manualServices` | `DusmSvc`, `InventorySvc` | Services set to manual start. Missing services are ignored |
| `disableGameDvr` | `true` | Game DVR recording |
| `hardwareGpuScheduling` | `true` | HAGS |
| `desktopPowerPlan` | `true` | Ultimate Performance plan, no PCIe or USB power saving. **Turn off on a laptop** |
| `disableHibernation` | `false` | See above |
| `snappierInterface` | `true` | Menu delay and taskbar animations |
| `disableTransparency` | `false` | See above |
| `disableMouseAcceleration` | `true` | "Enhance pointer precision" off |
| `disableChromeAutostart` | `false` | See above |
| `wallpaperEnginePause` | `true` | Only if Wallpaper Engine is installed |
| `network.adapter` | `""` | Adapter name (`Get-NetAdapter`). Empty: the first connected wired adapter |
| `network.dnsServers` | none | See above |
| `network.disablePowerSaving` | `true` | Adapter power saving |
| `network.disableThrottling` | `true` | `NetworkThrottlingIndex` |
| `defender.excludeSteamLibraries` | `false` | Every Steam library, read from Steam's own list |
| `defender.extraExclusions` | none | Folders to exclude. Environment variables allowed: `"%USERPROFILE%\\Videos"` |
| `checks.latestBiosVersion` | `""` | Latest BIOS version for your board, as Windows shows it (`1.D0` for MSI's "1D") |
| `checks.minLinkSpeedMbps` | `1000` | Link speed below which Check warns |

## After a BIOS update

A BIOS update resets everything, including things Windows had changed: XMP profile, Secure Boot keys, Microsoft's 2023 Secure Boot certificates, and it clears the TPM. Follow the [BIOS guide](docs/bios.md). **`SecureBoot.cmd`** puts the 2023 certificates back, using [Microsoft's procedure](https://support.microsoft.com/en-us/topic/registry-key-updates-for-secure-boot-windows-devices-with-it-managed-updates-a7be69c9-4634-42e1-9ca1-df06f43f360d), so Secure Boot can be turned on again without a "Secure Boot Violation" screen.

## Safety

- **Restore point** before every Apply (`rstrui.exe` to use it).
- **Previous state** of every changed setting saved to `backups\state-before-*.json`: that is what `Undo.cmd` restores.
- **Log** of every Apply, Undo and SecureBoot in `logs\`.
- **Not reversible by Undo:** removed apps (reinstall them from the Microsoft Store) and removed Nahimic drivers (reinstall your motherboard's audio package, after `Undo.cmd` lifts the block).
- Try `Apply.cmd -DryRun` first to see what would change.

## Deliberately left out

Many popular tweaks are neutral at best:

- **Disabling SysMain**: advice from the hard-drive era. On an SSD with 16 GB or more, it helps.
- **`Win32PrioritySeparation`, `SystemResponsiveness`, MMCSS priorities**: Windows defaults are already right for a desktop.
- **Deleting the page file**: crashes in video editors, some games refuse to start.
- **Emptying `C:\Windows\Installer`**: breaks repair and uninstall of MSI programs.
- **`DISM /ResetBase`**: Windows updates can no longer be uninstalled.
- **Defragmenting SSDs**: TRIM already does the job.
- **Disabling Defender**, third-party "optimizers" and registry cleaners.
- **PcaPatchDbTask**: Windows turns it back on at every boot.

## Command line

```powershell
powershell -ExecutionPolicy Bypass -File .\pc-tuning.ps1 -Mode Check
powershell -ExecutionPolicy Bypass -File .\pc-tuning.ps1 -Mode Apply -DryRun -Config D:\my-config.json -Language en
```

| Parameter | Meaning |
|---|---|
| `-Mode Check\|Apply\|Undo\|SecureBoot` | What to do (default: `Check`) |
| `-DryRun` | Walk through Apply, Undo or SecureBoot without changing anything |
| `-Config <file>` | Use a JSON configuration file |
| `-Language fr\|en` | Force the language (default: Windows display language) |
| `-StateFile <file>` | State file to write (Apply) or restore (Undo) instead of the latest one in `backups\` |
| `-NoPause` | Do not wait for Enter at the end |

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 (built in), on a desktop PC. Administrator rights for Apply, Undo and SecureBoot: the script asks for them. Check runs without them, except the Defender exclusions line.

Built and tested on an Intel Core i9-9900K, MSI MPG Z390 Gaming Pro Carbon, NVIDIA RTX 4070 Ti and Windows 11 25H2.

## Disclaimer

Provided as is, without warranty. Read what `Check.cmd` and `Apply.cmd -DryRun` report before applying.

## License

[MIT](LICENSE)
