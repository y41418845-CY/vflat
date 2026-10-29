import json

with open(r'C:\Users\cytsa\.gemini\antigravity\brain\8aecb0f7-b51a-468f-aa24-0d26adec157f\.system_generated\steps\1324\output.txt', 'r', encoding='utf-8') as f:
    d = json.load(f)

exports = d['normalized_result']['exports']
matches = []
for e in exports:
    name = e['name']
    lower = name.lower()
    if any(k in lower for k in ['voyagerx', 'freeform', 'pptp', 'optp', 'scan', 'eigen', 'inpaint', 'mask', 'decomp', 'euler', 'finger']):
        matches.append(e)

print(f"Total matching functions: {len(matches)}")
print("-" * 80)
for m in sorted(matches, key=lambda x: int(x['value'], 16)):
    print(f"{m['value']:>10} | size: {m['size']:>5} | {m['name']}")
