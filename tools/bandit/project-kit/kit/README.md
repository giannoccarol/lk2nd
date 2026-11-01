# Kit di avvio Android per il Lumia 1520

Catena: UEFI Nokia → bootmgr → BCD (voce "Android (lk1st)") → BootShim → lk1st.
Preparato il 01/11/2026. **BootShim → lk1st → fastboot verificato su RM-937**
con BootShim ARM32 `elf-loader-pre3` e variante `base-0ff`; dettagli e rollback in
[`../BOOTCHAIN-RM937-2026-11-01.md`](../BOOTCHAIN-RM937-2026-11-01.md).
La coppia BootShim → Stage2 già funzionante sul 950 XL è stata provata sul
1520 e termina in Qualcomm 9008; non va considerata compatibile senza altre
verifiche. Il kit usa ora `base-0ff` come default.

## Contenuto

| File | Origine | Verifica |
|---|---|---|
| `bootshim/BootShim.efi` | release `elf-loader-pre3` di imbushuo/boot-shim (2018) | sha256 `21fc9efd…4981`, controllato da `efiesp-prep.sh` |
| `lk1st/base/emmc_appsboot.mbn` | lk2nd `bandit` (`c6967d7b`), come il port KorelisLabs, niente display in lk | `scripts/check-bootshim-elf.py` |
| `lk1st/splash/emmc_appsboot.mbn` | stesso sorgente con `cont-splash` sul framebuffer UEFI | idem, **non provato sul 1520** |
| `lk1st/base-0ff/emmc_appsboot.mbn` | variante `base` ricompilata con `MEMBASE=0x0FF00000` | **fastboot verificato su RM-937**, default |
| `scripts/build-lk1st.sh` | ricompila lk1st in un container Debian | |
| `scripts/bcd-bootshim.py` | legge e modifica il BCD del telefono (hivex) | provato su copie dei BCD del 950 XL |
| `scripts/efiesp-prep.sh` | backup + installazione su EFIESP | |
| `scripts/efiesp-restore.sh` | ripristino file o immagine intera | |
| `scripts/installa-fase1.sh` | sequenza completa della fase 1 | prova a secco su disco finto |
| `scripts/00-backup-telefono.sh`, `01-estrai-firmware.sh`, `03-verifica-lk1st.sh` | passi della fase 1 | idem (03 non provabile senza telefono) |

Gli ELF storici `base` e `splash` hanno l'ingresso a `0x0F900000`, come l'LK del 950 XL.
Il port KorelisLabs scrive `0x0FF00000`: BootShim usa comunque l'indirizzo
dell'ELF. `base-0ff` ha verificato quell'indirizzo sul telefono reale. Il target
bandit nei sorgenti è stato aggiornato: le nuove compilazioni bandit usano
`0x0FF00000` anche senza un override da riga di comando.
Il controllo ELF offline non prova che l'allocazione UEFI a quell'indirizzo
riesca durante il boot.

## Installazione fase 1 (come l'installer del 950 XL, ma da Linux)

Prerequisiti: telefono sbloccato con WPinternals e in mass storage (dopo lo
sblocco si può spostare il cavo dal PC Windows a Linux: il telefono resta in
mass storage fino al riavvio), `hivex`, `zstd`, `fastboot`.

```
lsblk -o NAME,SIZE,PARTLABEL          # trova il disco del telefono, es. /dev/sdb
sudo kit/scripts/installa-fase1.sh /dev/sdb
```

| Passo | Script | Cosa fa | Scrive sul telefono |
|---|---|---|---|
| 1 | `00-backup-telefono.sh` | GPT, ogni partizione < 512 MiB come immagine, immagine completa `zstd`, SHA256 | no |
| 2 | `01-estrai-firmware.sh` | da MainOS/PLAT in sola lettura: `.mbn`, `.acdb`, NV Wi-Fi, ACPI, registro `SYSTEM`/`SOFTWARE`; divide i `.mbn` in `adsp`/`wcnss`/`venus`/`mba`/`modem` `.mdt+.bNN` | no |
| 3 | `efiesp-prep.sh` | prima a vuoto, poi chiede conferma: BootShim, lk1st, voce BCD; backup EFIESP (file + immagine) | solo EFIESP |
| 4 | `03-verifica-lk1st.sh` | aspetta lk1st in fastboot, salva `getvar all` e log di lk1st in `logs/` | no |

Uscite: `backups/telefono-*`, `backups/efiesp-*`, `private/firmware-*`,
`logs/lk1st-*`. Contengono dati del telefono e file Nokia/Microsoft: non vanno
pubblicati. Windows resta intatto e avviabile (con `--windows-key voldown`).

Dal log di lk1st vanno letti `qcom,msm-id` e il device tag, da confermare nel
dts `msm8974-nokia-bandit`.

**Prova a secco del 01/11:** l'intera sequenza (backup, estrazione, EFIESP
a vuoto e reale, ripristino file, ripristino immagine) è stata eseguita su
un disco finto con GPT tipo Lumia (EFIESP, PLAT, DPP, MainOS NTFS, Data),
in un container privilegiato, con `KIT_TEST=1` (abilita i dischi loop).
Tutto passato dopo due correzioni: nomi GPT letti anche senza udev e
percorso del backup reso assoluto nel ripristino.

## Primo kernel

Dopo la fase 1: `fastboot boot kit/k1/boot-k1.img`, procedura in `kit/k1/README.md`.

## Fase 2 (da preparare quando ci sono GPT reale e prima build)

- partizioni Android al posto di Data (e poi MainOS), da Linux in mass storage;
- provisioning come `provision.sh` del 950 XL: `MODEM_FS1/2`, `MODEM_FSG`,
  `SSD` → `modemst1/2`, `fsg`, `ssd`; MAC Wi-Fi/BT da `DPP`;
- recovery: prima quella LineageOS prodotta dalla stessa build, poi TWRP;
- flash di boot/system (o sideload dello zip), come `install-a16-nowipe.sh`.

Opzioni di `efiesp-prep.sh`:
- `--variant splash`: lk con display;
- `--windows-key voldown`: volume giù tenuto all'avvio porta a Windows (al posto del reset);
- `--android-only`: nel menu resta solo Android (dopo la rimozione di Windows).

## Recupero

- **Volume su tenuto premuto all'accensione = modalità flash**: lo script non
  tocca mai quell'azione. Da lì WPinternals o Windows Device Recovery Tool
  possono riscrivere tutto.
- `sudo kit/scripts/efiesp-restore.sh /mnt/efiesp backups/efiesp-<data>`:
  rimette BCD e file originali e li confronta con il manifest.
- `sudo kit/scripts/efiesp-restore.sh --image backups/efiesp-<data> /dev/sdX25`:
  riscrive l'immagine intera della partizione (smontata).

## Equivalente da Windows (se serve)

```
bcdedit /store X:\EFI\Microsoft\Boot\BCD /enum all
```
La voce va creata con lo stesso `device` della voce "Reset My Phone"
(`bcdedit /store … /copy {bd8951c4-eabd-4c6f-aafb-4ddb4eb0469b} /d "Android (lk1st)"`,
poi `/set {id} path \Windows\System32\BOOT\bootshim.efi`, `nointegritychecks on`,
`testsigning on`, `/default {id}`, `/displayorder {id} /addfirst`). Lo script Linux
fa la stessa cosa in modo controllato.

## Crediti

imbushuo (BootShim), msm8916-mainline (lk2nd), KorelisLabs (dts lk1st e
patch indirizzi per il 1520), Markynose (catena BootShim → lk1st sul 930),
Android4Lumia950 (BCD con Boot Shim usato come modello), René Lergner
(WPinternals).
