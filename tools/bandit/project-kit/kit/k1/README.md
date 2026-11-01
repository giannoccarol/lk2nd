# K1: primo avvio del kernel bandit (solo RAM)

`boot-k1.img` = kernel `android_kernel_nokia_msm8974` (`lineage-18.1-bandit`)
+ un init statico minimale. Non scrive nulla sul telefono. Preparato il
01/11/2026, **mai avviato**.

Prerequisito: fase 1 fatta (lk1st risponde in fastboot).

## Prova

```
fastboot boot kit/k1/boot-k1.img
```

Cosa dovrebbe succedere, nell'ordine:

1. **Schermo**: il kernel usa come console il framebuffer lasciato dalla
   UEFI (nessun registro del display toccato): lo schermo diventa nero e
   compaiono i messaggi del kernel (font 12x22), poi il blocco
   `==== Lumia 1520 K1 ... ====` e uno stato ogni 5 secondi (uptime, CPU,
   memoria, USB, batteria). Se lo schermo resta fermo sull'ultima immagine,
   il kernel può essere vivo lo stesso: controllare il punto 2.
2. **USB**: il telefono si presenta come `18d1:d00e` "Lumia 1520 K1", seriale
   CDC-ACM. Sul PC:
   ```
   lsusb | grep 18d1
   cat /dev/ttyACM0 | tee logs/k1-$(date +%Y%m%d-%H%M%S).log
   ```
   Arriva il log completo del kernel (e quello del boot precedente, se c'è).
3. **Se si blocca o si riavvia**: tenere premuto accensione circa 12 s
   (reset a caldo, la RAM resta). Al riavvio con lk1st:
   ```
   fastboot oem ramoops console
   fastboot get_staged logs/k1-ramoops.txt
   ```
   Il ram_console del kernel sta dove lk2nd legge il ramoops
   (`0x30fc0000`, 256 KB).

## Cosa contiene il kernel per il 1520

- `msm_tz_restricted`: nessuna chiamata SCM per l'indirizzo di avvio delle
  CPU (un solo core), idle solo WFI, clock e regolatori lasciati accesi
  come li lascia la UEFI, pin della UEFI conservati.
- Memoria: il kernel gira a `0x10008000` (`PHYS_OFFSET` `0x10000000`), dove
  lk1st lo carica. I primi 256 MB restano intatti: framebuffer UEFI
  (`0x00400000`), pagine di parcheggio dei core secondari (`0x00300000`) e
  zone dei firmware. Costa circa 128 MB di RAM durante la messa in funzione.
- Console: `simplefb` sul framebuffer della UEFI a `0x00400000`.
- Disattivati per ora: display MDSS, GPU, video, watchdog, TZ log, QSEECOM,
  microSD, USB 3. Carica batteria disattivata (resta solo la lettura).

Riga di comando: `console=tty0 fbcon=font:SUN12x22 ignore_loglevel nosmp
maxcpus=1 msm_tz_restricted=1 androidboot.hardware=bandit rdinit=/init`.

## Ricostruire

```
build-env/build-kernel.sh        # kernel/out/arch/arm/boot/zImage-dtb
kit/k1/build-k1.sh               # kit/k1/boot-k1.img
```

Il verificatore `check-bootimg.py` di KorelisLabs segnala errori pensati per
il kernel mainline (indirizzo del kernel, nomi dei nodi, framebuffer in
`/chosen`): per questo kernel non valgono, vedi il report §7.3.

## Storia

- K0 (01/11 pomeriggio, mai avviato, rimosso): kernel decompresso a
  `0x8000`, che avrebbe sovrascritto framebuffer e pagine di parcheggio
  delle CPU secondarie; console su un buffer spostato. Sostituito da K1.
