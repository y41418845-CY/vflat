import zipfile, struct

with zipfile.ZipFile(r'apks\com.voyagerx.scanner.apk') as z:
    dex = z.read('classes3.dex')

string_ids_off = struct.unpack_from('<I', dex, 0x3c)[0]
type_ids_off = struct.unpack_from('<I', dex, 0x44)[0]
method_ids_off = struct.unpack_from('<I', dex, 0x54)[0]

def get_str(str_idx):
    off = struct.unpack_from('<I', dex, string_ids_off + str_idx * 4)[0]
    l = dex[off]
    return dex[off+1:off+1+l].decode('utf-8', errors='ignore')

def get_type_name(type_idx):
    str_idx = struct.unpack_from('<I', dex, type_ids_off + type_idx * 4)[0]
    return get_str(str_idx)

def get_method_name(method_idx):
    class_idx, proto_idx, name_idx = struct.unpack_from('<HHI', dex, method_ids_off + method_idx * 8)
    return get_type_name(class_idx), get_str(name_idx)

# Let's inspect instructions around 0x4b6c60
cur = 0x4b6c60 - 30
end = 0x4b6c60 + 80

while cur < end:
    opcode = dex[cur]
    if opcode == 0x1a: # const-string
        reg = dex[cur+1]
        s_idx = struct.unpack_from('<H', dex, cur+2)[0]
        print(f"0x{cur:06x}: const-string v{reg}, \"{get_str(s_idx)}\"")
        cur += 4
    elif opcode == 0x1b: # const-string/jumbo
        reg = dex[cur+1]
        s_idx = struct.unpack_from('<I', dex, cur+2)[0]
        print(f"0x{cur:06x}: const-string/jumbo v{reg}, \"{get_str(s_idx)}\"")
        cur += 6
    elif opcode in [0x6e, 0x6f, 0x70, 0x71, 0x72]: # invoke-virtual/super/direct/static/interface
        m_idx = struct.unpack_from('<H', dex, cur+2)[0]
        cl, mn = get_method_name(m_idx)
        print(f"0x{cur:06x}: invoke (op 0x{opcode:02x}) -> {cl}->{mn}")
        cur += 6
    else:
        # advance 2 bytes
        cur += 2
