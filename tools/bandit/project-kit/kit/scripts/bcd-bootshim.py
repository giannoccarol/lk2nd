#!/usr/bin/env python3
"""Aggiunge al BCD del telefono una voce "Android (lk1st)" che lancia BootShim.

Non copia un BCD da un altro telefono: legge quello del 1520 e prende
l'elemento device (partizione EFIESP) da una voce già presente sulla stessa
partizione (resetphone o Mobile Startup), così i riferimenti restano validi.

Uso:
  bcd-bootshim.py show BCD
  bcd-bootshim.py add  BCD -o BCD.new [--default android|windows]
                       [--timeout N] [--windows-key voldown|none]
                       [--android-only]

"add" non modifica mai il file di ingresso: scrive BCD.new.
Richiede i binding Python di hivex (Arch: pacman -S hivex).
"""
import argparse, shutil, struct, sys
import hivex

BOOTMGR = "{9dea862c-5cdd-4e70-acc1-f32b344d4795}"
# GUID fisso della nostra voce ("bandit" in esadecimale nelle ultime 6 cifre)
ANDROID = "{1520b007-5e1f-4a1b-9b8e-62616e646974}"
BOOTSHIM_PATH = r"\Windows\System32\BOOT\bootshim.efi"
TEMPLATE_PATHS = ("resetphone.efi", "mobilestartup.efi")

# Elementi BCD (tipo esadecimale -> nome) usati qui
E_DEVICE = "11000001"          # ApplicationDevice (binario)
E_PATH = "12000002"            # ApplicationPath (stringa)
E_DESC = "12000004"            # Description (stringa)
E_NOINTEGRITY = "16000048"     # DisableIntegrityChecks (bool)
E_TESTSIGN = "16000049"        # AllowPrereleaseSignatures / testsigning (bool)
E_DEFAULT = "23000003"         # bootmgr: DefaultObject
E_ORDER = "24000001"           # bootmgr: DisplayOrder
E_TIMEOUT = "25000004"         # bootmgr: Timeout
E_CUSTOM_FIRST = "26000028"    # bootmgr: ProcessCustomActionsFirst
E_CUSTOM_LIST = "27000030"     # bootmgr: CustomActionsList
E_CUSTOM_OBJ1 = "54000001"     # bootmgr: oggetti dell'azione 1
E_CUSTOM_OBJ2 = "54000002"     # bootmgr: oggetti dell'azione 2

REG_SZ, REG_BINARY, REG_DWORD, REG_MULTI_SZ = 1, 3, 4, 7

# Scancode dei tasti volume come li usa il bootmgr dei Lumia
# (stesso schema del BCD dell'installer Android4Lumia950: 0x48 su, 0x50 giù)
KEYS = {"volup": 0x48000001, "voldown": 0x50000001}


def sz(s):
    return s.encode("utf-16le") + b"\0\0"


def multi_sz(items):
    return b"".join(sz(i) for i in items) + b"\0\0"


def parse_multi_sz(b):
    return [x for x in b.decode("utf-16le").split("\0") if x]


def parse_actions(b):
    """CustomActionsList: voci da 16 byte (tasto, 0x00010000, elemento 5400000x, 0)."""
    for i in range(0, len(b) - len(b) % 16, 16):
        key, _flags, elem, _zero = struct.unpack_from("<IIII", b, i)
        yield key, elem


def pack_actions(actions):
    return b"".join(struct.pack("<IIII", k, 0x00010000, e, 0) for k, e in actions)


class Bcd:
    def __init__(self, path, write=False):
        self.h = hivex.Hivex(path, write=write)
        self.root = self.h.root()
        self.objects = self.h.node_get_child(self.root, "Objects")
        if not self.objects:
            sys.exit("ERRORE: nodo Objects assente, non è un BCD")

    def obj(self, guid):
        return self.h.node_get_child(self.objects, guid)

    def guids(self):
        return [self.h.node_name(n) for n in self.h.node_children(self.objects)]

    def elements(self, guid):
        o = self.obj(guid)
        el = self.h.node_get_child(o, "Elements") if o else None
        out = {}
        if not el:
            return out
        for n in self.h.node_children(el):
            v = self.h.node_get_value(n, "Element")
            out[self.h.node_name(n).lower()] = self.h.value_value(v)
        return out

    def obj_type(self, guid):
        d = self.h.node_get_child(self.obj(guid), "Description")
        v = self.h.node_get_value(d, "Type") if d else None
        return struct.unpack("<I", self.h.value_value(v)[1][:4])[0] if v else None

    def set_element(self, guid, etype, t, value):
        o = self.obj(guid)
        el = self.h.node_get_child(o, "Elements") or self.h.node_add_child(o, "Elements")
        n = self.h.node_get_child(el, etype) or self.h.node_add_child(el, etype)
        self.h.node_set_value(n, {"key": "Element", "t": t, "value": value})

    def delete_element(self, guid, etype):
        el = self.h.node_get_child(self.obj(guid), "Elements")
        n = self.h.node_get_child(el, etype) if el else None
        if n:
            self.h.node_delete_child(n)

    def new_object(self, guid, otype):
        if self.obj(guid):
            self.h.node_delete_child(self.obj(guid))
        o = self.h.node_add_child(self.objects, guid)
        d = self.h.node_add_child(o, "Description")
        self.h.node_set_value(d, {"key": "Type", "t": REG_DWORD, "value": struct.pack("<I", otype)})
        self.h.node_add_child(o, "Elements")


def describe(bcd, guid):
    els = bcd.elements(guid)
    def s(e):
        return els[e][1].decode("utf-16le").rstrip("\0") if e in els else ""
    return s(E_DESC), s(E_PATH)


def show(path):
    bcd = Bcd(path)
    for g in bcd.guids():
        desc, p = describe(bcd, g)
        t = bcd.obj_type(g)
        print(f"{g} type=0x{t:08x} {desc!r} {p}" if t is not None else f"{g} {desc!r} {p}")
    els = bcd.elements(BOOTMGR)
    if not els:
        print("ATTENZIONE: oggetto bootmgr assente")
        return
    print("\nbootmgr:")
    if E_DEFAULT in els:
        print("  default  ", els[E_DEFAULT][1].decode("utf-16le").rstrip("\0"))
    if E_ORDER in els:
        print("  order    ", parse_multi_sz(els[E_ORDER][1]))
    if E_TIMEOUT in els:
        print("  timeout  ", struct.unpack("<Q", els[E_TIMEOUT][1][:8])[0])
    for e in (E_CUSTOM_FIRST, E_CUSTOM_LIST):
        if e in els:
            print(f"  {e} ", els[e][1].hex())
    for e in (E_CUSTOM_OBJ1, E_CUSTOM_OBJ2):
        if e in els:
            print(f"  {e} ", parse_multi_sz(els[e][1]))


def find_template(bcd):
    """Voce già presente su EFIESP da cui copiare device e tipo."""
    for want in TEMPLATE_PATHS:
        for g in bcd.guids():
            desc, p = describe(bcd, g)
            if p.lower().endswith(want) and E_DEVICE in bcd.elements(g):
                return g, want
    return None, None


def find_windows(bcd):
    for g in bcd.guids():
        if describe(bcd, g)[1].lower().endswith("mobilestartup.efi"):
            return g
    return None


def add(args):
    shutil.copyfile(args.bcd, args.output)
    bcd = Bcd(args.output, write=True)
    if not bcd.obj(BOOTMGR):
        sys.exit("ERRORE: oggetto bootmgr assente")
    tmpl, kind = find_template(bcd)
    if not tmpl:
        sys.exit("ERRORE: nessuna voce resetphone/mobilestartup da cui copiare il device EFIESP")
    win = find_windows(bcd)
    device = bcd.elements(tmpl)[E_DEVICE][1]
    otype = bcd.obj_type(tmpl)
    print(f"modello: {tmpl} ({kind}), tipo 0x{otype:08x}, device {len(device)} byte")
    print(f"Windows (Mobile Startup): {win or 'assente'}")

    bcd.new_object(ANDROID, otype)
    bcd.set_element(ANDROID, E_DEVICE, REG_BINARY, device)
    bcd.set_element(ANDROID, E_PATH, REG_SZ, sz(BOOTSHIM_PATH))
    bcd.set_element(ANDROID, E_DESC, REG_SZ, sz("Android (lk1st)"))
    bcd.set_element(ANDROID, E_NOINTEGRITY, REG_BINARY, b"\x01")
    bcd.set_element(ANDROID, E_TESTSIGN, REG_BINARY, b"\x01")

    old = bcd.elements(BOOTMGR)
    order = parse_multi_sz(old[E_ORDER][1]) if E_ORDER in old else []
    order = [g for g in order if g.lower() != ANDROID]
    if args.android_only:
        order = [ANDROID]
    elif args.default == "android":
        order = [ANDROID] + order
    else:
        order = order + [ANDROID]
    default = ANDROID if args.default == "android" or args.android_only else (win or order[0])
    bcd.set_element(BOOTMGR, E_ORDER, REG_MULTI_SZ, multi_sz(order))
    bcd.set_element(BOOTMGR, E_DEFAULT, REG_SZ, sz(default))
    bcd.set_element(BOOTMGR, E_TIMEOUT, REG_BINARY, struct.pack("<Q", args.timeout))

    # Azioni dei tasti all'avvio. Il BCD originale dei Lumia ha
    # volume su -> FFU Loader (modalità flash) e volume giù -> resetphone.
    # La modalità flash è la via di recupero: non va mai toccata.
    actions = list(parse_actions(old.get(E_CUSTOM_LIST, (0, b""))[1]))
    for key, elem in actions:
        objs = old.get(f"{elem:08x}")
        target = parse_multi_sz(objs[1]) if objs else []
        print(f"azione tasto 0x{key:08x} -> {[describe(bcd, g)[1] or g for g in target]}")
    if args.windows_key != "none" and not args.android_only:
        other = win if default == ANDROID else ANDROID
        key = KEYS[args.windows_key]
        hit = [e for k, e in actions if k == key]
        if hit:
            objs = old.get(f"{hit[0]:08x}")
            target = parse_multi_sz(objs[1]) if objs else []
            if any(describe(bcd, g)[1].lower().endswith("ffuloader.efi") for g in target):
                sys.exit("ERRORE: quel tasto apre la modalità flash, non lo riassegno")
            elem = hit[0]
        else:
            used = {e for _, e in actions}
            elem = next(e for e in range(0x54000001, 0x54000010) if e not in used)
            actions.append((key, elem))
        if other:
            bcd.set_element(BOOTMGR, f"{elem:08x}", REG_MULTI_SZ, multi_sz([other]))
            bcd.set_element(BOOTMGR, E_CUSTOM_LIST, REG_BINARY, pack_actions(actions))
            bcd.set_element(BOOTMGR, E_CUSTOM_FIRST, REG_BINARY, b"\x01")
            print(f"tasto {args.windows_key} all'avvio -> {other} (sostituisce l'azione precedente)")

    bcd.h.commit(args.output)
    print(f"scritto {args.output}\n")
    show(args.output)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show"); s.add_argument("bcd")
    a = sub.add_parser("add")
    a.add_argument("bcd")
    a.add_argument("-o", "--output", required=True)
    a.add_argument("--default", choices=("android", "windows"), default="android")
    a.add_argument("--timeout", type=int, default=0)
    a.add_argument("--windows-key", choices=("voldown", "none"), default="none",
                   help="riassegna volume giù (reset) a Windows; volume su resta la modalità flash")
    a.add_argument("--android-only", action="store_true",
                   help="solo la voce Android nel menu (quando Windows sarà rimosso)")
    args = ap.parse_args()
    if args.cmd == "show":
        show(args.bcd)
    else:
        if args.output == args.bcd:
            sys.exit("ERRORE: l'uscita deve essere un file diverso dall'ingresso")
        add(args)


if __name__ == "__main__":
    main()
