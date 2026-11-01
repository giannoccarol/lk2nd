#!/usr/bin/env bash
# Ripristina EFIESP com'era prima di efiesp-prep.sh.
# Uso: sudo ./efiesp-restore.sh <mount EFIESP> <cartella backup>
#      sudo ./efiesp-restore.sh --image <cartella backup> /dev/sdXN   (immagine intera)
set -euo pipefail
die() { echo "ERRORE: $*" >&2; exit 1; }
# Nome GPT di una partizione: udev (lsblk) oppure lettura diretta (blkid -p)
partlabel() { local l; l="$(lsblk -no PARTLABEL "$1" 2>/dev/null | head -1)"; [ -n "$l" ] || l="$(blkid -p -s PART_ENTRY_NAME -o value "$1" 2>/dev/null)"; echo "$l"; }
# Partizione del disco $1 con nome GPT $2
partbylabel() { local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do [ "$(partlabel "$p")" = "$2" ] && { echo "$p"; return; }; done; }

if [ "${1:-}" = "--image" ]; then
  BK="$(realpath "$2")"; DEV="$3"
  [ -f "$BK/efiesp-partition.img" ] || die "immagine assente in $BK"
  (cd "$BK" && sha256sum -c --quiet efiesp-partition.img.sha256) || die "hash immagine errato"
  case "$DEV" in /dev/sd*) ;; /dev/loop*) [ "${KIT_TEST:-}" = 1 ] || die "loop solo con KIT_TEST=1" ;; *) die "$DEV non sembra un disco USB" ;; esac
  [ "$(partlabel "$DEV")" = "EFIESP" ] || die "$DEV non è EFIESP"
  findmnt -rno TARGET --source "$DEV" >/dev/null && die "$DEV è montata: smontala prima"
  [ "$(blockdev --getsize64 "$DEV")" = "$(stat -c %s "$BK/efiesp-partition.img")" ] || die "dimensione diversa"
  dd if="$BK/efiesp-partition.img" of="$DEV" bs=1M conv=fsync status=progress
  echo "== Immagine EFIESP ripristinata su $DEV"
  exit 0
fi

EFIESP="${1:-}"; BK="${2:-}"
[ -n "$BK" ] && BK="$(realpath "$BK")"
[ -d "$EFIESP" ] && [ -f "$BK/INFO" ] || die "uso: $0 <mount EFIESP> <cartella backup>"
# shellcheck disable=SC1091
. "$BK/INFO"
[ -f "$BK/EFIESP/$bcd" ] || die "BCD di backup assente"

echo "== Ripristino BCD"
cp -v "$BK/EFIESP/$bcd" "$EFIESP/$bcd"
if [ "$had_bootshim" = 0 ]; then rm -fv "$EFIESP/$bootdir/bootshim.efi"
else cp -v "$BK/EFIESP/$bootdir/bootshim.efi" "$EFIESP/$bootdir/bootshim.efi"; fi
LKF="$(find "$EFIESP" -maxdepth 1 -iname emmc_appsboot.mbn -print -quit)"
if [ "$had_lk" = 0 ]; then [ -n "$LKF" ] && rm -fv "$LKF"
else cp -v "$(find "$BK/EFIESP" -maxdepth 1 -iname emmc_appsboot.mbn -print -quit)" "$EFIESP/"; fi
sync

echo "== Verifica con il manifest"
(cd "$EFIESP" && sha256sum -c --quiet "$BK/EFIESP.sha256") && echo "EFIESP identica al backup"
