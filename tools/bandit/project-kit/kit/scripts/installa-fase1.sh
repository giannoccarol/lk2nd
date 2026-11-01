#!/usr/bin/env bash
# Installazione fase 1 sul Lumia 1520, già sbloccato con WPinternals e in
# mass storage. Non cancella nulla di Windows:
#   1. backup completo (00-backup-telefono.sh)
#   2. estrazione firmware/ACPI/registro (01-estrai-firmware.sh)
#   3. BootShim + lk1st + voce BCD su EFIESP (efiesp-prep.sh, prima a vuoto)
#   4. riavvio e verifica di lk1st in fastboot (03-verifica-lk1st.sh)
# La fase 2 (partizioni Android al posto di Data/MainOS, provisioning modem,
# flash della ROM) arriva quando ci sono il dump GPT e la prima build.
# Uso: sudo ./installa-fase1.sh /dev/sdX [--variant base-0ff|base|splash] [--no-full]
set -euo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "ERRORE: $*" >&2; exit 1; }
# Nome GPT di una partizione: udev (lsblk) oppure lettura diretta (blkid -p)
partlabel() { local l; l="$(lsblk -no PARTLABEL "$1" 2>/dev/null | head -1)"; [ -n "$l" ] || l="$(blkid -p -s PART_ENTRY_NAME -o value "$1" 2>/dev/null)"; echo "$l"; }
# Partizione del disco $1 con nome GPT $2
partbylabel() { local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do [ "$(partlabel "$p")" = "$2" ] && { echo "$p"; return; }; done; }
ask() { read -rp "$1 Scrivi 'si': " a; [ "$a" = si ] || { echo "interrotto"; exit 1; }; }

DEV="${1:-}"; shift || true
VARIANT=base-0ff; NOFULL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) VARIANT="$2"; shift 2 ;;
    --no-full) NOFULL="--no-full"; shift ;;
    *) die "opzione sconosciuta: $1" ;;
  esac
done
[ -n "$DEV" ] || die "uso: $0 /dev/sdX [--variant base-0ff|base|splash] [--no-full]"
[ "$(id -u)" = 0 ] || die "serve root (sudo)"

echo "######## 1/4 backup"
"$S/00-backup-telefono.sh" "$DEV" $NOFULL

echo "######## 2/4 estrazione firmware"
"$S/01-estrai-firmware.sh" "$DEV"

echo "######## 3/4 EFIESP"
EFI="$(partbylabel "$DEV" EFIESP)"
[ -n "$EFI" ] || die "EFIESP non trovata"
MNT="$(mktemp -d)"
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
mount -t vfat "$EFI" "$MNT"
"$S/efiesp-prep.sh" "$MNT" --variant "$VARIANT" --dry-run
ask "Il nuovo BCD sopra va bene? Procedo con la scrittura su EFIESP."
"$S/efiesp-prep.sh" "$MNT" --variant "$VARIANT"
sync; umount "$MNT"

echo "######## 4/4 riavvio"
cat <<'EOF'
Ora riavvia il telefono: esci dal mass storage da WPinternals oppure tieni
premuto accensione + volume giù per circa 10 s finché vibra.
Deve comparire il testo di BootShim, poi lk1st (fastboot).
Se qualcosa va storto: volume su tenuto premuto all'accensione = modalità flash.
EOF
read -rp "Premi Invio quando il telefono si sta riavviando... " _
"$S/03-verifica-lk1st.sh" 240
