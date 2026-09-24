# Hardware guide

*Version française : [hardware.fr.md](hardware.fr.md)*

No Windows setting makes up for hardware that is badly configured or worn out. Ranked by real impact, from the biggest gain to the finest:

## 1. An NVMe SSD as the system drive

By far the biggest responsiveness gain: boot, app launches, project loading.

- **SATA SSD → NVMe:** a SATA SSD tops out around 550 MB/s. A PCIe 3.0 NVMe does about 3,500 MB/s, PCIe 4.0 about 7,000 MB/s.
- **Hard drive → any SSD:** a night-and-day difference.
- Before buying: a free **M.2** slot, and its **PCIe generation**. On many boards, one M.2 slot shares its lanes with SATA ports and disables some of them: the manual says which.

`Check.cmd` shows the type of your system drive.

## 2. RAM at its rated speed (XMP / EXPO)

The most overlooked free setting. Without its profile, RAM runs at its base speed (2133 MHz for DDR4) instead of the speed on the box. It shows in the 1% lows in games.

- BIOS → turn on **XMP** (Intel) or **EXPO/DOCP** (AMD). **Every BIOS update turns it off.**
- Check: *Task Manager → Performance → Memory → Speed*, or `Check.cmd`.

## 3. Resizable BAR

Lets the CPU reach all of the graphics card's memory at once instead of 256 MB windows. A few percent in some games, nothing in others. It needs **Above 4G decoding**, **Re-Size BAR** and **CSM off** in the BIOS (see the [BIOS guide](bios.md)), and a board and BIOS that offer it. `Check.cmd` reads it for NVIDIA cards.

## 4. The display at its real refresh rate

Windows often leaves a 144 Hz display at 60 Hz. *Settings → System → Display → Advanced display* → pick the highest rate. `Check.cmd` warns when a higher rate is offered.

- **G-Sync / FreeSync:** turn it on, over **DisplayPort**.
- **Overclocked refresh rates** ("OC 180 Hz" on a 144 Hz panel): try them, but look closely. On many panels, TN especially, overdrive isn't tuned for the overclocked rate: bright halos behind moving objects, washed-out colors. The native rate is often the better picture.

## 5. Getting the most out of the graphics card at 1080p

With a powerful card at 1080p, the CPU is usually the limit, not the graphics card. Use the headroom for image quality:

- **DLDSR** (NVIDIA Control Panel → *Manage 3D settings → DSR - Factors → 2.25x DL*): games render at 2880×1620 and are scaled down to your screen. A much finer image, for almost the same FPS when the CPU is the limit. Pick that resolution in the game, in fullscreen mode.
- **DLDSR 2.25x + DLSS Quality:** the game renders internally at 1080p, then outputs at 2880×1620. A better picture than native 1080p at about the same cost.
- **DSR - Smoothness:** 33% by default. Raise it towards 50% if the image looks over-sharpened, especially with DLSS.
- **Competitive games:** stay at native resolution, with **NVIDIA Reflex** on, for the most FPS and the lowest latency.

## 6. Drive health

Free tool: **CrystalDiskInfo**. What to read:

| Field | Meaning |
|---|---|
| Health percentage | Life left for an SSD. Plan a replacement when it drops under about 20% |
| **Total host writes** | Compare with the endurance your SSD's maker guarantees (TBW, for example 150 TB for a 250 GB Samsung 860 EVO). A system drive that writes several GB per hour usually has a culprit: continuous NVIDIA Instant Replay, video editing caches, WSL/Docker disks |
| Reallocated sectors (05), pending sectors (C5), uncorrectable errors | Must stay at 0. If they grow, back up and replace the drive |
| **UDMA CRC errors (C7)** | Transmission errors between the drive and the board: almost always **the SATA cable or its port**, not the drive. Replace the cable and check that the count stops growing |

## 7. Wired network at 1 Gbps

Almost every Ethernet port is Gigabit. Gigabit uses all 4 pairs of the cable, while 100 Mbps only needs 2. A damaged pair or a connector not fully clicked in drops the link to 100 Mbps, which caps your internet at about 95 Mbit/s whatever your plan. `Check.cmd` shows the link speed. If it says 100 Mbps:

1. Unplug and replug the cable **at both ends**, until it clicks.
2. Try **another router port**.
3. Replace the cable: **Cat 5e at least, Cat 6 ideally**, no kinks, latch intact.

Don't force "Speed & Duplex" to 1 Gbps in the adapter settings: without auto-negotiation, the link may not come up at all.

## 8. Temperatures and dust

A CPU or graphics card that runs too hot slows itself down. Free tools: **HWMonitor** or **HWiNFO**. Under load, keep the CPU under about 90 °C and the graphics card under about 83 °C.

- Dust the case, the heatsinks and the filters. Airflow: front and bottom in, rear and top out.
- On an older machine, fresh thermal paste on the CPU can bring back hundreds of MHz under sustained load.

## 9. Drivers

Chipset, network and Intel Management Engine drivers: from Intel or AMD, or from your motherboard's support page. `Check.cmd` flags network and Management Engine drivers older than 2 years.

For a clean install without extra software: extract the package, then *Device Manager → right-click the device → Update driver → Browse my computer* → the extracted folder, subfolders included. Do the network driver last: the connection drops for a few seconds. Avoid "driver updater" apps.

## Benchmarking

Test one component at a time, with the same conditions every time, and write down the scores: that's how you see the effect of a change.

| What | Free tool | Measures |
|---|---|---|
| CPU | **Cinebench 2024** | single-core and multi-core score |
| Gaming (GPU + CPU) | **3DMark** (free demo on Steam), **Time Spy** test | graphics score and CPU score, compared with identical PCs |
| GPU only | **Unigine Superposition** | FPS in a fixed 3D scene |
| Drives | **CrystalDiskMark** | sequential and random read/write speeds |
| Your real games | **CapFrameX** | average FPS and **1% lows**, how smooth it really feels |
| Temperatures | **HWMonitor** | to watch while testing |

Method:

1. Close everything: chat apps, browser, animated wallpaper, launchers.
2. Run each test 3 times and keep the middle score. The first run is often lower.
3. Keep HWMonitor open. Above the temperatures in section 8, the hardware slows itself down and the scores drop.
4. Write the scores down with the date and what changed since the last run.

**UserBenchmark:** the raw numbers are usable, the rankings are not. Its graphics test is so light (300 to 400 FPS) that the CPU becomes the limit: a powerful card paired with an older CPU gets a poor ranking without anything being wrong. Its drive percentiles compare system drives busy with Windows against idle ones.

## Not worth it

- **RAM "boosters" and cleaners**: placebo.
- **Defragmenting an SSD**: useless, TRIM handles it.
- **Extreme overclocking without matching cooling**: instability for a marginal gain.
