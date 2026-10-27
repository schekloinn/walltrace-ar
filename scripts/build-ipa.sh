#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Run this script in a fresh checkout; never silently reuse an older result.
if [[ -e build/DerivedData || -e build/Package || -e build/Build.xcresult || -e build/WallTraceAR.ipa ]]; then
  echo "Build outputs already exist. Use a fresh checkout or move build/ aside." >&2
  exit 1
fi
{
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcodegen --version
} | tee build/toolchain.txt
/usr/bin/plutil -lint WallTraceAR/Info.plist
# Run the pure Swift model and stabilization checks on the macOS host.
xcrun swiftc -O -swift-version 5 WallTraceAR/ImageSlots.swift WallTraceAR/AnchorStabilizer.swift WallTraceAR/SavedProject.swift Tests/Checks.swift -o build/WallTraceChecks
build/WallTraceChecks | tee build/checks.log
xcodegen generate --spec project.yml
# Parse with the selected Apple compiler before the full device build.
xcrun swiftc -frontend -parse WallTraceAR/*.swift
xcodebuild \
  -project WallTraceAR.xcodeproj \
  -scheme WallTraceAR \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/Build.xcresult \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO TARGETED_DEVICE_FAMILY=1 \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  build 2>&1 | tee build/build.log

app='build/DerivedData/Build/Products/Release-iphoneos/WallTrace AR.app'
test -d "$app"
executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Info.plist")
xcrun lipo "$app/$executable" -verify_arch arm64
/usr/libexec/PlistBuddy -c 'Print MinimumOSVersion' "$app/Info.plist" | grep -Fx '15.0'
/usr/libexec/PlistBuddy -c 'Print UIDeviceFamily:0' "$app/Info.plist" | grep -Fx '1'
if /usr/libexec/PlistBuddy -c 'Print UIDeviceFamily:1' "$app/Info.plist" >/dev/null 2>&1; then
  echo 'Unexpected extra device family; expected iPhone only.' >&2
  exit 1
fi
# Ad-hoc here means codesign identity '-', NOT Apple's Ad Hoc distribution.
# Sign nested Swift libraries first if Xcode embeds any for the deployment target.
if [[ -d "$app/Frameworks" ]]; then
  while IFS= read -r -d '' library; do
    /usr/bin/codesign --force --sign - --timestamp=none "$library"
  done < <(find "$app/Frameworks" -type f -name '*.dylib' -print0)
  while IFS= read -r -d '' framework; do
    /usr/bin/codesign --force --sign - --timestamp=none "$framework"
  done < <(find "$app/Frameworks" -type d -name '*.framework' -depth -print0)
fi
/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p build/Package/Payload
/usr/bin/ditto "$app" 'build/Package/Payload/WallTrace AR.app'
(cd build/Package && /usr/bin/zip -qry ../WallTraceAR.ipa Payload)
/usr/bin/unzip -tq build/WallTraceAR.ipa
(cd build && /usr/bin/shasum -a 256 WallTraceAR.ipa > WallTraceAR.ipa.sha256)
echo 'IPA ready: build/WallTraceAR.ipa (install with TrollStore)'
