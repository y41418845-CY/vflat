import struct

with open(r'assets\models\optp_v3_3.dat', 'rb') as f:
    buf = f.read()

root_table_offset = 28
vtable_offset = 8

# Subgraphs field is at vtable offset 10 (field 2)
sub_off = struct.unpack_from('<H', buf, vtable_offset + 8)[0]
pos = root_table_offset + sub_off
vec_off = pos + struct.unpack_from('<I', buf, pos)[0]
# first subgraph
table_loc = vec_off + 4
subgraph_pos = table_loc + struct.unpack_from('<I', buf, table_loc)[0]

v_diff = struct.unpack_from('<i', buf, subgraph_pos)[0]
v_off = subgraph_pos - v_diff
v_size = struct.unpack_from('<H', buf, v_off)[0]

# SubGraph fields:
# 0: tensors (vector of Tensor)
# 1: inputs (vector of int)
# 2: outputs (vector of int)
# 3: operators (vector of Operator)
# 4: name (string)
fields = {}
for fi in range(4, v_size, 2):
    fields[(fi-4)//2] = struct.unpack_from('<H', buf, v_off + fi)[0]

def get_int_vector(field_idx):
    fo = fields.get(field_idx)
    if not fo: return []
    p = subgraph_pos + fo
    v = p + struct.unpack_from('<I', buf, p)[0]
    n = struct.unpack_from('<I', buf, v)[0]
    return [struct.unpack_from('<i', buf, v + 4 + i * 4)[0] for i in range(n)]

inputs = get_int_vector(1)
outputs = get_int_vector(2)
print('Inputs tensor indices:', inputs)
print('Outputs tensor indices:', outputs)

# Let's inspect the input and output tensors
tensors_fo = fields.get(0)
p = subgraph_pos + tensors_fo
tensors_vec = p + struct.unpack_from('<I', buf, p)[0]
num_tensors = struct.unpack_from('<I', buf, tensors_vec)[0]
print('Total tensors in subgraph:', num_tensors)

def get_tensor_info(idx):
    t_loc = tensors_vec + 4 + idx * 4
    t_pos = t_loc + struct.unpack_from('<I', buf, t_loc)[0]
    v_diff = struct.unpack_from('<i', buf, t_pos)[0]
    v_off = t_pos - v_diff
    v_size = struct.unpack_from('<H', buf, v_off)[0]
    
    t_fields = {}
    for fi in range(4, v_size, 2):
        t_fields[(fi-4)//2] = struct.unpack_from('<H', buf, v_off + fi)[0]
        
    # 0: shape (vector of int)
    # 1: type (TensorType enum)
    # 2: buffer (uint32)
    # 3: name (string)
    shape = []
    if 0 in t_fields and t_fields[0]:
        sp = t_pos + t_fields[0]
        sv = sp + struct.unpack_from('<I', buf, sp)[0]
        sn = struct.unpack_from('<I', buf, sv)[0]
        shape = [struct.unpack_from('<i', buf, sv + 4 + i * 4)[0] for i in range(sn)]
        
    t_type = 0
    if 1 in t_fields and t_fields[1]:
        t_type = struct.unpack_from('<b', buf, t_pos + t_fields[1])[0]
        
    name = ""
    if 3 in t_fields and t_fields[3]:
        np = t_pos + t_fields[3]
        nv = np + struct.unpack_from('<I', buf, np)[0]
        nl = struct.unpack_from('<I', buf, nv)[0]
        name = buf[nv+4:nv+4+nl].decode('utf-8', errors='ignore')
        
    return {'name': name, 'shape': shape, 'type': t_type}

for inp in inputs:
    print(f'Input tensor [{inp}]:', get_tensor_info(inp))

for out in outputs:
    print(f'Output tensor [{out}]:', get_tensor_info(out))
