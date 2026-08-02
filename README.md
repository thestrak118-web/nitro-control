# nitro-control

**Universal Kali Linux laptop control** — fan, keyboard RGB (Acer gaming), and system monitor (temp / RAM / SSD).

Works on **any Kali** (or Debian) laptop:

| Hardware | Fan (NBFC) | Keyboard RGB | Monitor GUI |
|----------|------------|--------------|-------------|
| Acer Nitro / Predator (supported) | Yes | Yes (facer module) | Yes |
| Other laptop with NBFC config | Yes | No | Yes |
| Any other laptop | No | No | Yes (temp, RAM, SSD) |

Originally built for **Acer Nitro AN515-57**, then generalized for all Kali installs.

---

## Quick install (Kali)

```bash
# Download the .deb from Releases, then:
sudo dpkg -i nitro-control_2.0.0_all.deb
sudo apt-get install -f -y

nitro-fan probe      # detect model & capabilities
nitro-fan-gui        # graphical UI
```

Or build from this repo:

```bash
./build-deb.sh
sudo dpkg -i dist/nitro-control_*.deb
```

---

## Commands

```bash
nitro-fan probe                 # DMI model + fan/RGB support
nitro-fan status                # fans, temps, RAM
nitro-fan-gui                   # GUI (Fan + RGB + alerts)

sudo nitro-fan install-nbfc     # install NoteBook FanControl
sudo nitro-fan enable           # apply matched NBFC config
sudo nitro-fan auto             # temperature auto fan
sudo nitro-fan max              # 100% fans
sudo nitro-fan set 50           # manual %

sudo nitro-fan install-rgb      # Acer Nitro/Predator RGB kernel module
sudo nitro-fan grub             # useful kernel params (Acer)
```

### RGB CLI (after install-rgb)

```bash
nitro-rgb -m 0 -z 1 -b 100 -cR 0 -cG 255 -cB 0   # static green, zone 1
nitro-rgb -m 2 -s 3 -b 100                         # neon effect
```

---

## GUI features

- Live CPU / fan gauges
- Auto / Max / Quiet fan modes
- Keyboard RGB presets + effects (Breath, Neon, Wave, …)
- RAM / Swap / SSD temperature
- Auto fan boost on critical heat or RAM pressure

Menu entry: **Nitro Control**

---

## How detection works

`/usr/lib/nitro-control/hw-detect.sh` reads DMI product name and:

1. Matches an NBFC config under `/usr/share/nbfc/configs/`
2. Detects Acer gaming WMI + `/dev/acer-gkbbl-*` for RGB
3. Falls back to **monitor-only** mode on unsupported hardware

```bash
nitro-fan probe
```

---

## Dependencies

**Package depends:** `systemd`, `python3`, `python3-pyqt5`  

**Recommends:** `curl`, `lm-sensors`, `dmidecode`  

**Optional:**

- [nbfc-linux](https://github.com/nbfc-linux/nbfc-linux) — fan control  
- [acer-predator-turbo-and-rgb-keyboard-linux-module](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module) — Acer RGB (`install-rgb`)

---

## Build

```bash
./build-deb.sh
# → dist/nitro-control_2.0.0_all.deb
```

Prebuilt package also under `releases/`.

---

## Disclaimer

Fan and RGB control talk to low-level EC/WMI interfaces. Use at your own risk.  
RGB module is third-party reverse engineering of Predator Sense — not affiliated with Acer.

---

## License

MIT (this packaging and GUI).  
NBFC and facer modules keep their own licenses.
