#!/bin/bash
set -euo pipefail
mkdir -p build/previews
xcrun simctl list devices available -j > build/devices.json
python3 - <<'PY'
import json
data=json.load(open('build/devices.json'))
devices=[(rt,d) for rt,ds in data['devices'].items() if 'iOS-18' in rt for d in ds if d.get('isAvailable')]
se=[x for x in devices if 'iPhone SE (3rd generation)' == x[1]['name']]
pool=se or [x for x in devices if 'iPhone' in x[1]['name']]
assert pool, 'No available iPhone simulator'
runtime, device=sorted(pool,key=lambda x:x[0])[-1]
open('build/previews/simulator.txt','w').write(runtime+'\n'+device['name']+'\n')
open('build/simulator-id.txt','w').write(device['udid'])
PY
xcrun simctl boot "$(cat build/simulator-id.txt)"
