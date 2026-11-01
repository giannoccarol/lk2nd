# LineageOS 18.1 sul Nokia Lumia 1520 ("bandit") — analisi iniziale

Data: 01/11/2026. Stato: **solo analisi**, nessuna operazione sul telefono, nessun
sorgente Android scaricato. Le fonti esterne lette sono clonate in
`external-src/` (solo lettura).

## 1. Sintesi

- **Non esiste un port Android per il 1520.** Né LineageOS né altro: le ricerche
  trovano solo port Linux mainline recenti.
- Esiste però un **port mainline/postmarketOS attivo** (KorelisLabs, kernel
  6.16, ultimo commit 31/10/2026) che ha già risolto la parte più rischiosa:
  catena di avvio senza toccare Windows, display (framebuffer della UEFI),
  touch, eMMC, USB, regolatori, sospensione, ADSP avviato via PAS, sensore
  luce/prossimità. Il fratello **Lumia 930** (stesso SoC e stessa famiglia di
  firmware Windows) ha risolto anche l'**SMP a 4 core** usando le mailbox di
  parcheggio della UEFI originale.
- L'ecosistema **LineageOS 18.1 per MSM8974** è completo e ufficiale: kernel
  3.4 e device tree con branch `lineage-18.1` (Samsung klte/hlte, OnePlus bacon,
  LG G2/G3, Sony shinano) e HAL `hardware/qcom-caf/msm8974` (display, audio,
  media) con branch `lineage-18.1-caf-msm8974`.
- Il lavoro vero è il **kernel**: portare l'hardware del 1520 dentro un kernel
  MSM8974 Android, aggirando la TrustZone di Windows Phone. È lo stesso tipo di
  lavoro fatto sul 950 XL, ma su un SoC più vecchio (ARMv7, kernel 3.4) e senza
  un device tree Android di partenza (sul 950 XL c'era quello talkman).

## 2. Il telefono

| Voce | Valore |
|---|---|
| Codename | `bandit` (pacchetti firmware `Nokia.DEVICE_BANDIT_*`) |
| Varianti | RM-937 (globale), RM-938, RM-939 (Cina), RM-940 (AT&T, l'unica provata dal port mainline) |
| SoC | MSM8974 (Snapdragon 800, non Pro, AB), 4× Krait 400 fino a 2,2 GHz, **ARMv7 a 32 bit** |
| GPU | Adreno 330 |
| RAM / eMMC | 2 GB / 16-32 GB, GPT Windows Phone a 30 partizioni |
| PMIC | PM8941 (+ PM8841), come il Nexus 5 |
| Audio | codec WCD9320 (Taiko) su SLIMbus, come il Nexus 5 e molti MSM8974 Android |
| Wi-Fi/BT | WCNSS/Pronto integrato (WCN3680, 802.11ac) |
| Display | 1080×1920 DSI, framebuffer UEFI vivo a `0x00400000` |
| Touch | Synaptics PLG0175-02, RMI4, `blsp1_i2c2` @ `0x4B`, IRQ GPIO 61, enable GPIO 60 |
| Sensori | APDS-9930 (luce/prossimità) su AP; accelerometro/giroscopio/magnetometro gestiti da Windows tramite ADSP (`qcSensors`), su AP restano 3 dispositivi I²C non identificati |
| Fotocamera | PureView 20 MP + frontale, **nessun lavoro esistente** |
| Avvio | SBL → UEFI Qualcomm/Nokia → Windows Boot Manager. **Nessuna partizione `aboot`** |
| Sblocco | WPinternals (il 1520 è un dispositivo "Spec B" supportato) |

## 3. Catena di avvio (già risolta dalla community)

```
SBL → UEFI Lumia → BootShim (al posto di resetphone.efi su EFIESP)
    → lk1st (lk2nd compilato per un solo dispositivo) → fastboot → kernel
```

- BootShim di imbushuo carica `emmc_appsboot.mbn` (che deve essere l'**ELF**
  `lk_s.elf`) a `0x0FF00000`. Windows resta avviabile.
- lk2nd sovrascrive gli indirizzi del boot.img: la patch del port sposta il
  kernel a `0x10008000` e ramdisk/tags a `0x14000000`/`0x13e00000`, altrimenti
  il kernel sovrascrive il framebuffer a `0x00400000`.
- lk1st avvia boot.img Android standard → **va bene anche per LineageOS**
  (`fastboot boot` per le prove, poi un'immagine fissa su una partizione).
- Diagnostica: `fastboot oem log`, `fastboot oem ramoops console` (pstore a
  `0x30fc0000`), console sul framebuffer.

Da capire per Android: **dove mettere boot, system, vendor, userdata e
recovery** in un GPT Windows. Il port mainline usa sottopartizioni dentro
`Data` (12,9 GB). Per LineageOS servono partizioni vere o immagini; il
ripartizionamento (come sul Nexus 4) è da valutare dopo il backup.

## 4. Le insidie della TrustZone di Windows Phone

Verificate dal port mainline sull'RM-940; vanno rispettate anche dal kernel
Android:

1. **SMP via SCM resetta il SoC** senza log. Mainline e i kernel Android
   MSM8974 avviano i core secondari con `scm_set_boot_addr` + ACC/SAW: sul 1520
   reset immediato. Il port 1520 gira con `nosmp`. **Soluzione del 930**: un
   backend `smp_operations` ARM32 che scrive l'indirizzo di ingresso nelle
   mailbox di parcheggio lasciate dalla UEFI e manda SGI0 al core
   (`kernel/0001-lumia930-uefi-parking-smp.patch`). Verificato con 4 core
   online; niente hotplug né power collapse. È la stessa famiglia di firmware,
   quindi è il candidato principale anche per il 1520 (da provare).
2. **Idle profondo** (power collapse) passa dalla TZ → `cpuidle.off=1`, solo
   WFI. Costa batteria; nel kernel Android vanno disattivati i livelli
   `msm_pm` che chiamano la TZ.
3. **Il PAS funziona**: l'ADSP si avvia con `qcom_scm_pas_auth_and_reset` e
   porta su APR, DIAG, IPCRTR. Quindi PIL/PAS per ADSP, modem e Venus è
   plausibile anche nel kernel Android (che usa le stesse chiamate SCM legacy).
4. **Pronto (Wi-Fi/BT)** va in timeout dopo un PAS riuscito: firmware caricato,
   nessun interrupt `ready`. Causa non trovata (iris/XO, clock, wiring
   dell'IRQ). Sul 950 XL il Wi-Fi si è sbloccato con un reset PCIe e il
   firmware giusto: qui il chip è diverso, ma il metodo (confronto con lo stato
   lasciato da Windows) è lo stesso.
5. `clk_ignore_unused pd_ignore_unused` e regolatori sempre accesi: molto
   hardware vive sullo stato lasciato dalla UEFI. Lo spegnimento dei regolatori
   "inutilizzati" toglie corrente all'eMMC dopo ~30 s.
6. Insidia già risolta, utile da ricordare: un regolatore con min = max blocca
   `set_voltage` per tutti i consumatori (PHY USB in `-EINVAL`).

## 5. Due strade per il kernel

### A. Kernel Android MSM8974 3.4 (consigliata)

Base: un kernel LineageOS 18.1 MSM8974 mantenuto, con i backport per Android 11
già fatti (binder, ecc.). Candidati verificati via GitHub il 01/11:

| Repository LineageOS | Branch | Note |
|---|---|---|
| `android_kernel_samsung_msm8974` | `lineage-18.1` (ultimo commit 07/02/2024) | klte/hlte, ufficiale, il più curato |
| `android_kernel_oppo_msm8974` | `lineage-18.1` | OnePlus One / Find 7 |
| `android_kernel_lge_msm8974`, `android_kernel_lge_g3` | `lineage-18.1` | G2 / G3 |
| `android_kernel_sony_msm8974` | `lineage-18.1` | Xperia Z1/Z2/Z3 |

Più il kernel del Nexus 5 (`hammerhead`, CAF puro, stesso PMIC e codec) come
riferimento di board, anche se LineageOS ufficiale si è fermato a 14.1.

Lavoro:
- device tree `msm8974-bandit` in stile 3.4, partendo dai fatti del port
  mainline (regolatori, touch, pulsanti, sensori, memoria riservata) e dalla
  DSDT di Windows (`PLAT`, `/ACPI/dsdt.aml`);
- backend SMP a mailbox portato dal 930;
- display: MDSS con *continuous splash* sul pannello già acceso dalla UEFI per
  partire; per spegnimento/accensione servono i comandi del pannello, da
  estrarre dalla configurazione Windows (ACPI/driver);
- TZ: disattivare power collapse, SCM non supportate, IOMMU sicuro/contenuti
  protetti; tenere PIL/PAS;
- in cambio si ottengono i driver Android nativi: WCD9320 (`wcd9320`/taiko),
  Pronto (`wcnss`/prima), KGSL per il blob Adreno 330, stack camera
  `msm_camera` v4l2, IPC router/QMI per il RIL.

Vantaggi: HAL, blob e driver Android esistono già e sono quelli che LineageOS
18.1 si aspetta (audio, RIL, camera, GPU). È il percorso del 950 XL.
Rischi: nessun DT di partenza per questo telefono; kernel 3.4 vecchio; SMP e
display da risolvere a mano.

### B. Kernel mainline 6.16 + Android 11 generico

Base: il port KorelisLabs. Userspace Android con Mesa freedreno (Adreno 330 è
supportato), `drm_hwcomposer`, gralloc gbm.

Vantaggi: display, touch, USB, sospensione già funzionanti; kernel moderno.
Contro: niente RIL Android per il modem mainline, niente camera, audio WCD9320
non ancora upstream (KorelisLabs ci sta lavorando), Wi-Fi bloccato,
SimpleDRM senza gestione del pannello. Più adatto a una ROM "tablet" senza
telefonia.

**Proposta:** strada A per la ROM, usando la strada B (il port mainline così
com'è) come banco di prova dell'hardware: estrazione firmware, valori dei
regolatori, verifica che il proprio esemplare si comporti come l'RM-940.

## 6. Userspace LineageOS 18.1

- Prodotto nuovo `bandit` (`device/nokia/bandit`, `vendor/nokia/bandit`),
  costruito su un `msm8974-common` LineageOS 18.1 (Samsung o Oppo).
- HAL: `hardware/qcom-caf/msm8974` (display, audio, media) dal branch
  `lineage-18.1-caf-msm8974`.
- Blob Android: GPU Adreno 330, RIL QMI, camera, sensori, da un dispositivo
  MSM8974 con LineageOS 18.1 (klte/bacon/hammerhead), da scegliere per
  compatibilità con il modem del 1520.
- Firmware specifici del 1520 da `MainOS/Windows/system32`: `qcadsp8974.mbn`,
  `qcwcnss8974.mbn`, modem/DSP (`qcdsp1v28974.mbn`, `qcdsp28974.mbn`),
  `qcvss8974.mbn` (Venus). Da dividere in `.mdt/.bNN` (`tools/pil-split.py` del
  port, oppure il nostro strumento del 950 XL). Come per il cityman, MAC, EFS e
  dati del modem restano sul telefono e non vanno nei repository.
- Sensori: Windows li gestisce dall'ADSP. Su Android MSM8974 i sensori di
  solito stanno sull'AP; da verificare se servono driver I²C o un HAL ADSP.

## 7. Fasi proposte

| Fase | Obiettivo | Uscita |
|---|---|---|
| 0 | Variante RM-93x/94x, versione firmware, sblocco WPinternals, **backup FFU e partizioni**, DSDT e firmware estratti | inventario + hash |
| 1 | BootShim + lk1st, poi `fastboot boot` del pmOS mainline così com'è | hardware confermato sul nostro esemplare |
| 2 | Kernel 3.4 minimo: console sul framebuffer, eMMC, USB adb, 1 core | shell Android minima in RAM |
| 3 | SMP con mailbox, regolatori, touch, pulsanti, batteria | kernel stabile |
| 4 | Layout partizioni + primo build LineageOS 18.1 | avvio alla home |
| 5 | Audio WCD9320, modem/RIL, Wi-Fi/BT | telefono usabile |
| 6 | Pannello (DPMS), GPU, Venus, sensori, camera | rifinitura |

### 7.1 Fase 0 in dettaglio: sblocco e catena bootmgr

**Decisione dell'utente (01/11):** strada A, kernel Android 3.4. Il telefono
**non è ancora sbloccato**.

**Sblocco (serve Windows).** WPinternals esiste solo per Windows: la 2.9.2
stabile è `win-x64.zip`/`win-x86.zip`, i sorgenti 3.0 sono
`net8.0-windows` + WPF. Serve un PC Windows 8 o successivo con porta USB 2.0
(va bene anche un hub). Una VM Windows su Linux con passthrough USB è
possibile, ma durante lo sblocco il telefono cambia identità USB più volte
(modalità normale, flash `0421:*`, EDL Qualcomm `05c6:9008`, mass storage):
se la VM ne perde una a metà del flash si rischia il brick. Meglio un PC vero.

Procedura Spec B (guida lpcwiki/WOA-Project, da riverificare al momento):
1. Prima, su Windows Phone: disattivare la crittografia del dispositivo, se
   presente. Niente aggiornamenti di Windows Phone dopo lo sblocco.
2. WPinternals 2.9.2 → Manual mode → *Switch to Flash mode*.
3. *Unlock bootloader*: selezionare l'FFU del proprio modello, il file
   emergency (uno solo per Spec B, niente SBL3) e un **FFU donatore** se il
   telefono non è nato con Windows 10 Mobile (il 1520 è nato con WP8). Per il
   1520 l'FFU donatore che funziona è un **RM-1085 (Lumia 950 XL) build
   10586**: `RM1085_1078.0053.10586.13169.12547.035242` funziona, la
   `…0017.10586.13053…` è rifiutata (issue WPinternals #39).
4. Nessun altro telefono o FFU montato. Se compare `MainOS` con la richiesta di
   formattare, **non formattare**.
5. Dopo lo sblocco, il backup completo (FFU originale + dump delle partizioni)
   va conservato, come per il 950 XL.

**Catena di avvio: sì, come sul 950 XL, con tre differenze.**

| | 950 XL (fatto il 23/10) | 1520 (da preparare) |
|---|---|---|
| UEFI | Mu-Silicium (già presente per WOA) | UEFI Nokia originale |
| BCD | quello dell'installer Android4Lumia950 copiato in EFIESP | **quello del telefono, modificato**: il BCD del 950 XL punta alle partizioni del 950 XL (elementi device con i GUID delle sue partizioni), non va copiato |
| Catena | BCD → `bootshim.efi` → `Stage2.efi` → LK2ND (poi in `aboot`) | BCD → BootShim → lk1st `bandit` (ELF `emmc_appsboot.mbn` nella root di EFIESP) |
| Accesso a EFIESP | Developer Menu → USB Mass Storage | mass storage di WPinternals (poi fastboot di lk1st) |

Il BCD del 950 XL fa da modello: Boot Shim come voce predefinita
(`{bootmgr}` → `default`, `displayorder` Boot Shim + Mobile Startup, timeout
10 s), `nointegritychecks` e `testsigning` attivi sulla voce Boot Shim.
Il port KorelisLabs invece sostituisce `resetphone.efi`. Funziona, ma
l'avvio di Android passa allora dalla combinazione di tasti del reset.
Proposta: aggiungere una voce "Boot Shim" al BCD del telefono, copiando
l'elemento device della voce `resetphone` già presente, così resta valido
per quel telefono. Lo si può fare con `bcdedit /store` da Windows o con
`hivexregedit --merge` da Linux. Windows Phone resta nel menu.

Da preparare prima dello sblocco (nessun rischio, tutto offline):
- BootShim ARM32 compilato dai sorgenti di imbushuo, con indirizzo di
  caricamento `0x0FF00000`;
- lk1st `msm8974-nokia-bandit` con la patch degli indirizzi;
- script `efiesp-prep` sul modello di `../Android 950 XL/scripts/01-efiesp-prep.sh`:
  backup EFIESP, copia dei file, modifica del BCD letto dal telefono,
  rollback;
- le varianti di `qcom,msm-id` e del device tag da leggere dal log di lk1st
  sul nostro esemplare.

## 7.2 Stato al 01/11 sera: kit, repository, sorgenti

**Aggiornamento sul telefono reale:** RM-937, 32 GB, firmware
2540.19.15053; sblocco `IS_UNLOCKED` confermato, backup delle partizioni
piccole e firmware estratti. Le prove attuali della catena BootShim/lk1st
e il rollback sono in [BOOTCHAIN-RM937-2026-11-01.md](BOOTCHAIN-RM937-2026-11-01.md).
Il launcher a due stadi del 950 XL non ha raggiunto fastboot sul 1520.
**La variante `base-0ff` con BootShim ARM32 originale ha raggiunto fastboot**
(`18d1:d00d`), `product=lk1st-msm8974`; `getvar all` e log LK letti in
`logs/lk1st-20261101-172743/`. K1 non ancora avviato.

**Scelta dell'utente:** come sul 950 XL, Android definitivo (Windows rimosso
dopo l'estrazione di firmware e tabelle ACPI).

**Kernel di base:** `LineageOS/android_kernel_oppo_msm8974` (`lineage-18.1`,
ultimo commit 07/02/2024, OnePlus One/Find 7). Tra i kernel 18.1 MSM8974 è
l'unico con Wi-Fi Pronto/`prima` (come il 1520), oltre a WCD9320 e Synaptics
RMI4. Samsung klte e LG G2 usano Broadcom. Contiene anche i dts
`msm8974-v2.x` non Pro, più vicini al 1520 (MSM8974 AB).

**Repository su GitHub (`giannoccarol`, pubblici):**

| Repository | Tipo | Branch | Contenuto |
|---|---|---|---|
| `android_kernel_nokia_msm8974` | fork di `LineageOS/android_kernel_oppo_msm8974` | `lineage-18.1-bandit` (predefinito) | `lineage_bandit_defconfig` copiato da bacon |
| `lk2nd` | fork di `msm8916-mainline/lk2nd` | `bandit` | target lk1st `msm8974-nokia-bandit` + patch indirizzi |
| `android_device_nokia_bandit` | nuovo | `lineage-18.1` | scheletro: prodotto, BoardConfig, fstab provvisorio, init, libinit; eredita per ora `device/oppo/msm8974-common` |
| `android_vendor_nokia_bandit` | nuovo | `lineage-18.1` | vuoto, per i firmware estratti dal telefono |
| `bandit-manifests` | nuovo | `lineage-18.1` | `lineageos-18.1/bandit_manifest.xml` |

Nessun fork del device tree: il 1520 non ha un albero Android da cui partire,
quindi è nuovo. Eredita `msm8974-common` di LineageOS per avere subito HAL
Wi-Fi/audio/sepolicy funzionanti su Android 11. I pezzi Oppo (libinit, luci,
gesti touch) andranno sostituiti.

**Copie locali** (in `../lumia-1520/`): `kernel/` (worktree del fork),
`src/lk2nd` (branch `bandit`), `device_nokia_bandit/`,
`vendor_nokia_bandit/`, `bandit-manifests/`.

**Sorgenti:** albero LineageOS 18.1 in `los18/`, `repo init --depth=1` +
manifest locale; sync completato il 01/11 (85 GB, log `los18-sync.log`). `lunch lineage_bandit-userdebug` riesce (Android 11, `armv7-a-neon`); nessuna build ancora. Ambiente in
`build-env/`: stessa immagine Docker `los18-build` del cityman A11, container
`bandit18-*`, ccache `~/.cache/ccache-bandit18`.

**Kit di avvio:** `kit/` (vedi `kit/README.md`): BootShim `elf-loader-pre3`,
lk1st `base` e `splash`, script per BCD ed EFIESP con backup e ripristino.
Lo script del BCD conserva sempre l'azione "volume su → modalità flash"
del BCD originale, che resta la via di recupero.

**Installer fase 1** (`kit/scripts/installa-fase1.sh`, da Linux): backup
completo, estrazione di firmware/ACPI/registro da MainOS e PLAT, BootShim +
lk1st + BCD, verifica di lk1st. Non tocca Windows. È stato provato a secco
su un disco finto in container. La fase 2 (partizioni Android, provisioning
modem, recovery, flash) si prepara dopo il primo dump GPT reale e la prima
build.

**Recovery/TWRP:** serve dalla fase 2, non prima. Nella fase 1 il mass
storage di WPinternals e il fastboot di lk1st bastano per backup,
partizionamento (da Linux) e flash. Una recovery diventa necessaria per
sideload, GApps, aggiornamenti senza wipe e script di provisioning con adb
root (come `partition.sh`/`provision.sh` del 950 XL). Ordine proposto: prima
la recovery LineageOS che esce dalla stessa build (stesso kernel, nessun
lavoro extra), poi TWRP 3.7 per Android 11 (cartella `twrp/` nel device
tree come in bacon, manifest minimale `twrp-11`). lk1st permette anche
`fastboot boot recovery.img` in RAM, senza scriverla. Prerequisito comune:
un kernel bandit che arrivi alla shell.

**Da decidere al kernel:** lk2nd forza il kernel a `0x10008000` (patch per
mainline, per non sovrascrivere il framebuffer a `0x00400000`). Un kernel
downstream 3.4 con `PHYS_OFFSET` fisso a 0 si decomprime comunque a
`0x00008000`. Gli effetti sono rumore a schermo durante l'avvio e i
fotogrammi della UEFI persi prima che MDSS riprenda il pannello. In
alternativa si usa `AUTO_ZRELADDR`, che però costa 256 MB di RAM sotto
`0x10000000`.

## 7.3 Kernel bandit, primo giro (01/11 sera)

Branch `lineage-18.1-bandit` del fork, commit `417f45b1`..`ce547d7a`;
compila con la GCC 4.9 di LineageOS (`build-env/build-kernel.sh`), mai
avviato.

**Board:** generica MSM8974 invece di quella Oppo (`MACH_NOKIA_BANDIT` al
posto di `MACH_FIND7OP`). La scheda del 1520 è vicina alla MTP Qualcomm:
touch sullo stesso bus e GPIO 60/61, tasti fotocamera/volume su PM8941
GPIO 3/4/5, volume giù su RESIN. dts: `msm8974-v2.2-bandit.dts` +
`msm8974-bandit/msm8974-bandit.dtsi`.

**Avvio del DTB:** `zImage-dtb` con il solo DTB bandit. lk2nd usa un DTB
appeso unico anche se gli ID non coincidono (`dev_tree.c`, "Only one
appended non-skales DTB"), quindi non servono ancora `msm-id` reali.

**TrustZone di Windows Phone** (`arch/arm/mach-msm/tz-restricted.c`,
attivo con `nokia,bandit` o `msm_tz_restricted=1`):
- `pm-boot.c`: niente `scm_set_boot_addr` per il warm boot, che veniva
  chiamato sempre all'avvio;
- `platsmp.c`: niente `scm_set_boot_addr` per i core secondari, CPU 1-3
  tolte dai presenti;
- `msm-pm.c`: solo WFI (retention e power collapse passano dalla TZ);
- `clock.c`: i clock lasciati accesi dalla UEFI non vengono spenti a fine
  avvio (equivalente di `clk_ignore_unused`);
- `board-8974.c`: senza `regulator_has_full_constraints`, i regolatori senza
  consumatore restano accesi; ram_console a `0x30f80000`, nel layout del
  ramoops di lk2nd (`fastboot oem ramoops console`);
- `board-8974-gpiomux.c`: niente tabelle pin MTP, resta la configurazione
  della UEFI.

**Memoria:** lk1st passa 2 GB piatti; il kernel 3.4 non ha
`reserved-memory`. Il nodo `nokia,bandit-mem-hole` (`qcom,memblock-remove`,
compatibile esportato in `board-8974.c`) toglie `0x08000000`-`0x0ff00000`
(modem, mba, wcnss, adsp, venus, smem, tz, rfsa, rmtfs: stessa mappa del
dtsi mainline, verificata sul 1520 dal port KorelisLabs) e il buffer della
console.

**Aggiornamento, kernel a `0x10008000` (`2de92be9`, `f7f805ea`):** il primo
giro decomprimeva il kernel a `0x8000`. Così avrebbe sovrascritto il
framebuffer UEFI e le pagine di parcheggio dei core 1-3 (`0x00302000`-
`0x00304000` sul 930), dove i core secondari aspettano mentre eseguono
codice del firmware. Ora valgono `PHYS_OFFSET` = `0x10000000` (solo con
`MACH_NOKIA_BANDIT`) e `zreladdr` `0x10008000`, dove lk1st carica il
kernel. È riportato dal mainline il controllo che ignora la RAM sotto
`PHYS_OFFSET` (`arch/arm/kernel/setup.c`). Si perdono circa 128 MB utili
sotto `0x08000000`, ma la console usa direttamente il framebuffer UEFI e le
mailbox restano pronte per l'SMP. Il testo seguente descrive il primo giro.

**Console (primo giro, superato):** backport di `simplefb` (3.10). La GCC 4.9/3.4 decomprime il
kernel a `0x8000` e sovrascrive il framebuffer UEFI a `0x00400000`. Il
driver usa quindi un buffer nuovo a `0x05000000` e scrive il suo indirizzo
nel registro della pipe MDP RGB0 (`0xFD901E14`, dal port mainline), più
due flush dei CTL (`0xFD900618`/`0xFD900718`, dal fork lk2nd del 930). Non
verificato: se il flush non basta, lo schermo resta sporco e si usa la
seriale USB.

**USB:** il connettore è sul controller USB 2.0 `usb@f9a55000` (il port
mainline usa `ci_hdrc` lì), disattivato nel dtsi di base e ora attivo con
VBUS dal PM8941. L24 non dà il problema visto in mainline, perché
`rpm-regulator-smd` concede sempre il cambio di tensione.

**Disattivati per i primi avvii:** MDSS/DSI, GPU (KGSL + OCMEM), Venus,
watchdog, TZ log, QSEECOM, microSD (card detect sconosciuto), USB 3. La
carica resta disattivata (`qcom,charging-disabled`): il telefono va tenuto
carico da Windows o con le prove brevi.

**Driver Oppo tolti dal defconfig:** NFC PN544, LED SN3193, fuel gauge
BQ27541, caricatore BQ24196/Oppo, VOOC, backlight LM3630, touch S3508.
Sostituiti da `QPNP_CHARGER`, `QPNP_BMS` e `TOUCHSCREEN_SYNAPTICS_I2C_RMI4`
(binding `synaptics,rmi4`).

**Device tree Android** (`8deff18`): `BOARD_KERNEL_IMAGE_NAME := zImage-dtb`,
DTB non separato, cmdline con `msm_tz_restricted=1 nosmp maxcpus=1
console=tty0`.

**adb (richiesta dell'utente, `1535064`):** `WITH_ADB_INSECURE := true`
(nessuna richiesta di autorizzazione), `service.adb.root=1` (adbd root
dall'avvio sulla userdebug), `init.qcom.usb.rc` copiato da bacon, SELinux
permissive dalla cmdline. Boot.img con base `0x10000000`, ramdisk
`+0x04000000`, tags `+0x03e00000`.

**Prima build LineageOS:** avviata il 01/11 (`build-env/build-rom.sh`, log
`build-rom-1.log`).

**Immagine di prova:** `kit/k1/boot-k1.img` (sostituisce K0) (kernel + init statico che
scrive a schermo e manda il log del kernel su una seriale USB ACM), solo
`fastboot boot`. Procedura in `kit/k1/README.md`.

**Prossimi passi dopo K0:** `msm-id` reali nel dts lk1st e kernel, poi i
blocchi spenti uno alla volta (watchdog, GPU/OCMEM, PIL con i firmware
estratti), backend SMP con le mailbox UEFI del 930, pannello MDSS (comandi
dalla configurazione Windows), carica con i dati della batteria BV-4BW.

## 8. Domande aperte

1. Quale variante è il telefono (RM-937/938/939/940), con che firmware
   (WP8.1 o W10M)? È disponibile un PC Windows per WPinternals?
2. Windows Phone deve restare avviabile o il telefono può diventare solo
   Android?
3. ~~Strada A o B~~ → **A**, decisa il 01/11.
4. Partizioni: ripartizionare `Data` o usare immagini dentro `Data`?

## 9. Fonti e crediti

- KorelisLabs, [lumia-1520-mainline](https://github.com/KorelisLabs/lumia-1520-mainline)
  (HEAD `04f8972`, 31/10/2026): catena di avvio, DT RM-940, quirk TrustZone,
  firmware, audio WCD9320 in corso. Clonato in `external-src/`.
- Markynose (Mark Buchok), [lumia930-linux](https://github.com/Markynose/lumia930-linux)
  (HEAD `c115f40`, 28/10/2026): SMP con mailbox UEFI, touch, grafica.
  Clonato in `external-src/`.
- imbushuo, [boot-shim](https://github.com/imbushuo/boot-shim).
- msm8916-mainline, [lk2nd](https://github.com/msm8916-mainline/lk2nd).
- René Lergner (HeathCliff), [WPinternals](https://github.com/ReneLergner/WPinternals);
  donatore RM-1085 per il 1520 dalla [issue #39](https://github.com/ReneLergner/WPinternals/issues/39)
  (AkariRiku, joaozittoo).
- Guide di sblocco: [WOA-Project/guides](https://github.com/WOA-Project/guides),
  [Legacy Portable Computing Wiki](https://lpcwiki.miraheze.org/wiki/Lumia_bootloader_unlock_guide).
- Android4Lumia950: installer cityman (BCD con Boot Shim, Stage2, Developer
  Menu) usato come modello per la catena bootmgr.
- [msm8974-mainline](https://github.com/msm8974-mainline/linux), [postmarketOS](https://postmarketos.org).
- [LineageOS](https://github.com/LineageOS): kernel e device MSM8974, HAL
  `qcom-caf/msm8974`, branch `lineage-18.1`.
