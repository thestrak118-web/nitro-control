#!/bin/bash
# nitro-control display — tashqi ekran / HDMI avto-boshqaruv + avto-tuzatish
# Universal: GNOME(gdctl) / KDE(kscreen-doctor) / wlroots(wlr-randr) / X11(xrandr).
# Ulangan ekranlarni aniqlaydi, joylashtiradi va drayver muammosini o'zi tuzatadi.
set -euo pipefail

die()  { echo "xato: $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "root kerak: sudo nitro-fan display $*"; }

# --- ichki panelmi? (eDP/LVDS/DSI) ---
is_internal() { case "$1" in eDP*|LVDS*|DSI*|DPI*) return 0 ;; *) return 1 ;; esac; }

# --- /sys/class/drm dan chiqishlar: "conn status card driver" (drayverga bog'liq emas) ---
sys_outputs() {
  local s d base conn card drv
  for s in /sys/class/drm/card*-*/status; do
    [[ -e "$s" ]] || continue
    d=$(dirname "$s"); base=$(basename "$d")   # masalan: card1-HDMI-A-1
    conn=${base#*-}                            # -> HDMI-A-1
    card=${base%%-*}                           # -> card1
    drv=$(basename "$(readlink -f "/sys/class/drm/$card/device/driver" 2>/dev/null)" 2>/dev/null || echo "-")
    printf '%s %s %s %s\n' "$conn" "$(cat "$s")" "$card" "$drv"
  done
}

connected_external() { sys_outputs | while read -r c st _ _; do [[ "$st" == connected ]] && ! is_internal "$c" && echo "$c"; done || true; }
internal_conn()      { { sys_outputs | while read -r c st _ _; do is_internal "$c" && echo "$c"; done | head -1; } || true; }

# --- backend aniqlash ---
detect_backend() {
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    case "${XDG_CURRENT_DESKTOP:-}" in
      *GNOME*) command -v gdctl          >/dev/null 2>&1 && { echo gdctl;   return; } ;;
      *KDE*)   command -v kscreen-doctor >/dev/null 2>&1 && { echo kscreen; return; } ;;
    esac
    command -v wlr-randr      >/dev/null 2>&1 && { echo wlrrandr; return; }
    command -v gdctl          >/dev/null 2>&1 && { echo gdctl;    return; }
    command -v kscreen-doctor >/dev/null 2>&1 && { echo kscreen;  return; }
    echo none; return
  fi
  command -v xrandr >/dev/null 2>&1 && { echo xrandr; return; }
  echo none
}

warn_root_gui() {
  # gdctl/xrandr foydalanuvchi sessiyasida ishlaydi; root+sudo da DBus/Wayland yo'qoladi.
  if [[ $EUID -eq 0 ]]; then
    echo "eslatma: ekran joylashuvini oddiy foydalanuvchi (sudo'siz) sifatida ishga tushiring." >&2
  fi
}

# gdctl ko'rayotgan konnektorlar (compositor haqiqatan ko'rayotganlari)
gd_conn_list() { gdctl show 2>/dev/null | sed -nE 's/.*Monitor ([A-Za-z0-9-]+).*/\1/p'; }
gd_has()       { gd_conn_list | grep -qx "$1"; }

# --------- APPLY (backendga qarab) ---------
apply_layout() {
  # $1=mode: extend|mirror|external|internal   $2=pos (extend uchun: right|left|above|below)
  local mode="$1" pos="${2:-right}"
  local be int ext
  be=$(detect_backend)
  int=$(internal_conn); ext=$(connected_external | head -1)
  [[ "$be" == none ]] && die "monitor boshqaruv tooli topilmadi (gdctl/kscreen-doctor/wlr-randr/xrandr)."

  if [[ "$mode" != internal && -z "$ext" ]]; then
    die "tashqi ekran ulanmagan (HDMI/DP). 'nitro-fan display' bilan tekshiring."
  fi
  [[ -n "$int" ]] || int="$ext"   # ichki panel yo'q bo'lsa tashqisini asos qil

  warn_root_gui
  case "$be" in
    gdctl)
      # tashqi ekran /sys da ulangan, lekin compositor ko'rmasa -> drayver muammosi
      if [[ "$mode" != internal ]] && ! gd_has "$ext"; then
        echo "[!] Tashqi ekran ($ext) ulangan, lekin tizim uni ko'rmayapti."
        echo "    Ehtimol drayver muammosi. Yechim:  sudo nitro-fan display fix"
        exit 1
      fi
      case "$mode" in
        extend)
          local rel; case "$pos" in
            right) rel=--right-of;; left) rel=--left-of;;
            above) rel=--above;;   below) rel=--below;;
            *) rel=--right-of;; esac
          gdctl set -P --logical-monitor --primary --monitor "$int" \
                       --logical-monitor --monitor "$ext" "$rel" "$int"
          ;;
        mirror)   gdctl set -P --logical-monitor --primary --monitor "$int" --monitor "$ext" ;;
        external) gdctl set -P --logical-monitor --primary --monitor "$ext" ;;
        internal) gdctl set -P --logical-monitor --primary --monitor "$int" ;;
      esac
      ;;
    xrandr)
      case "$mode" in
        extend)
          local rel; case "$pos" in
            right) rel=--right-of;; left) rel=--left-of;;
            above) rel=--above;;   below) rel=--below;;
            *) rel=--right-of;; esac
          xrandr --output "$int" --auto --primary --output "$ext" --auto "$rel" "$int"
          ;;
        mirror)   xrandr --output "$ext" --auto --same-as "$int" ;;
        external) xrandr --output "$ext" --auto --primary --output "$int" --off ;;
        internal) xrandr --output "$int" --auto --primary --output "$ext" --off ;;
      esac
      ;;
    kscreen)
      case "$mode" in
        extend)   kscreen-doctor "output.$ext.enable" "output.$ext.position.$([[ $pos == left ]] && echo -1920,0 || echo 1920,0)" "output.$int.enable" ;;
        mirror)   kscreen-doctor "output.$ext.enable" "output.$ext.position.0,0" "output.$int.position.0,0" ;;
        external) kscreen-doctor "output.$ext.enable" "output.$int.disable" ;;
        internal) kscreen-doctor "output.$int.enable" "output.$ext.disable" ;;
      esac
      ;;
    wlrrandr)
      case "$mode" in
        extend)   wlr-randr --output "$int" --on --pos 0,0 --output "$ext" --on --pos 1920,0 ;;
        mirror)   wlr-randr --output "$ext" --on --pos 0,0 ;;
        external) wlr-randr --output "$ext" --on --output "$int" --off ;;
        internal) wlr-randr --output "$int" --on --output "$ext" --off ;;
      esac
      ;;
  esac
  echo "OK: $mode ${ext:+($int + $ext)}"
}

cmd_status() {
  local be; be=$(detect_backend)
  echo "=== Ekran holati ==="
  echo "Sessiya : ${XDG_SESSION_TYPE:-?} / ${XDG_CURRENT_DESKTOP:-?}   backend: $be"
  echo
  printf "%-14s %-12s %-7s %s\n" "KONNEKTOR" "HOLAT" "KARTA" "DRAYVER"
  sys_outputs | while read -r c st card drv; do
    local tag=""; is_internal "$c" && tag="(ichki)"
    printf "%-14s %-12s %-7s %s %s\n" "$c" "$st" "$card" "$drv" "$tag"
  done
  echo
  local ext; ext=$(connected_external | head -1)
  if [[ -n "$ext" ]]; then
    echo "Tashqi ekran ULANGAN: $ext"
    if [[ "$be" == gdctl ]] && ! gd_has "$ext"; then
      echo "  [!] tizim ko'rmayapti -> sudo nitro-fan display fix"
    else
      echo "  nitro-fan display extend   (yoki mirror/external)"
    fi
  else
    echo "Tashqi ekran ulanmagan."
  fi
}

cmd_auto() {
  local ext; ext=$(connected_external | head -1)
  if [[ -n "$ext" ]]; then apply_layout extend right; else apply_layout internal; fi
}

cmd_watch() {
  echo "[watch] real vaqtda kuzatilmoqda... (Ctrl+C to'xtatadi)"
  local prev cur
  prev="$(sys_outputs | awk '{print $1"="$2}' | sort | tr '\n' ',')"
  cmd_auto || true
  while true; do
    sleep 2
    cur="$(sys_outputs | awk '{print $1"="$2}' | sort | tr '\n' ',')"
    if [[ "$cur" != "$prev" ]]; then
      echo "[watch] o'zgarish aniqlandi -> avto qo'llanmoqda"
      cmd_auto || true
      prev="$cur"
    fi
  done
}

cmd_fix() {
  need_root "fix"
  echo "=== display fix — diagnostika ==="
  local gpus has_nv=0 has_amd=0 has_intel=0
  gpus=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)
  grep -qi nvidia <<<"$gpus" && has_nv=1
  grep -qiE 'amd|ati|radeon' <<<"$gpus" && has_amd=1
  grep -qi intel <<<"$gpus" && has_intel=1
  echo "GPU: intel=$has_intel amd=$has_amd nvidia=$has_nv"
  echo
  echo "DRM kartalar / drayverlar:"
  local cdir card drv
  for cdir in /sys/class/drm/card[0-9]; do
    [[ -d "$cdir" ]] || continue
    card=$(basename "$cdir")
    drv=$(basename "$(readlink -f "$cdir/device/driver" 2>/dev/null)" 2>/dev/null || echo "-")
    echo "  $card -> $drv"
  done

  # Tashqi ekran ulangan-u, lekin drayveri yo'q kartadami?
  local ext_line problem_card=""
  ext_line=$(sys_outputs | awk '$2=="connected"' | while read -r c st cc dd; do is_internal "$c" || echo "$c $cc $dd"; done | head -1)
  if [[ -n "$ext_line" ]]; then
    read -r ec ecard edrv <<<"$ext_line"
    echo
    echo "Tashqi ekran: $ec  ($ecard, drayver: $edrv)"
    [[ "$edrv" == "-" ]] && problem_card="$ecard"
  fi

  local fixed=0
  # --- NVIDIA (HDMI ko'pincha NVIDIA'ga ulangan) ---
  if [[ $has_nv -eq 1 ]]; then
    if ! lsmod | grep -q '^nvidia'; then
      echo
      echo "[!] NVIDIA GPU bor, lekin nvidia moduli YUKLANMAGAN."
      if dpkg -l nvidia-driver 2>/dev/null | grep -q '^ii'; then
        echo "[*] nvidia-driver o'rnatilgan -> modul yuklanmoqda..."
        if modprobe nvidia 2>/dev/null && modprobe nvidia_modeset 2>/dev/null && modprobe nvidia_drm modeset=1 2>/dev/null; then
          echo "[+] nvidia moduli yuklandi."; fixed=1
        else
          echo "[x] modprobe muvaffaqiyatsiz. Tekshiring: dmesg | grep -i nvidia"
        fi
      else
        echo "[*] nvidia-driver o'rnatilmagan -> o'rnatilmoqda (apt)..."
        if apt-get update >/dev/null 2>&1 && apt-get install -y nvidia-driver firmware-misc-nonfree >/dev/null 2>&1; then
          echo "[+] O'rnatildi. REBOOT tavsiya etiladi."; fixed=1
        else
          echo "[x] O'rnatish muvaffaqiyatsiz. 'non-free non-free-firmware' repo yoqilganini tekshiring."
        fi
      fi
    else
      echo
      echo "[ok] nvidia moduli yuklangan."
    fi
    # Wayland tashqi ekran uchun nvidia-drm modeset shart
    local ms; ms=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "?")
    if [[ "$ms" != "Y" ]]; then
      echo "[!] nvidia-drm modeset o'chiq ($ms) -> Wayland tashqi ekran uchun yoqilmoqda..."
      echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nitro-control-nvidia-drm.conf
      command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u >/dev/null 2>&1 || true
      echo "[+] Yoqildi -> REBOOT kerak."; fixed=1
    else
      echo "[ok] nvidia-drm modeset=Y"
    fi
  fi

  # --- AMD/Intel: firmware yetishmasligi ---
  if [[ -n "$problem_card" && $has_nv -eq 0 ]]; then
    echo
    echo "[!] $problem_card kartasida drayver bog'lanmagan. firmware o'rnatilmoqda..."
    if apt-get install -y firmware-linux firmware-misc-nonfree >/dev/null 2>&1; then
      echo "[+] firmware o'rnatildi -> REBOOT tavsiya."; fixed=1
    else
      echo "[x] firmware o'rnatilmadi."
    fi
  fi

  # --- hotplugni qayta trigger qilish ---
  udevadm trigger --subsystem-match=drm >/dev/null 2>&1 || true
  echo
  if [[ $fixed -eq 1 ]]; then
    echo "Tuzatishlar qo'llandi. Ba'zilari REBOOT talab qiladi."
  else
    echo "Avtomatik tuzatiladigan muammo topilmadi (yoki hammasi joyida)."
  fi
  echo "Holatni ko'rish:  nitro-fan display"
}

usage() {
  cat <<'EOF'
nitro-fan display — tashqi ekran / HDMI boshqaruvi

  nitro-fan display [status]      Ulangan ekranlar + GPU/drayver
  nitro-fan display extend [pos]  Tashqi ekranni kengaytirish (right|left|above|below)
  nitro-fan display mirror        Ekranni nusxalash (mirror)
  nitro-fan display external      Faqat tashqi ekran
  nitro-fan display internal      Faqat ichki ekran
  nitro-fan display auto          Tashqi bor bo'lsa extend, yo'q bo'lsa ichki
  nitro-fan display watch         Real vaqtda: ulanganda o'zi qo'llaydi
  sudo nitro-fan display fix      Drayver/modul muammosini avto-tuzatish
EOF
}

main() {
  local sub="${1:-status}"; shift || true
  case "$sub" in
    status|st|"")        cmd_status ;;
    extend|ext)          apply_layout extend "${1:-right}" ;;
    mirror|mir)          apply_layout mirror ;;
    external|out)        apply_layout external ;;
    internal|in)         apply_layout internal ;;
    auto|a)              cmd_auto ;;
    watch|w)             cmd_watch ;;
    fix|f)               cmd_fix ;;
    -h|--help|help)      usage ;;
    *)                   usage; die "noma'lum display buyrug'i: $sub" ;;
  esac
}

main "$@"
