#!/bin/bash
# nitro-control smoke tests — sintaksis + kompilyatsiya + asosiy ishlash.
# CI va lokal ishlaydi; hech qanday apparatga bog'liq emas.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
fail=0
ok()   { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }

echo "== bash -n (sintaksis) =="
for f in usr/bin/nitro-fan usr/lib/nitro-control/display.sh usr/lib/nitro-control/hw-detect.sh build-deb.sh tests/smoke.sh; do
  [[ -f "$f" ]] || continue
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
done

echo "== shellcheck (bor bo'lsa) =="
if command -v shellcheck >/dev/null 2>&1; then
  for f in usr/bin/nitro-fan usr/lib/nitro-control/display.sh build-deb.sh; do
    if shellcheck -S error "$f" >/dev/null 2>&1; then ok "$f"; else bad "shellcheck: $f"; fi
  done
else
  echo "  (shellcheck yo'q — o'tkazib yuborildi)"
fi

echo "== python py_compile =="
if python3 -m py_compile usr/bin/nitro-fan-gui 2>/dev/null; then ok "nitro-fan-gui"; else bad "nitro-fan-gui compile"; fi

echo "== VERSION izchilligi =="
ver="$(tr -d ' \t\n\r' < VERSION)"
cver="$(grep -E '^Version:' DEBIAN/control | awk '{print $2}')"
if [[ -n "$ver" && "$ver" == "$cver" ]]; then ok "VERSION=$ver == control"; else bad "VERSION($ver) != control($cver)"; fi

echo "== display.sh asosiy buyruqlar =="
if bash usr/lib/nitro-control/display.sh help >/dev/null 2>&1; then ok "display help"; else bad "display help"; fi
if bash usr/lib/nitro-control/display.sh status >/dev/null 2>&1; then ok "display status"; else bad "display status"; fi

echo
if [[ $fail -eq 0 ]]; then echo "HAMMASI O'TDI ✅"; else echo "XATOLAR BOR ❌"; fi
exit $fail
