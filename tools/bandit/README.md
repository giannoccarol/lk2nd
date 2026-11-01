# Lumia 1520 project kit

This directory preserves the local project kit and its verified RM-937 boot
configuration. The project workspace is `/home/lorenzo/Documenti/Projects/Jail/lumia-1520`;
this repository is its `src/lk2nd` checkout on branch `bandit`.

Start with `project-kit/RIPRESA-AGENTE-BOOTCHAIN-2026-11-01.md` and
`project-kit/BOOTCHAIN-RM937-2026-11-01.md`. BootShim ARM32 `elf-loader-pre3`
plus the bundled `base-0ff` payload reached fastboot on the real RM-937.
The tested ELF is built from `c6967d7b` with `MEMBASE=0x0FF00000`; source
commit `194771c1` selects that address automatically for bandit. The ELF's
SHA-256 is `bda72d086d80ea43f529b1ee847465e9a45cc7d4c6873ca0d11bd7bfe093b827`.

`project-kit/` mirrors the workspace layout for documentation, scripts,
build environment and the tested bootloader payload. Run the scripts from
the actual workspace, where `src/lk2nd`, the kernel and ROM checkouts exist.
To restore the kit elsewhere, copy `project-kit/.` into the project root
containing those checkouts. The package does not include the untested K1
kernel binary, the Android source tree or the failed two-stage EFI payloads.

Backups, firmware/calibration extractions and raw device logs remain private
in the workspace and are intentionally absent here. The bootchain report
records their local paths. Windows/MainOS/Data and GPT were not changed.

Credits and upstream commits are recorded in the bootchain report and the
analysis. The original BootShim license and copyright notice accompany its
binary under `project-kit/kit/bootshim/third-party-license/`; its source is
imbushuo/boot-shim at `10ab44add00b7c8614fdaa27415f4bc41328aa6f`.
