import zipfile, struct

with zipfile.ZipFile(r'apks\com.voyagerx.scanner.apk') as z:
    dex = z.read('classes3.dex')

string_ids_off = struct.unpack_from('<I', dex, 0x3c)[0]
type_ids_off = struct.unpack_from('<I', dex, 0x44)[0]
method_ids_off = struct.unpack_from('<I', dex, 0x54)[0]
class_defs_size = struct.unpack_from('<I', dex, 0x60)[0]
class_defs_off = struct.unpack_from('<I', dex, 0x64)[0]

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

def read_uleb128(data, off):
    res = 0
    shift = 0
    while True:
        b = data[off]
        off += 1
        res |= (b & 0x7f) << shift
        if (b & 0x80) == 0:
            break
        shift += 7
    return res, off

target_off = 0x4b6c60

for i in range(class_defs_size):
    c_off = class_defs_off + i * 32
    class_idx, access_flags, super_idx, interfaces_off, source_file_idx, annotations_off, class_data_off, static_values_off = struct.unpack_from('<IIIIIIII', dex, c_off)
    if class_data_off == 0:
        continue
    cname = get_type_name(class_idx)
    
    off = class_data_off
    static_fields_size, off = read_uleb128(dex, off)
    instance_fields_size, off = read_uleb128(dex, off)
    direct_methods_size, off = read_uleb128(dex, off)
    virtual_methods_size, off = read_uleb128(dex, off)
    
    # skip fields
    for _ in range(static_fields_size + instance_fields_size):
        _, off = read_uleb128(dex, off)
        _, off = read_uleb128(dex, off)
        
    last_idx = 0
    for _ in range(direct_methods_size + virtual_methods_size):
        m_diff, off = read_uleb128(dex, off)
        access, off = read_uleb128(dex, off)
        code_off, off = read_uleb128(dex, off)
        last_idx += m_diff
        
        if code_off > 0:
            # code_item header: registers_size (2), ins_size (2), outs_size (2), tries_size (2), debug_info_off (4), insns_size (4)
            insns_size = struct.unpack_from('<I', dex, code_off + 12)[0]
            insns_start = code_off + 16
            insns_end = insns_start + insns_size * 2
            if insns_start <= target_off < insns_end:
                cl, mname = get_method_name(last_idx)
                print(f"[FOUND!] Target 0x{target_off:x} is inside:")
                print(f"Class: {cl}")
                print(f"Method: {mname}")
                exit(0)
