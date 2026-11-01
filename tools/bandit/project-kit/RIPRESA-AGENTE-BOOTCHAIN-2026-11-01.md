# Ripresa dopo l'installazione di lk1st — 01/11/2026

Il blocco UEFI → bootmgr → BootShim è superato sul **Lumia 1520 RM-937**
(firmware 2540.19.15053, 32 GB). Telefono lasciato collegato in **fastboot**,
USB `18d1:d00d`; `fastboot getvar product` risponde `lk1st-msm8974`.

La catena funzionante è:

```text
UEFI Nokia → bootmgr/BCD del 1520 → BootShim ARM32 elf-loader-pre3
           → emmc_appsboot.mbn a 0x0FF00000 → lk1st fastboot
```

L'ELF compilato a `0x0F900000` non è la variante da reinstallare. La coppia
BootShim + Stage2 del 950 XL è stata provata e terminava in Qualcomm 9008;
è stata sostituita dal BootShim ARM32 originale e Stage2 rimosso. Il BCD e
le azioni volume non sono stati cambiati durante queste prove.

## Dove sono i file

Root locale del progetto: `/home/lorenzo/Documenti/Projects/Jail/lumia-1520`.

| Risorsa | Percorso relativo alla root |
| --- | --- |
| Stato verificato, hash, prove e rollback | `BOOTCHAIN-RM937-2026-11-01.md` |
| Istruzioni operative correnti | `AGENTS.md`, `kit/README.md` |
| BootShim installato | `kit/bootshim/BootShim.efi` |
| lk1st installato, verificato | `kit/lk1st/base-0ff/emmc_appsboot.mbn` |
| SHA-256 dell'ELF | `kit/lk1st/base-0ff/SHA256SUMS` |
| Log reali LK e getvar all | `logs/lk1st-20261101-172743/` |
| Backup prima di questa sessione | `backups/bootchain-20261101-171951/` |
| Backup prima della prova riuscita | `backups/bootchain-20261101-172731-trial2/` |
| Backup Windows originali | `backups/efiesp-20261101-160133/`, `backups/efiesp-20261101-160206/` |
| Kernel K1 già preparato, mai avviato | `kit/k1/boot-k1.img`, `kit/k1/README.md` |
| Sorgenti LK, branch bandit | `src/lk2nd/` |
| Kit e documentazione versionati nel repository LK | `src/lk2nd/tools/bandit/project-kit/` |

L'ELF realmente provato ha SHA-256
`bda72d086d80ea43f529b1ee847465e9a45cc7d4c6873ca0d11bd7bfe093b827`,
compilato da `c6967d7b` con `MEMBASE=0x0FF00000`. Il commit sorgente
`194771c1` rende quell'indirizzo automatico per il DTB bandit. Default del
kit aggiornato a `base-0ff`. Le copie versionate del kit riproducono i file
locali al termine di questa sessione; non sono una seconda installazione.

## Lavoro successivo

Leggere `AGENTS.md`, il report bootchain e `kit/k1/README.md`; il kernel K1
resta **non provato**. Prima di consolidare il boot kernel, verificare il
warning LK sul `qcom,msm-id` di 16 byte (non multiplo di 12) e la selezione
del DTB: modello/compatible nel getvar sono quelli del DTB bundled, non una
misura del tag firmware. Rispettare i vincoli TrustZone già documentati.

Per la prova successiva usare solo `fastboot boot` del K1 e registrare il
risultato reale. Backup e log privati restano locali; non pubblicarli. Nessun
repartizionamento o flash del kernel è stato fatto da questa sessione.

Crediti, repository e commit di BootShim, lk2nd, KorelisLabs,
Android4Lumia950 e WPinternals nel report bootchain e nell'analisi.
