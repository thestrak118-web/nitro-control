# Install on any Kali Linux

## 1) From .deb (easiest)

```bash
sudo dpkg -i nitro-control_2.0.0_all.deb
sudo apt-get install -f -y
```

## 2) First-time setup

```bash
nitro-fan probe
```

### If fan is supported

```bash
sudo nitro-fan install-nbfc
sudo nitro-fan enable
nitro-fan-gui
```

### If Acer Nitro / Predator RGB needed

```bash
sudo nitro-fan install-rgb
# may need: reboot
nitro-fan-gui   # open Keyboard RGB tab
```

## 3) From source

```bash
git clone https://github.com/thestrak118-web/nitro-control.git
cd nitro-control
./build-deb.sh
sudo dpkg -i dist/nitro-control_*.deb
```

## Uninstall

```bash
sudo dpkg -r nitro-control
```
