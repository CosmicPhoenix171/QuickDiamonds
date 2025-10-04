import json
from pathlib import Path

SRC = Path(r"c:\Users\Phoenix\QuickDiamonds\species.json")
BACKUP = SRC.with_suffix('.json.bak')
DEFAULT_NEEDZONES = {"Feeding": ["-","-"], "Drinking": ["-"], "Resting": ["-"]}

text = SRC.read_text(encoding='utf-8')

objs = []
idx = 0
n = len(text)
while idx < n:
    # find next '{'
    start = text.find('{', idx)
    if start == -1:
        break
    depth = 0
    i = start
    while i < n:
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                # include this char and break
                objs.append(text[start:i+1])
                idx = i+1
                break
        i += 1
    else:
        # reached end without closing brace
        break

# parse objects
parsed = []
errors = []
for k, s in enumerate(objs, start=1):
    try:
        parsed.append(json.loads(s))
    except Exception as e:
        errors.append((k, str(e), s[:200]))

# backup original
if not BACKUP.exists():
    BACKUP.write_text(text, encoding='utf-8')

result = []
pending_needzones = None
for obj in parsed:
    # detect standalone needZones dict
    if isinstance(obj, dict) and set(obj.keys()) == {"Feeding", "Drinking", "Resting"}:
        pending_needzones = obj
        continue
    # normal species object
    if 'needZones' not in obj:
        if pending_needzones is not None:
            obj['needZones'] = pending_needzones
            pending_needzones = None
        else:
            obj['needZones'] = DEFAULT_NEEDZONES
    result.append(obj)

# if there was a trailing standalone needZones with no previous object, ignore it

# write normalized NDJSON
lines = [json.dumps(o, ensure_ascii=False, separators=(',', ': ')) for o in result]
SRC.write_text('\n'.join(lines) + '\n', encoding='utf-8')

# summary print
print('NORMALIZE_DONE')
print(f'TOTAL_PARSED: {len(parsed)}')
print(f'TOTAL_WRITTEN: {len(lines)}')
print(f'PARSE_ERRORS: {len(errors)}')
if errors:
    for e in errors[:5]:
        print('ERR', e[0], e[1])
