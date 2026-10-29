import struct

with open(r'assets\models\optp_v3_3.dat', 'rb') as f:
    buf = bytearray(f.read())

print(f"Original size: {len(buf)} bytes")

# Fix any 32-bit offsets where bit 31 is set unexpectedly in table pointers
# Let's check buffers and tables
root_table = 28
vtable_off = 8

# Model table fields:
# 4: buffers
buffers_fo = struct.unpack_from('<H', buf, vtable_off + 12)[0]
buf_vec_pos = root_table + buffers_fo
buf_vec = buf_vec_pos + struct.unpack_from('<I', buf, buf_vec_pos)[0]
num_bufs = struct.unpack_from('<I', buf, buf_vec)[0]
print(f"Num buffers in model: {num_bufs}")

fixed_count = 0
for i in range(num_bufs):
    entry_pos = buf_vec + 4 + i * 4
    uoff = struct.unpack_from('<I', buf, entry_pos)[0]
    if uoff & 0x80000000:
        clean_uoff = uoff & 0x7fffffff
        struct.pack_into('<I', buf, entry_pos, clean_uoff)
        fixed_count += 1

print(f"Fixed {fixed_count} buffer pointers with 0x80000000 mask")

# Write out clean tflite model
out_path = r'assets\models\optp_v3_3_clean.tflite'
with open(out_path, 'wb') as f:
    f.write(buf)

print(f"Saved clean model to {out_path}")
