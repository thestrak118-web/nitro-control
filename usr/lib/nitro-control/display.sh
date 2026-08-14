#!/bin/bash
# nitro-control display — tashqi ekran / HDMI avto-boshqaruv + avto-tuzatish
# Universal: GNOME(gdctl) / KDE(kscreen-doctor) / wlroots(wlr-randr) / X11(xrandr).
set -euo pipefail

die()  { echo "xato: $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "root kerak: sudo nitro-fan display $*"; }

CONF="${XDG_CONFIG_HOME:-${HOME:-/root}/.config}/nitro-control/display.conf"

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

# Har doim 0 qaytaradi (set -e ostida while oxirgi test 1 qaytarmasin)
connected_external() { sys_outputs | while read -r c st _ _; do [[ "$st" == connected ]] && ! is_internal "$c" && echo "$c"; done || true; }
internal_conn()      { { sys_outputs | while read -r c st _ _; do is_internal "$c" && echo "$c"; done | head -1; } || true; }

# Konnektorning afzal (preferred) rejim kengligi/balandligi — qattiq kodlangan 1920 o'rniga
mode_width()  { local c="$1" w=1920 m first; for m in /sys/class/drm/card*-"$c"/modes; do [[ -r "$m" ]] || continue; read -r first < "$m" || true; [[ "$first" =~ ^([0-9]+)x[0-9]+ ]] && w="${BASH_REMATCH[1]}"; break; done; echo "$w"; }
mode_height() { local c="$1" h=1080 m first; for m in /sys/class/drm/card*-"$c"/modes; do [[ -r "$m" ]] || continue; read -r first < "$m" || true; [[ "$first" =~ ^[0-9]+x([0-9]+) ]] && h="${BASH_REMATCH[1]}"; break; done; echo "$h"; }

# --- afzal rejim (watch/auto shuni ishlatadi; foydalanuvchi tanlovini bosib ketmaslik uchun) ---
PREF_MODE=extend; PREF_POS=right
load_pref() {
  [[ -r "$CONF" ]] || return 0
  local v
  v=$(grep -E '^PREF_MODE=' "$CONF" 2>/dev/null | tail -1 | cut -d= -f2); [[ -n "$v" ]] && PREF_MODE="$v"
  v=$(grep -E '^PREF_POS='  "$CONF" 2>/dev/null | tail -1 | cut -d= -f2); [[ -n "$v" ]] && PREF_POS="$v"
  return 0
}
save_pref() {
  mkdir -p "$(dirname "$CONF")" 2>/dev/null || true
  printf 'PREF_MODE=%s\nPREF_POS=%s\n' "$1" "$2" > "$CONF" 2>/dev/null || true
}

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
  [[ $EUID -eq 0 ]] && echo "eslatma: ekran joylashuvini oddiy foydalanuvchi (sudo'siz) sifatida ishga tushiring." >&2 || true
}

# gdctl ko'rayotgan konnektorlar
gd_conn_list() { gdctl show 2>/dev/null | sed -nE 's/.*Monitor ([A-Za-z0-9-]+).*/\1/p'; }
gd_has()       { gd_conn_list | grep -qx "$1"; }
# /sys nomi gdctl'da boshqacha atalsa ham topib beradi (masalan HDMI-A-1 -> HDMI-1)
gd_resolve() {
  local want="$1" t
  if gd_has "$want"; then echo "$want"; return; fi
  case "$want" in HDMI*) t=HDMI ;; DP*) t=DP ;; eDP*) t=eDP ;; *) t="${want%%-*}" ;; esac
  gd_conn_list | grep -iE "^${t}" | head -1
}

# --------- APPLY (backendga qarab) ---------
apply_layout() {
  # $1=mode: extend|mirror|external|internal   $2=pos (extend uchun)
  local mode="$1" pos="${2:-right}"
  local be int; be=$(detect_backend)
  [[ "$be" == none ]] && die "monitor boshqaruv tooli topilmadi (gdctl/kscreen-doctor/wlr-randr/xrandr)."
  int=$(internal_conn)

  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  if [[ "$mode" != internal && ${#EXTS[@]} -eq 0 ]]; then
    die "tashqi ekran ulanmagan (HDMI/DP). 'nitro-fan display' bilan tekshiring."
  fi
  [[ -n "$int" ]] || int="${EXTS[0]:-}"   # ichki panel yo'q bo'lsa tashqisini asos qil

  warn_root_gui
  case "$be" in
    gdctl)      _apply_gdctl "$mode" "$pos" "$int" ;;
    xrandr)     _apply_xrandr "$mode" "$pos" "$int" ;;
    kscreen)    _apply_kscreen "$mode" "$pos" "$int" ;;
    wlrrandr)   _apply_wlrrandr "$mode" "$pos" "$int" ;;
  esac
  echo "OK: $mode (${int:-?}${EXTS:+ + ${EXTS[*]}})"
}

_rel_flag() { case "$1" in left) echo --left-of;; above) echo --above;; below) echo --below;; *) echo --right-of;; esac; }

_apply_gdctl() {
  local mode="$1" pos="$2" int="$3" rel; rel=$(_rel_flag "$pos")
  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  # tashqilarni compositor ko'radigan nomga aylantirish
  local -a GEXTS=(); local e ge
  for e in "${EXTS[@]}"; do ge=$(gd_resolve "$e"); [[ -n "$ge" ]] && GEXTS+=("$ge") || {
      echo "[!] Tashqi ekran ($e) ulangan, lekin tizim ko'rmayapti — drayver muammosi."
      echo "    Yechim:  sudo nitro-fan display fix"
      exit 1; }
  done
  local gint; gint=$(gd_resolve "$int"); [[ -n "$gint" ]] || gint="$int"
  local -a args=(set -P)
  case "$mode" in
    internal)  args+=(--logical-monitor --primary --monitor "$gint") ;;
    external)  args+=(--logical-monitor --primary --monitor "${GEXTS[0]}") ;;
    mirror)    args+=(--logical-monitor --primary --monitor "$gint"); for ge in "${GEXTS[@]}"; do args+=(--monitor "$ge"); done ;;
    extend)
      args+=(--logical-monitor --primary --monitor "$gint")
      local prev="$gint"
      for ge in "${GEXTS[@]}"; do args+=(--logical-monitor --monitor "$ge" "$rel" "$prev"); prev="$ge"; done
      ;;
  esac
  gdctl "${args[@]}"
}

_apply_xrandr() {
  local mode="$1" pos="$2" int="$3" rel; rel=$(_rel_flag "$pos")
  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  case "$mode" in
    internal)  xrandr --output "$int" --auto --primary; for e in "${EXTS[@]}"; do xrandr --output "$e" --off; done ;;
    external)  xrandr --output "${EXTS[0]}" --auto --primary; xrandr --output "$int" --off ;;
    mirror)    for e in "${EXTS[@]}"; do xrandr --output "$e" --auto --same-as "$int"; done ;;
    extend)
      xrandr --output "$int" --auto --primary
      local prev="$int"
      for e in "${EXTS[@]}"; do xrandr --output "$e" --auto "$rel" "$prev"; prev="$e"; done ;;
  esac
}

_apply_kscreen() {
  local mode="$1" pos="$2" int="$3"
  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  local iw ih; iw=$(mode_width "$int"); ih=$(mode_height "$int")
  case "$mode" in
    internal)  kscreen-doctor "output.$int.enable"; for e in "${EXTS[@]}"; do kscreen-doctor "output.$e.disable"; done ;;
    external)  kscreen-doctor "output.${EXTS[0]}.enable" "output.$int.disable" ;;
    mirror)    for e in "${EXTS[@]}"; do kscreen-doctor "output.$e.enable" "output.$e.position.0,0"; done; kscreen-doctor "output.$int.position.0,0" ;;
    extend)
      kscreen-doctor "output.$int.enable" "output.$int.position.0,0"
      local x="$iw" y=0; case "$pos" in left) x=-"$iw"; y=0;; above) x=0; y=-"$ih";; below) x=0; y="$ih";; esac
      for e in "${EXTS[@]}"; do kscreen-doctor "output.$e.enable" "output.$e.position.$x,$y"; x=$((x + $(mode_width "$e"))); done ;;
  esac
}

_apply_wlrrandr() {
  local mode="$1" pos="$2" int="$3"
  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  local iw ih; iw=$(mode_width "$int"); ih=$(mode_height "$int")
  case "$mode" in
    internal)  wlr-randr --output "$int" --on; for e in "${EXTS[@]}"; do wlr-randr --output "$e" --off; done ;;
    external)  wlr-randr --output "${EXTS[0]}" --on --output "$int" --off ;;
    mirror)    wlr-randr --output "${EXTS[0]}" --on --pos 0,0 ;;
    extend)
      wlr-randr --output "$int" --on --pos 0,0
      local x="$iw" y=0; case "$pos" in left) x=-"$iw"; y=0;; above) x=0; y=-"$ih";; below) x=0; y="$ih";; esac
      for e in "${EXTS[@]}"; do wlr-randr --output "$e" --on --pos "$x,$y"; x=$((x + $(mode_width "$e"))); done ;;
  esac
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
  local -a EXTS=(); mapfile -t EXTS < <(connected_external)
  if [[ ${#EXTS[@]} -gt 0 ]]; then
    echo "Tashqi ekran ULANGAN: ${EXTS[*]}"
    if [[ "$be" == gdctl ]] && ! gd_has "$(gd_resolve "${EXTS[0]}")" 2>/dev/null; then
      echo "  [!] tizim ko'rmayapti -> sudo nitro-fan display fix"
    else
      echo "  nitro-fan display extend   (yoki mirror/external)"
    fi
  else
    echo "Tashqi ekran ulanmagan."
  fi
  load_pref; echo "Afzal rejim: $PREF_MODE / $PREF_POS"
}

cmd_auto() {
  load_pref
  if [[ -n "$(connected_external | head -1)" ]]; then apply_layout "$PREF_MODE" "$PREF_POS"; else apply_layout internal; fi
}

cmd_pref() {
  local m="${1:-}" p="${2:-right}"
  if [[ -z "$m" ]]; then load_pref; echo "Afzal rejim: $PREF_MODE / $PREF_POS"; return; fi
  case "$m" in extend|mirror|external|internal) ;; *) die "rejim: extend|mirror|external|internal" ;; esac
  save_pref "$m" "$p"; echo "Saqlandi: $m $p"
}

cmd_watch() {
  load_pref
  echo "[watch] real vaqtda kuzatilmoqda (afzal: $PREF_MODE/$PREF_POS). Ctrl+C to'xtatadi."
  # boshlanishda joriy holatni buzmaymiz — faqat o'zgarishga javob beramiz
  local prev cur
  prev="$(sys_outputs | awk '{print $1"="$2}' | sort | tr '\n' ',')"
  while true; do
    sleep 2
    cur="$(sys_outputs | awk '{print $1"="$2}' | sort | tr '\n' ',')"
    if [[ "$cur" != "$prev" ]]; then
      echo "[watch] o'zgarish -> qo'llanmoqda"
      if [[ -n "$(connected_external | head -1)" ]]; then
        apply_layout "$PREF_MODE" "$PREF_POS" || true
      else
        apply_layout internal || true
      fi
      prev="$cur"
    fi
  done
}

# NVIDIA PRIME / quvvat holati (HDMI ko'pincha NVIDIA'da — dGPU o'chiq bo'lsa yonmaydi)
_report_prime() {
  local nv_pci rs; nv_pci=$(lspci -D 2>/dev/null | awk '/NVIDIA/{print $1; exit}')
  [[ -n "$nv_pci" ]] || return 0
  rs=$(cat "/sys/bus/pci/devices/$nv_pci/power/runtime_status" 2>/dev/null || echo "?")
  echo "NVIDIA PCI: $nv_pci  runtime: $rs"
  if command -v prime-select >/dev/null 2>&1; then
    echo "PRIME rejim: $(prime-select query 2>/dev/null || echo '?')"
  fi
  if [[ "$rs" == suspended ]]; then
    echo "[!] dGPU uxlab yotibdi — HDMI (NVIDIA) yonmasligi mumkin."
    echo "    'nvidia-smi' bilan uyg'otishga urinilyapti..."
    nvidia-smi -L >/dev/null 2>&1 || true
    echo "    Doimiy yechim: dGPU'ni 'on' rejimga (masalan supergfxctl/prime-select nvidia) yoki tashqi ekranni ichki GPU portiga (DP) ulang."
  fi
}

cmd_fix() {
  need_root "fix"
  local allow_install=0
  case "${1:-}" in --yes|-y|apply) allow_install=1 ;; esac

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

  local ext_line problem_card=""
  ext_line=$(sys_outputs | awk '$2=="connected"' | while read -r c st cc dd; do is_internal "$c" || echo "$c $cc $dd"; done | head -1)
  if [[ -n "$ext_line" ]]; then
    read -r ec ecard edrv <<<"$ext_line"
    echo; echo "Tashqi ekran: $ec  ($ecard, drayver: $edrv)"
    [[ "$edrv" == "-" ]] && problem_card="$ecard"
  fi

  local fixed=0 need_install=""
  if [[ $has_nv -eq 1 ]]; then
    if ! lsmod | grep -q '^nvidia'; then
      echo; echo "[!] NVIDIA GPU bor, lekin nvidia moduli YUKLANMAGAN."
      if dpkg -l nvidia-driver 2>/dev/null | grep -q '^ii'; then
        echo "[*] nvidia-driver o'rnatilgan -> modul yuklanmoqda..."
        if modprobe nvidia 2>/dev/null && modprobe nvidia_modeset 2>/dev/null && modprobe nvidia_drm modeset=1 2>/dev/null; then
          echo "[+] nvidia moduli yuklandi."; fixed=1
        else
          echo "[x] modprobe muvaffaqiyatsiz. Tekshiring: dmesg | grep -i nvidia"
        fi
      else
        need_install="nvidia-driver firmware-misc-nonfree"
      fi
    else
      echo; echo "[ok] nvidia moduli yuklangan."
    fi
    local ms; ms=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "?")
    if [[ "$ms" != "Y" && -e /sys/module/nvidia_drm ]]; then
      echo "[!] nvidia-drm modeset o'chiq ($ms) -> Wayland tashqi ekran uchun yoqilmoqda..."
      echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nitro-control-nvidia-drm.conf
      command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u >/dev/null 2>&1 || true
      echo "[+] Yoqildi -> REBOOT kerak."; fixed=1
    fi
    echo; _report_prime
  fi

  if [[ -n "$problem_card" && $has_nv -eq 0 ]]; then
    need_install="${need_install:+$need_install }firmware-linux firmware-misc-nonfree"
  fi

  # Paket o'rnatish — POTENTIAL BUZUVCHI amal. Ochiq ko'rsatamiz, faqat --yes bilan bajaramiz.
  if [[ -n "$need_install" ]]; then
    echo
    if [[ $allow_install -eq 1 ]]; then
      echo "[*] Paket o'rnatilmoqda (tasdiqlangan): $need_install"
      if apt-get update >/dev/null 2>&1 && apt-get install -y $need_install >/dev/null 2>&1; then
        echo "[+] O'rnatildi. REBOOT tavsiya etiladi."; fixed=1
      else
        echo "[x] O'rnatish muvaffaqiyatsiz. 'non-free non-free-firmware' repo yoqilganini tekshiring:"
        echo "    /etc/apt/sources.list ichida 'contrib non-free non-free-firmware' bo'lsin."
      fi
    else
      echo "[!] Kerakli paket(lar) o'rnatilmagan: $need_install"
      echo "    Bu tizimni o'zgartiruvchi amal — avtomatik o'rnatilmadi."
      echo "    O'rnatish uchun:  sudo nitro-fan display fix --yes"
    fi
  fi

  udevadm trigger --subsystem-match=drm >/dev/null 2>&1 || true
  echo
  if [[ $fixed -eq 1 ]]; then
    echo "Tuzatishlar qo'llandi. Ba'zilari REBOOT talab qiladi."
  elif [[ -n "$need_install" && $allow_install -eq 0 ]]; then
    echo "Tasdiq kutilmoqda — 'fix --yes' bilan paketlarni o'rnating."
  else
    echo "Avtomatik tuzatiladigan muammo topilmadi (yoki hammasi joyida)."
  fi
  echo "Holatni ko'rish:  nitro-fan display"
}

usage() {
  cat <<'EOF'
nitro-fan display — tashqi ekran / HDMI boshqaruvi

  nitro-fan display [status]      Ulangan ekranlar + GPU/drayver
  nitro-fan display extend [pos]  Kengaytirish (right|left|above|below)
  nitro-fan display mirror        Ekranni nusxalash
  nitro-fan display external      Faqat tashqi ekran
  nitro-fan display internal      Faqat ichki ekran
  nitro-fan display auto          Afzal rejim (tashqi bor bo'lsa), aks holda ichki
  nitro-fan display watch         Real vaqtda: ulanganda afzal rejimni qo'llaydi
  nitro-fan display pref M [pos]  Afzal rejimni saqlash (extend/mirror/...)
  sudo nitro-fan display fix       Drayver muammosini diagnostika + xavfsiz tuzatish
  sudo nitro-fan display fix --yes Paket o'rnatishga ham ruxsat berish
EOF
}

main() {
  local sub="${1:-status}"; shift || true
  case "$sub" in
    status|st|"")        cmd_status ;;
    extend|ext)          apply_layout extend "${1:-right}"; save_pref extend "${1:-right}" ;;
    mirror|mir)          apply_layout mirror; save_pref mirror right ;;
    external|out)        apply_layout external ;;
    internal|in)         apply_layout internal ;;
    auto|a)              cmd_auto ;;
    watch|w)             cmd_watch ;;
    pref)                cmd_pref "${1:-}" "${2:-right}" ;;
    fix|f)               cmd_fix "${1:-}" ;;
    -h|--help|help)      usage ;;
    *)                   usage; die "noma'lum display buyrug'i: $sub" ;;
  esac
}

main "$@"
