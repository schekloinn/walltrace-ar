#!/bin/bash
set -euo pipefail
mkdir -p build/previews
device=$(cat build/simulator-id.txt)
python3 - "$device" <<'PY'
import subprocess, sys
subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=240)
PY
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$device" build/DerivedData/Build/Products/Debug-iphonesimulator/Puffline.app
for screen in home progress settings breathe; do
  xcrun simctl terminate "$device" local.puffline.app || true
  arguments=(--preview)
  if [[ "$screen" != home ]]; then arguments+=("--$screen"); fi
  xcrun simctl launch "$device" local.puffline.app "${arguments[@]}"
  sleep 10
  xcrun simctl io "$device" screenshot "build/previews/$screen.png"
done
# Also show the dark appearance of the home screen.
xcrun simctl terminate "$device" local.puffline.app
xcrun simctl launch "$device" local.puffline.app --preview --dark
sleep 8
xcrun simctl io "$device" screenshot build/previews/home-dark.png
