# BIOS guide

*Version française : [bios.fr.md](bios.fr.md)*

No script can change BIOS settings. This page is the checklist, including what to redo **after every BIOS update**, which resets everything. Menu paths are those of MSI Click BIOS 5 in advanced mode (F7). Other brands use similar names in different places.

`Check.cmd` tells you from Windows whether most of these settings took effect.

## Before a BIOS update

- **BitLocker:** if it is on, suspend it first (*Control Panel → BitLocker → Suspend protection*), and have your recovery key at hand. The update clears the TPM, and BitLocker would otherwise ask for the key at boot.
- **Write down your settings.** On MSI, **F12** saves a screenshot of the current page to a FAT32 USB stick.
- Use the board's built-in flash tool (M-Flash, Q-Flash, EZ Flash…) from a FAT32 USB stick. Don't cut the power during the flash.

**What is it worth?** Mostly security: CPU microcode fixes and firmware vulnerabilities. It rarely brings frames by itself, except when it unlocks a feature such as Resizable BAR.

## What a BIOS update resets

Seen on a real update:

| What | Consequence | Fix |
|---|---|---|
| XMP / EXPO profile | RAM falls back to its base speed (2133 MHz for DDR4) | Turn it back on. `Check.cmd` warns |
| Secure Boot | Off, and the keys are gone ("System Mode: Setup") | See [Secure Boot](#secure-boot-after-a-bios-update) |
| Microsoft's 2023 Secure Boot certificates | Gone from the firmware, while Windows already boots with the 2023-signed boot manager | `SecureBoot.cmd` |
| TPM | Cleared | Windows Hello PIN to recreate if refused, passkeys stored in Windows Hello lost, BitLocker recovery key asked if it wasn't suspended |
| CSM, Above 4G, Resizable BAR, Fast Boot, fan curves | Back to defaults | This checklist |

## Checklist

| Setting | Where (MSI) | Value | Why |
|---|---|---|---|
| **XMP / EXPO** | button top left | Profile 1 | RAM at its rated speed |
| Memory Fast Boot | OC, memory settings | Enabled | No memory retraining at every boot |
| CPU virtualization (Intel VT-x / AMD SVM) | OC → CPU Features | Enabled | WSL, Docker, Windows Sandbox |
| TPM (Intel PTT / AMD fTPM) | Settings → Security → Trusted Computing | Enabled | Windows 11, Windows Hello |
| **CSM off** | Settings → Advanced → Windows OS Configuration → *Windows 10 WHQL Support* | UEFI | Required for Secure Boot and Resizable BAR. Only if Windows is installed in UEFI mode (`msinfo32`: "BIOS mode: UEFI") |
| Above 4G decoding | Settings → Advanced → PCIe/PCI Sub-system Settings | Enabled | Required for Resizable BAR |
| **Re-Size BAR Support** | same menu | Enabled | A few percent in some games. Not offered by every board and BIOS |
| **Fast Boot** | Settings → Advanced → Windows OS Configuration | Fast Boot on, *MSI Fast Boot* off | Seconds saved at every boot. MSI Fast Boot also skips USB init, which makes the BIOS hard to reach |
| Boot order | Settings → Boot | Windows Boot Manager first, network boot off | Nothing searched for at boot. Other devices stay reachable with the boot menu (F11 on MSI) |
| **Secure Boot** | Settings → Advanced → Windows OS Configuration → Secure Boot | Enabled, Standard mode | Security, and required by some anti-cheats (Battlefield 6, Valorant, Call of Duty…) |

With Fast Boot on, the keyboard may not be read in time to enter the BIOS. Go through Windows instead: *Settings → System → Recovery → Advanced startup → Restart now → Troubleshoot → Advanced options → UEFI Firmware Settings*.

## Secure Boot after a BIOS update

Windows now boots with a boot manager signed by Microsoft's 2023 certificate. The firmware keys restored by a BIOS update may not include that certificate. Turning Secure Boot on then risks a "Secure Boot Violation" screen. Safe order:

1. BIOS: make sure keys are installed. Secure Boot in **Standard** mode installs the factory keys at the next boot. On some boards: *Secure Boot Mode: Custom → Key Management → Restore Factory Keys*.
2. Windows: run **`SecureBoot.cmd`**. It stops if the firmware has no keys. It may take two runs with a restart in between.
3. `Check.cmd` should say "Secure Boot off (2023 certificates in place: turn it on in the BIOS)", or "Secure Boot on" if it already is.
4. BIOS: **Secure Boot → Enabled**, Standard mode.

If the PC shows a Secure Boot error at boot: set Secure Boot back to **Disabled** and Windows starts normally. Nothing is broken, the certificates just weren't in place yet. Run `SecureBoot.cmd`, then try again.

Once `SecureBoot.cmd` has run, **don't use "Restore Factory Keys"** again: it would wipe the 2023 certificates once more.

## Leave alone

- **C-states, SpeedStep/EIST, voltages, Load-Line Calibration**: the defaults are right. Check that the CPU holds its all-core turbo under load (HWMonitor, or the benchmark tools in the [hardware guide](hardware.md)). No drop = nothing to fix.
- **Game Boost and other one-click overclocks**: they raise voltage much more than needed.

## Multi-core enhancement: your call

MSI "Enhanced Turbo", ASUS "MultiCore Enhancement", Gigabyte "Enhanced Multi-Core Performance" run every core at the single-core turbo frequency. On an i9-9900K, that means 5.0 GHz instead of 4.7 GHz on all cores.

- **Gain:** about +6% in rendering, compiling or video export. In games, 0 to 3%: they rarely load every core fully.
- **Cost:** 40 to 50 W more under load, and a lot more heat.

Only with a big air cooler or a liquid cooler, checking that the CPU stays under 85-90 °C in games. Otherwise leave it off.

## Optional: undervolting

On MSI boards, **CPU Lite Load** (Auto by default) lowers the CPU voltage one step at a time: lower temperatures, and sometimes steadier boost clocks. Every step down must be stress-tested (Cinebench loops, OCCT): too low, and the PC crashes under load. Only worth it if the CPU runs hot.
