#!/usr/bin/env bash
# Backup del Lumia 1520 in mass storage (WPinternals): tabella GPT, ogni
# partizione piccola come immagine separata, immagine completa compressa.
# Non scrive nulla sul telefono.
# Uso: sudo ./00-backup-telefono.sh /dev/sdX [--no-full]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/../.." && pwd)"
die() { echo "ERRORE: $*" >&2; exit 1; }
# Nome GPT di una partizione: udev (lsblk) oppure lettura diretta (blkid -p)
partlabel() { local l; l="$(lsblk -no PARTLABEL "$1" 2>/dev/null | head -1)"; [ -n "$l" ] || l="$(blkid -p -s PART_ENTRY_NAME -o value "$1" 2>/dev/null)"; echo "$l"; }
# Partizione del disco $1 con nome GPT $2
partbylabel() { local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do [ "$(partlabel "$p")" = "$2" ] && { echo "$p"; return; }; done; }

DEV="${1:-}"; FULL=1
[ "${2:-}" = "--no-full" ] && FULL=0
[ -n "$DEV" ] || die "uso: $0 /dev/sdX [--no-full]  (disco intero del telefono)"
[ "$(id -u)" = 0 ] || die "serve root (sudo)"
[ -b "$DEV" ] || die "$DEV non è un block device"
[ "$(lsblk -ndo TYPE "$DEV")" = disk ] || [ "${KIT_TEST:-}" = 1 ] || die "$DEV non è un disco intero"
case "$DEV" in /dev/sd*) ;; /dev/loop*) [ "${KIT_TEST:-}" = 1 ] || die "loop solo con KIT_TEST=1" ;; *) die "$DEV non sembra un disco USB" ;; esac

LABELS="$(for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do partlabel "$p"; done)"
for need in EFIESP MainOS PLAT DPP; do
  grep -qx "$need" <<<"$LABELS" || die "partizione $need assente: non sembra un Lumia in mass storage"
done

lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL "$DEV"
echo "Dimensione: $(( $(blockdev --getsize64 "$DEV") / 1024 / 1024 )) MiB"
read -rp "È il disco del Lumia 1520? Scrivi 'si': " ok
[ "$ok" = si ] || { echo annullato; exit 1; }
for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
  findmnt -rno TARGET --source "$p" >/dev/null && die "$p è montata: smonta tutto prima del backup"
done

BK="$PROJ/backups/telefono-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK/partizioni"
echo "== Backup in $BK"

lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,PARTUUID "$DEV" > "$BK/lsblk.txt"
for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do echo "$p $(partlabel "$p")"; done > "$BK/partlabel.txt"
sfdisk --dump "$DEV" > "$BK/gpt-sfdisk.txt"
SECT=$(blockdev --getss "$DEV"); TOT=$(blockdev --getsz "$DEV")
dd if="$DEV" of="$BK/gpt-primaria.bin" bs="$SECT" count=34 status=none
dd if="$DEV" of="$BK/gpt-secondaria.bin" bs="$SECT" skip=$((TOT - 33)) count=33 status=none

# Partizioni sotto 512 MiB una per una: servono a confronto e provisioning
# (DPP, MODEM_FS1/2, MODEM_FSG, SSD, PLAT, EFIESP, UEFI, TZ, RPM, SBL...).
echo "== Partizioni piccole"
for name in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
  size="$(blockdev --getsize64 "$name")"; label="$(partlabel "$name")"
  [ -n "$label" ] || label="$(basename "$name")"
  if [ "$size" -lt $((512 * 1024 * 1024)) ]; then
    dd if="$name" of="$BK/partizioni/$label.img" bs=1M status=none
    printf '  %-16s %8s KiB\n' "$label" $((size / 1024))
  else
    printf '  %-16s %8s MiB (solo nell immagine completa)\n' "$label" $((size / 1024 / 1024))
  fi
done

if [ "$FULL" = 1 ]; then
  echo "== Immagine completa (zstd), può richiedere 20-60 minuti"
  dd if="$DEV" bs=8M status=progress | zstd -T0 -3 -q -o "$BK/lumia1520-full.img.zst"
  zstd -t -q "$BK/lumia1520-full.img.zst"
fi

(cd "$BK" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER:" "$BK"
echo "== FATTO: $BK"
echo "Contiene dati personali e del modem (DPP, MODEM_FS*): non pubblicarlo."
