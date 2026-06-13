import sys, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

WOW = r"C:\Users\KIRA\Desktop\world of warcraft 3.3.5a hd\wow.exe"
DATA = open(WOW, "rb").read()

# --- PE parse ---
pe = struct.unpack_from("<I", DATA, 0x3C)[0]
assert DATA[pe:pe+4] == b"PE\0\0"
nsec = struct.unpack_from("<H", DATA, pe+6)[0]
opt = pe + 24
image_base = struct.unpack_from("<I", DATA, opt+28)[0]
sohdr = pe + 24 + struct.unpack_from("<H", DATA, pe+20)[0]
secs = []
for i in range(nsec):
    o = sohdr + i*40
    name = DATA[o:o+8].rstrip(b"\0").decode("latin1")
    vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", DATA, o+8)
    secs.append((name, vaddr, vsize, raddr, rsize))

def va2off(va):
    r = va - image_base
    for name, vaddr, vsize, raddr, rsize in secs:
        if vaddr <= r < vaddr + max(vsize, rsize):
            return raddr + (r - vaddr)
    return None

def off2va(off):
    for name, vaddr, vsize, raddr, rsize in secs:
        if raddr <= off < raddr + rsize:
            return image_base + vaddr + (off - raddr)
    return None

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.detail = True

def disasm(va, n=80, stop_ret=True):
    off = va2off(va)
    if off is None:
        print("  <va not in image>"); return
    code = DATA[off:off+ n*8]
    cnt = 0
    for ins in md.disasm(code, va):
        tgt = ""
        if ins.mnemonic in ("call", "jmp") and ins.operands and ins.operands[0].type == 1:  # imm? actually type
            pass
        print("  %08X  %-10s %s" % (ins.address, ins.mnemonic, ins.op_str))
        cnt += 1
        if stop_ret and ins.mnemonic.startswith("ret"):
            break
        if cnt >= n:
            break

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "d":
        va = int(sys.argv[2], 16)
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 80
        print("== disasm %08X ==" % va)
        disasm(va, n)
    elif cmd == "str":
        # find an ascii string, print its VA(s)
        needle = sys.argv[2].encode("latin1")
        start = 0
        hits = 0
        while True:
            i = DATA.find(needle, start)
            if i < 0: break
            va = off2va(i)
            print("  off=%08X va=%s  %r" % (i, ("%08X"%va) if va else "?", DATA[i:i+40]))
            start = i + 1
            hits += 1
            if hits > 30: break
    elif cmd == "xref":
        # find absolute 4-byte immediate references to a VA (push imm32 / mov reg,imm32 / cmp [imm])
        target = int(sys.argv[2], 16)
        tb = struct.pack("<I", target)
        start = 0
        hits = 0
        while True:
            i = DATA.find(tb, start)
            if i < 0: break
            va = off2va(i)
            if va:
                print("  ref-at va=%08X off=%08X  ctx=%s" % (va, i, DATA[i-2:i+4].hex()))
                hits += 1
            start = i + 1
            if hits > 60: break
    elif cmd == "call":
        # find E8 relative callers of target VA
        target = int(sys.argv[2], 16)
        hits = 0
        for name, vaddr, vsize, raddr, rsize in secs:
            if name != ".text": continue
            base = image_base + vaddr
            seg = DATA[raddr:raddr+rsize]
            for k in range(len(seg)-5):
                if seg[k] == 0xE8:
                    rel = struct.unpack_from("<i", seg, k+1)[0]
                    src = base + k
                    if src + 5 + rel == target:
                        print("  call from %08X" % src)
                        hits += 1
                        if hits > 60: break
    elif cmd == "fn":
        # Disassemble a function window; report ret-imm values and all call targets,
        # and whether it (directly) calls GetSpellVisualRow 0x7FA290.
        va = int(sys.argv[2], 16)
        leaf = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x7FA290
        off = va2off(va)
        code = DATA[off:off+1200]
        rets = []
        calls = []
        callsLeaf = False
        end = None
        for ins in md.disasm(code, va):
            if ins.mnemonic == "ret":
                rets.append(ins.op_str.strip() or "0")
            if ins.mnemonic in ("call", "jmp"):
                op = ins.operands[0] if ins.operands else None
                if op is not None and op.type == 2:  # CS_OP_IMM
                    t = op.imm & 0xFFFFFFFF
                    calls.append((ins.mnemonic, t))
                    if t == leaf:
                        callsLeaf = True
            # stop after we pass the first ret AND we've gone a bit (functions can have early rets)
            if ins.mnemonic == "ret" and end is None:
                end = ins.address
        firstret = rets[0] if rets else "?"
        leafcalls = [hex(t) for m,t in calls if t == leaf]
        print("  %08X  firstRet=ret %s  callsLeaf(%05X)=%s  rets=%s" % (
            va, firstret, leaf, callsLeaf, sorted(set(rets))))
    elif cmd == "scan_desc":
        # Register-aware: find `mov R, [B+8]` (descriptor-array load) then a read of
        # [R + 0x38] (summonedBy) — the unit owner-field access pattern. Report the
        # function-ish start (nearest preceding push ebp) and which owner offsets appear.
        from capstone.x86 import X86_OP_REG, X86_OP_MEM
        results = []
        for name, vaddr, vsize, raddr, rsize in secs:
            if name != ".text": continue
            base = image_base + vaddr
            seg = DATA[raddr:raddr+rsize]
            insns = list(md.disasm(seg, base))
            # map: reg currently holding a descriptor base, and the addr it was set
            for i, ins in enumerate(insns):
                # detect mov R, [B + 8]
                if ins.mnemonic == "mov" and len(ins.operands) == 2:
                    dst, src = ins.operands
                    if dst.type == X86_OP_REG and src.type == X86_OP_MEM and src.mem.disp == 8 and src.mem.base != 0:
                        descreg = dst.reg
                        # scan forward up to 30 insns for reads of [descreg + 0x30/0x38/0x40]
                        offs = set()
                        GP = ("mov","cmp","or","test","push","lea","and","add","xor","sub")
                        for j in range(i+1, min(i+30, len(insns))):
                            nj = insns[j]
                            if nj.mnemonic not in GP:
                                continue
                            for k, op in enumerate(nj.operands):
                                # only SOURCE reads (for mov, operand[1]); exclude FP/stores
                                if nj.mnemonic == "mov" and k == 0:
                                    continue
                                if op.type == X86_OP_MEM and op.mem.base == descreg and op.mem.disp in (0x30,0x34,0x38,0x3C,0x40,0x44):
                                    offs.add(op.mem.disp)
                            # crude reassignment check
                            if nj.mnemonic == "mov" and nj.operands and nj.operands[0].type==X86_OP_REG and nj.operands[0].reg==descreg:
                                src2 = nj.operands[1] if len(nj.operands)>1 else None
                                if not (src2 and src2.type==X86_OP_MEM and src2.mem.base==descreg):
                                    break
                        if 0x38 in offs and (0x40 in offs or 0x30 in offs):
                            results.append((ins.address, tuple(sorted(offs))))
        seen=set()
        for a,offs in results:
            if a in seen: continue
            seen.add(a)
            print("  %08X  owner-field reads: %s" % (a, [hex(o) for o in offs]))
        print("total:", len(seen))
    elif cmd == "scan_kitlist":
        # Find .text functions that reference BOTH disp 0xA8 (kit-list head) and 0x108
        # (kit-node next) — the kit-list walkers (apply-insert, per-frame update/GC, clear).
        from capstone.x86 import X86_OP_MEM
        funcs = {}
        cur = None
        for name, vaddr, vsize, raddr, rsize in secs:
            if name != ".text": continue
            base = image_base + vaddr
            seg = DATA[raddr:raddr+rsize]
            for ins in md.disasm(seg, base):
                # track function starts (push ebp; mov ebp,esp)
                if ins.mnemonic == "push" and ins.op_str == "ebp":
                    cur = ins.address
                if cur is None: continue
                for op in ins.operands:
                    if op.type == X86_OP_MEM and op.mem.disp in (0xA8, 0x108):
                        d = funcs.setdefault(cur, set())
                        d.add(op.mem.disp)
        hits = [f for f, s in funcs.items() if 0xA8 in s and 0x108 in s]
        for f in sorted(hits):
            print("  func %08X references +0xA8 and +0x108" % f)
        print("total:", len(hits))
    elif cmd == "scan_owner":
        # Find .text functions that read descriptor displacements 0x38 (summonedBy) and
        # 0x40 (createdBy) and/or 0x30 (charmedBy) close together — the owner-resolution
        # pattern (CGUnit_C::GetCharmerOrOwnerGUID and friends).
        import struct as _s
        want = set()
        for name, vaddr, vsize, raddr, rsize in secs:
            if name != ".text": continue
            base = image_base + vaddr
            seg = DATA[raddr:raddr+rsize]
            hits38 = []
            # collect instruction addresses that reference disp 0x38 / 0x40 / 0x30
            d = {0x30: [], 0x38: [], 0x40: []}
            for ins in md.disasm(seg, base):
                for op in ins.operands:
                    if op.type == 3:  # mem
                        disp = op.mem.disp
                        if disp in d:
                            d[disp].append(ins.address)
            # window match: a 0x38 within 64 bytes of a 0x40
            for a in d[0x38]:
                near40 = any(abs(a-b) < 64 for b in d[0x40])
                near30 = any(abs(a-b) < 96 for b in d[0x30])
                if near40:
                    want.add((a, near30))
            print("=== %s: %d sites where [reg+0x38] near [reg+0x40] ===" % (name, len(want)))
            for a, n30 in sorted(want):
                print("  %08X  (also 0x30 nearby=%s)" % (a, n30))
    elif cmd == "info":
        print("image_base %08X" % image_base)
        for s in secs:
            print("  %-8s va=%08X vsz=%08X raw=%08X rsz=%08X" % (s[0], image_base+s[1], s[2], s[3], s[4]))
