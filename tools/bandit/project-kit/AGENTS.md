# Lumia 1520 / bandit

- Obiettivo: LineageOS 18.1 sul Nokia Lumia 1520 (MSM8974, ARMv7), **Android definitivo come sul 950 XL** (scelta dell'utente, 01/11/2026). Strada A: kernel Android 3.4.
- Leggere prima `ANALISI-LOS18.1-LUMIA1520-2026-11-01.md` (§4 insidie TrustZone, §7.1 sblocco/bootmgr, §7.2 stato) e `kit/README.md`.
- Repository GitHub `giannoccarol`: `android_kernel_nokia_msm8974` (`lineage-18.1-bandit`, fork del kernel oppo_msm8974 di LineageOS), `lk2nd` (`bandit`), `android_device_nokia_bandit`, `android_vendor_nokia_bandit`, `bandit-manifests` (tutti `lineage-18.1`). Copie locali in questa cartella.
- Albero `los18/`, ambiente `build-env/` (`run.sh`, `sync.sh`), immagine `los18-build`, container `bandit18-*`. Mai usare i container `los18-*`/`los23-*` del cityman.
- Telefono: RM-937, 32 GB, firmware 2540.19.15053, sbloccato (`IS_UNLOCKED` verificato in mass storage). **BootShim → lk1st → fastboot funzionante il 01/11**: BootShim ARM32 `elf-loader-pre3` e `kit/lk1st/base-0ff/emmc_appsboot.mbn` con ingresso `0x0FF00000`; default del kit aggiornati. Il launcher BootShim + Stage2 del 950 XL termina invece in Qualcomm 9008 sul 1520. Report e rollback in `BOOTCHAIN-RM937-2026-11-01.md`; log verificati in `logs/lk1st-20261101-172743/`. K1 non ancora avviato. WPinternals da Windows serve per il mass storage; il telefono attualmente è accessibile via fastboot.
- Prima di cancellare MainOS/Data: estrarre firmware (`qcadsp8974.mbn`, `qcwcnss8974.mbn`, modem, Venus) e ACPI (`PLAT/ACPI/dsdt.aml`) e fare il backup completo.
- Kernel: `kernel/` (branch `lineage-18.1-bandit`), build con `build-env/build-kernel.sh`; prova in RAM `kit/k1/boot-k1.img` (report §7.3). La protezione TrustZone è in `arch/arm/mach-msm/tz-restricted.c`: non reintrodurre `scm_set_boot_addr` né power collapse sul 1520.
- Recupero: volume su all'accensione = modalità flash. Gli script BCD non devono mai togliere questa azione.
- Prove sul telefono: preferire `fastboot boot`; backup e hash prima di ogni scrittura; registrare risultati e rollback nel report.
- Crediti nei README e report (KorelisLabs, Markynose, imbushuo, lk2nd, WPinternals, LineageOS, TheMuppets, Android4Lumia950); mai nei commit. Nessuna attribuzione AI.
