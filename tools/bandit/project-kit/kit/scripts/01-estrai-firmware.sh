#!/usr/bin/env bash
# Estrae dal Lumia 1520 (mass storage) quello che serve ad Android prima di
# cancellare Windows: firmware dei processori ausiliari, calibrazioni audio
# e Wi-Fi, tabelle ACPI, registro di sistema. Monta tutto in sola lettura.
# Uso: sudo ./01-estrai-firmware.sh /dev/sdX
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$SCRIPT_DIR/../.." && pwd)"
PILSPLIT="$PROJ/external-src/lumia-1520-mainline/tools/pil-split.py"
die() { echo "ERRORE: $*" >&2; exit 1; }
# Nome GPT di una partizione: udev (lsblk) oppure lettura diretta (blkid -p)
partlabel() { local l; l="$(lsblk -no PARTLABEL "$1" 2>/dev/null | head -1)"; [ -n "$l" ] || l="$(blkid -p -s PART_ENTRY_NAME -o value "$1" 2>/dev/null)"; echo "$l"; }
# Partizione del disco $1 con nome GPT $2
partbylabel() { local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do [ "$(partlabel "$p")" = "$2" ] && { echo "$p"; return; }; done; }

DEV="${1:-}"
[ -n "$DEV" ] || die "uso: $0 /dev/sdX"
[ "$(id -u)" = 0 ] || die "serve root (sudo)"
[ "$(lsblk -ndo TYPE "$DEV")" = disk ] || [ "${KIT_TEST:-}" = 1 ] || die "$DEV non è un disco intero"
MAINOS="$(partbylabel "$DEV" MainOS)"; PLAT="$(partbylabel "$DEV" PLAT)"
[ -n "$MAINOS" ] && [ -n "$PLAT" ] || die "MainOS o PLAT non trovate"

OUT="$PROJ/private/firmware-$(date +%Y%m%d-%H%M%S)"
MNT="$(mktemp -d)"
mkdir -p "$OUT"/{stock,split,acpi,registro} "$MNT"/{mainos,plat}
cleanup() { umount "$MNT/mainos" "$MNT/plat" 2>/dev/null || true; rmdir "$MNT"/mainos "$MNT"/plat "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

mount -t ntfs3 -o ro "$MAINOS" "$MNT/mainos" 2>/dev/null || mount -t ntfs-3g -o ro "$MAINOS" "$MNT/mainos"
mount -t vfat -o ro "$PLAT" "$MNT/plat"
echo "== MainOS $MAINOS, PLAT $PLAT (sola lettura) -> $OUT"

echo "== PLAT (ACPI e configurazione piattaforma)"
cp -a "$MNT/plat/." "$OUT/acpi/"

echo "== Firmware e calibrazioni da MainOS"
# .mbn: DSP/WCNSS/modem/Venus. .acdb: calibrazione audio. *wlan*/*wcnss*: NV Wi-Fi.
find "$MNT/mainos/Windows" -type f \( -iname '*.mbn' -o -iname '*.acdb' \
     -o -iname '*wlan*' -o -iname '*wcnss*' -o -iname '*.b0[0-9]' -o -iname '*.mdt' \) \
     -not -ipath '*/WinSxS/*' -print0 |
  while IFS= read -r -d '' f; do
    rel="${f#"$MNT/mainos/"}"
    mkdir -p "$OUT/stock/$(dirname "$rel")"
    cp -a "$f" "$OUT/stock/$rel"
  done
(cd "$OUT/stock" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$OUT/stock.sha256"
echo "   $(wc -l < "$OUT/stock.sha256") file"

echo "== Registro (configurazione driver: pannello, touch, audio)"
for h in SYSTEM SOFTWARE; do
  # WP8.1 usa "system32" minuscolo: ricerca senza distinzione di maiuscole
  f="$(find "$MNT/mainos/Windows" -maxdepth 3 -ipath "*/system32/config/$h" -print -quit 2>/dev/null || true)"
  if [ -n "$f" ]; then cp -a "$f" "$OUT/registro/$h"; else echo "   $h non trovato"; fi
done

echo "== Divisione .mbn in .mdt/.bNN (nomi del caricatore PIL Android)"
# Corrispondenza nomi Windows -> PIL msm8974 (da confermare col kernel):
#   qcadsp8974 -> adsp, qcwcnss8974 -> wcnss, qcvss8974 -> venus,
#   qcdsp1v28974 -> mba (modem boot authenticator), qcdsp28974 -> modem
while read -r win pil; do
  f="$(find "$OUT/stock" -iname "$win.mbn" -print -quit)"
  if [ -n "$f" ]; then
    python3 -I "$PILSPLIT" "$f" "$OUT/split" "$pil" >/dev/null && echo "   $win.mbn -> $pil.mdt + .bNN"
  else
    echo "   $win.mbn non trovato"
  fi
done <<'EOF'
qcadsp8974 adsp
qcwcnss8974 wcnss
qcvss8974 venus
qcdsp1v28974 mba
qcdsp28974 modem
EOF
(cd "$OUT/split" && sha256sum * > ../split.sha256) 2>/dev/null || true

[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER:" "$OUT"
echo "== FATTO: $OUT"
echo "Proprietà Nokia/Microsoft e dati del telefono: restano in private/, mai nei repository pubblici."
