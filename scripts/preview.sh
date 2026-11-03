#!/bin/bash
set -euo pipefail
mkdir -p build/previews
xcrun simctl list devices available -j > build/devices.json
device=$(python3 - <<'PY'
import json
data=json.load(open('build/devices.json'))
devices=[(rt,d) for rt,ds in data['devices'].items() if 'iOS' in rt for d in ds if d.get('isAvailable')]
se=[x for x in devices if 'iPhone SE (3rd generation)' == x[1]['name']]
pool=se or [x for x in devices if 'iPhone' in x[1]['name']]
assert pool, 'No available iPhone simulator'
runtime, device=sorted(pool,key=lambda x:x[0])[-1]
open('build/previews/simulator.txt','w').write(runtime+'\n'+device['name']+'\n')
print(device['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" build/DerivedData/Build/Products/Debug-iphonesimulator/Puffline.app
for screen in home progress settings breathe; do
  xcrun simctl terminate "$device" local.puffline.app || true
  arguments=(--preview)
  if [[ "$screen" != home ]]; then arguments+=("--$screen"); fi
  xcrun simctl launch "$device" local.puffline.app "${arguments[@]}"
  sleep 4
  xcrun simctl io "$device" screenshot "build/previews/$screen.png"
done
# Also show the dark appearance of the home screen.
xcrun simctl terminate "$device" local.puffline.app
xcrun simctl launch "$device" local.puffline.app --preview --dark
sleep 3
xcrun simctl io "$device" screenshot build/previews/home-dark.png
