# Nokia Lumia 1520 ("bandit") — LineageOS 18.1

Progetto avviato il 01/11/2026. RM-937 sbloccato; **BootShim → lk1st → fastboot
verificato** con ingresso LK a `0x0FF00000`. Kernel K1 compilato, non ancora
avviato sul telefono.

- Analisi, piano e stato: `ANALISI-LOS18.1-LUMIA1520-2026-11-01.md`
- Avvio verificato, hash e rollback: `BOOTCHAIN-RM937-2026-11-01.md`
- Kit di avvio (BootShim, lk1st, script BCD/EFIESP): `kit/README.md`
- Note operative: `AGENTS.md`
- `kernel/`, `src/lk2nd`, `device_nokia_bandit/`, `vendor_nokia_bandit/`, `bandit-manifests/`: copie locali dei repository GitHub `giannoccarol`
- `los18/`: albero LineageOS 18.1; `build-env/`: container di build
- `external-src/`: port mainline di riferimento (KorelisLabs 1520, Markynose 930), solo lettura

Crediti nella sezione 9 dell'analisi e nei README dei repository.
