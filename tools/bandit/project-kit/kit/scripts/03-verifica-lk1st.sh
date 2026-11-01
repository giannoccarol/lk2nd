#!/usr/bin/env bash
# Dopo il primo riavvio con BootShim: aspetta lk1st in fastboot e salva i
# dati che servono a completare il dts bandit (msm-id, device tag, cmdline).
# Uso: ./03-verifica-lk1st.sh [secondi di attesa, default 180]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAIT="${1:-180}"
LOG="$PROJ/logs/lk1st-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG"

echo "== Attendo lk1st in fastboot (max ${WAIT}s). Con la variante base lo schermo resta fermo."
for _ in $(seq 1 "$WAIT"); do
  fastboot devices 2>/dev/null | grep -q fastboot && break
  sleep 1
done
fastboot devices | tee "$LOG/devices.txt" | grep -q fastboot || {
  echo "lk1st non risponde. Controlla: testo di BootShim a schermo? cavo USB? lsusb (18d1:d00d)?"
  lsusb > "$LOG/lsusb.txt"; exit 1; }

fastboot getvar all > "$LOG/getvar-all.txt" 2>&1
fastboot oem log >/dev/null 2>&1 && fastboot get_staged "$LOG/lk1st.log" >/dev/null 2>&1
lsusb > "$LOG/lsusb.txt"

echo "== Dati per il dts msm8974-nokia-bandit"
grep -i -h -E "msm-id|platform|board|cmdline|bandit|nokia|SCM|panel|display|lk2nd" \
  "$LOG/lk1st.log" "$LOG/getvar-all.txt" 2>/dev/null | head -40
echo "== Log in $LOG"
