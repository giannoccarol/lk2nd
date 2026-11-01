#!/usr/bin/env bash
# Installa la catena Android sul Lumia 1520 (bandit):
#   UEFI Nokia -> bootmgr -> BCD (voce "Android (lk1st)") -> BootShim -> lk1st
# Telefono in mass storage (WPinternals), EFIESP montata in sola scrittura FAT.
#
# Uso: sudo ./efiesp-prep.sh <mount EFIESP> [--variant base-0ff|base|splash]
#                            [--windows-key voldown] [--android-only] [--dry-run]
#
# Fa sempre un backup completo prima di scrivere (file + immagine della
# partizione se eseguito come root). Ripristino: efiesp-restore.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJ="$(cd "$KIT/.." && pwd)"
BOOTSHIM="$KIT/bootshim/BootShim.efi"
BOOTSHIM_SHA256="21fc9efd2090ece34fe681a513cc87f3590265100412b214128b5a12b3cc4981"  # elf-loader-pre3

die() { echo "ERRORE: $*" >&2; exit 1; }
# Nome GPT di una partizione: udev (lsblk) oppure lettura diretta (blkid -p)
partlabel() { local l; l="$(lsblk -no PARTLABEL "$1" 2>/dev/null | head -1)"; [ -n "$l" ] || l="$(blkid -p -s PART_ENTRY_NAME -o value "$1" 2>/dev/null)"; echo "$l"; }
# Partizione del disco $1 con nome GPT $2
partbylabel() { local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do [ "$(partlabel "$p")" = "$2" ] && { echo "$p"; return; }; done; }

EFIESP=""; VARIANT="base-0ff"; BCD_OPTS=(); DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) VARIANT="$2"; shift 2 ;;
    --windows-key) BCD_OPTS+=(--windows-key "$2"); shift 2 ;;
    --android-only) BCD_OPTS+=(--android-only); shift ;;
    --dry-run) DRY=1; shift ;;
    -*) die "opzione sconosciuta: $1" ;;
    *) EFIESP="$1"; shift ;;
  esac
done
[ -n "$EFIESP" ] || die "uso: $0 <mount EFIESP> [--variant base-0ff|base|splash] [--windows-key voldown] [--android-only] [--dry-run]"
[ -d "$EFIESP" ] || die "$EFIESP non è una cartella"
LK="$KIT/lk1st/$VARIANT/emmc_appsboot.mbn"

# --- controlli sul volume ---
SRC="$(findmnt -rno SOURCE --target "$EFIESP" | head -1)"
FST="$(findmnt -rno FSTYPE --target "$EFIESP" | head -1)"
[ "$(findmnt -rno TARGET --target "$EFIESP" | head -1)" = "$(realpath "$EFIESP")" ] \
  || die "$EFIESP non è un punto di mount"
case "$SRC" in /dev/sd*) ;; /dev/loop*) [ "${KIT_TEST:-}" = 1 ] || die "loop solo con KIT_TEST=1" ;; *) die "$SRC non sembra un disco USB del telefono" ;; esac
[ "$FST" = "vfat" ] || die "filesystem $FST, atteso vfat"
LABEL="$(lsblk -no LABEL "$SRC" 2>/dev/null || true)"
PARTLABEL="$(partlabel "$SRC")"
echo "== EFIESP: $EFIESP ($SRC, label '$LABEL', partlabel '$PARTLABEL')"
[ "$PARTLABEL" = "EFIESP" ] || [ "$LABEL" = "EFIESP" ] || die "la partizione non si chiama EFIESP"

# FAT non distingue maiuscole: cerco i percorsi reali
ci() { find "$EFIESP" -ipath "$EFIESP/$1" -print -quit; }
BCD="$(ci 'efi/microsoft/boot/bcd')"
BOOTDIR="$(ci 'windows/system32/boot')"
[ -n "$BCD" ] || die "BCD non trovato in EFI/Microsoft/Boot"
[ -n "$BOOTDIR" ] || die "Windows/System32/BOOT non trovata"
[ -n "$(ci 'efi/boot/bootarm.efi')" ] || die "bootarm.efi assente: EFIESP inattesa"
echo "   BCD: $BCD"
echo "   BOOT: $BOOTDIR"

# --- controlli sul kit ---
[ -f "$BOOTSHIM" ] || die "manca $BOOTSHIM"
echo "$BOOTSHIM_SHA256  $BOOTSHIM" | sha256sum -c --quiet - || die "hash BootShim inatteso"
[ -f "$LK" ] || die "manca $LK (scripts/build-lk1st.sh $VARIANT)"
python3 -I "$SCRIPT_DIR/check-bootshim-elf.py" "$LK" >/dev/null || die "lk1st non valido per BootShim"
python3 -I -c "import hivex" 2>/dev/null || die "binding Python di hivex assenti (pacman -S hivex)"

# --- backup ---
TS="$(date +%Y%m%d-%H%M%S)"
BK="$PROJ/backups/efiesp-$TS"
echo "== Backup in $BK"
mkdir -p "$BK/EFIESP"
cp -a "$EFIESP/." "$BK/EFIESP/"
(cd "$BK/EFIESP" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$BK/EFIESP.sha256"
if [ "$(id -u)" = 0 ]; then
  dd if="$SRC" of="$BK/efiesp-partition.img" bs=1M status=none
  sha256sum "$BK/efiesp-partition.img" > "$BK/efiesp-partition.img.sha256"
  echo "   immagine partizione: $(du -h "$BK/efiesp-partition.img" | cut -f1)"
else
  echo "   (non root: salto l'immagine della partizione, copiati solo i file)"
fi
REL_BCD="${BCD#"$EFIESP"/}"
REL_BOOT="${BOOTDIR#"$EFIESP"/}"
cat > "$BK/INFO" <<EOF
data=$TS
source=$SRC
variant=$VARIANT
bcd=$REL_BCD
bootdir=$REL_BOOT
had_bootshim=$([ -e "$BOOTDIR/bootshim.efi" ] && echo 1 || echo 0)
had_lk=$([ -n "$(ci 'emmc_appsboot.mbn')" ] && echo 1 || echo 0)
EOF
python3 -I "$SCRIPT_DIR/bcd-bootshim.py" show "$BK/EFIESP/$REL_BCD" > "$BK/BCD-originale.txt"

# --- nuovo BCD, generato dalla copia di backup ---
echo "== Nuovo BCD"
python3 -I "$SCRIPT_DIR/bcd-bootshim.py" add "$BK/EFIESP/$REL_BCD" -o "$BK/BCD.new" "${BCD_OPTS[@]}" \
  | tee "$BK/BCD-nuovo.txt" | sed -n '/^modello/p;/^azione/p;/^tasto/p;/bootmgr:/,$p'
grep -q "1520b007-5e1f-4a1b-9b8e-62616e646974" "$BK/BCD-nuovo.txt" || die "voce Android assente nel nuovo BCD"

if [ "$DRY" = 1 ]; then
  echo "== --dry-run: nessuna scrittura su EFIESP. Backup e BCD.new in $BK"
  exit 0
fi

# --- scrittura ---
echo "== Scrittura su EFIESP"
cp -v "$BOOTSHIM" "$BOOTDIR/bootshim.efi"
cp -v "$LK" "$EFIESP/emmc_appsboot.mbn"
cp -v "$BK/BCD.new" "$BCD"
sync

# --- verifica ---
cmp "$BOOTSHIM" "$BOOTDIR/bootshim.efi"
cmp "$LK" "$EFIESP/emmc_appsboot.mbn"
cmp "$BK/BCD.new" "$BCD"
echo "== Verifica OK"
cat <<EOF

Fatto. Backup: $BK
1) sudo umount '$EFIESP'
2) Riavvia il telefono: deve comparire il testo di BootShim, poi lk1st in fastboot
   (lo schermo resta fermo con la variante base): controlla con 'fastboot devices'.
3) Volume su tenuto premuto all'avvio = modalità flash (recupero con WPinternals).
Ripristino: sudo $SCRIPT_DIR/efiesp-restore.sh '$EFIESP' '$BK'
EOF
