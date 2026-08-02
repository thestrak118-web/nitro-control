#!/bin/bash
# Hardware detection for nitro-control (any Kali / Debian laptop)
# Prints shell-safe KEY='value' assignments (eval-safe).

set -euo pipefail

emit() {
  # shell-escape value for eval
  local k="$1" v="${2-}"
  printf "%s=%q\n" "$k" "$v"
}

dmi() {
  local key="$1"
  if [[ -r "/sys/class/dmi/id/$key" ]]; then
    tr -d '\0' < "/sys/class/dmi/id/$key" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  else
    echo ""
  fi
}

MANUFACTURER="$(dmi sys_vendor)"
PRODUCT="$(dmi product_name)"
VERSION="$(dmi product_version)"
BOARD="$(dmi board_name)"
PRODUCT_NORM="$(echo "$PRODUCT" | sed 's/^Acer //I')"

emit MANUFACTURER "$MANUFACTURER"
emit PRODUCT "$PRODUCT"
emit PRODUCT_NORM "$PRODUCT_NORM"
emit VERSION "$VERSION"
emit BOARD "$BOARD"

NBFC_CONFIG=""
CONFIG_DIR="/usr/share/nbfc/configs"
if [[ -d "$CONFIG_DIR" ]]; then
  for cand in \
    "$PRODUCT" \
    "$PRODUCT_NORM" \
    "Acer $PRODUCT_NORM" \
    "$BOARD"
  do
    [[ -z "$cand" ]] && continue
    if [[ -f "$CONFIG_DIR/${cand}.json" ]]; then
      NBFC_CONFIG="$cand"
      break
    fi
  done
  if [[ -z "$NBFC_CONFIG" && -n "$PRODUCT_NORM" ]]; then
    token="$(echo "$PRODUCT_NORM" | grep -oE 'AN[0-9]+-[0-9]+' | head -1 || true)"
    if [[ -n "$token" ]]; then
      hit="$(find "$CONFIG_DIR" -maxdepth 1 -type f -name "*${token}*.json" 2>/dev/null | head -1 || true)"
      if [[ -n "$hit" ]]; then
        NBFC_CONFIG="$(basename "$hit" .json)"
      fi
    fi
  fi
  if [[ -z "$NBFC_CONFIG" && -n "$PRODUCT_NORM" ]]; then
    words="$(echo "$PRODUCT_NORM" | awk '{print $1" "$2}')"
    if [[ -n "${words// /}" ]]; then
      hit="$(find "$CONFIG_DIR" -maxdepth 1 -type f -iname "*${words}*.json" 2>/dev/null | head -1 || true)"
      if [[ -n "$hit" ]]; then
        NBFC_CONFIG="$(basename "$hit" .json)"
      fi
    fi
  fi
fi

emit NBFC_CONFIG "$NBFC_CONFIG"

if command -v nbfc >/dev/null 2>&1; then
  emit NBFC_INSTALLED 1
else
  emit NBFC_INSTALLED 0
fi

if [[ -n "$NBFC_CONFIG" ]]; then
  emit FAN_SUPPORTED 1
else
  emit FAN_SUPPORTED 0
fi

IS_ACER=0
echo "$MANUFACTURER $PRODUCT" | grep -qi 'acer' && IS_ACER=1
IS_NITRO_PRED=0
echo "$PRODUCT" | grep -qiE 'nitro|predator|helios|triton' && IS_NITRO_PRED=1
RGB_DEV=0
[[ -e /dev/acer-gkbbl-0 ]] && RGB_DEV=1
WMI_RGB=0
if ls /sys/bus/wmi/devices/ 2>/dev/null | grep -qi '7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56'; then
  WMI_RGB=1
fi

emit IS_ACER "$IS_ACER"
emit IS_NITRO_PRED "$IS_NITRO_PRED"
emit RGB_DEV "$RGB_DEV"
emit WMI_RGB "$WMI_RGB"

if [[ $RGB_DEV -eq 1 ]]; then
  emit RGB_SUPPORTED 1
  emit RGB_STATUS ready
elif [[ $IS_ACER -eq 1 && $IS_NITRO_PRED -eq 1 && $WMI_RGB -eq 1 ]]; then
  emit RGB_SUPPORTED 1
  emit RGB_STATUS needs_facer
elif [[ $IS_ACER -eq 1 && $IS_NITRO_PRED -eq 1 ]]; then
  emit RGB_SUPPORTED 0
  emit RGB_STATUS maybe_unsupported
else
  emit RGB_SUPPORTED 0
  emit RGB_STATUS not_acer_gaming
fi

if [[ -n "$NBFC_CONFIG" || $RGB_DEV -eq 1 ]]; then
  emit PROFILE full
elif [[ $IS_ACER -eq 1 ]]; then
  emit PROFILE acer_partial
else
  emit PROFILE monitor_only
fi
