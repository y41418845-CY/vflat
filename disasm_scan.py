import capstone

elf_path = r'h:\我的雲端硬碟\工具程式\vflat\apks\extracted_arm64\lib\arm64-v8a\libnative-scan.so'

with open(elf_path, 'rb') as f:
    elf_data = f.read()

# Parse ELF64 headers to map virtual address to file offset
# e_shoff is at 0x28, e_shentsize at 0x3a, e_shnum at 0x3c, e_shstrndx at 0x3e
import struct

e_shoff = struct.unpack_from('<Q', elf_data, 0x28)[0]
e_shentsize = struct.unpack_from('<H', elf_data, 0x3a)[0]
e_shnum = struct.unpack_from('<H', elf_data, 0x3c)[0]
e_shstrndx = struct.unpack_from('<H', elf_data, 0x3e)[0]

sections = []
for i in range(e_shnum):
    offset = e_shoff + i * e_shentsize
    sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize = struct.unpack_from('<IIQQQQIIQQ', elf_data, offset)
    sections.append({
        'name_idx': sh_name,
        'addr': sh_addr,
        'offset': sh_offset,
        'size': sh_size
    })

shstrtab = sections[e_shstrndx]
shstr_data = elf_data[shstrtab['offset']:shstrtab['offset']+shstrtab['size']]

def get_sh_name(idx):
    end = shstr_data.find(b'\x00', idx)
    return shstr_data[idx:end].decode('ascii', errors='ignore')

for s in sections:
    s['name'] = get_sh_name(s['name_idx'])

def vaddr_to_offset(vaddr):
    for s in sections:
        if s['addr'] <= vaddr < s['addr'] + s['size']:
            return s['offset'] + (vaddr - s['addr'])
    return None

targets = [
    (0x1afec, 88, 'Java_com_voyagerx_vflat_scan_Scan_otr'),
    (0x1af6c, 32, 'Java_com_voyagerx_vflat_scan_Scan_dof'),
    (0x1a9b0, 432, 'Java_com_voyagerx_vflat_scan_Scan_btf'),
    (0x1c1a8, 148, '_ZN8freeform5model11deobfuscateEPf'),
    (0x1cf0c, 144, '_ZN4pptp18fillPositionBufferEPf'),
    (0x1ae4c, 96, 'Java_com_voyagerx_vflat_scan_Scan_calcFreeformOutputSize'),
]

cs = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)

for vaddr, size, name in targets:
    print("=" * 80)
    print(f"DISASSEMBLY OF {name} @ 0x{vaddr:x} (size: {size} bytes)")
    print("=" * 80)
    foff = vaddr_to_offset(vaddr)
    if foff is None:
        print(f"ERROR: Cannot map virtual address 0x{vaddr:x} to file offset")
        continue
    code = elf_data[foff:foff+size]
    for ins in cs.disasm(code, vaddr):
        print(f"  0x{ins.address:06x}:  {ins.mnemonic:<8} {ins.op_str}")
    print()
