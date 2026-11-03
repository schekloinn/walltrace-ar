#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
{
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcodegen --version
} | tee build/toolchain.txt
plutil -lint App/Info.plist Widget/Info.plist App/Puffline.entitlements
xcrun swiftc -O -swift-version 5 Shared/Model.swift Tests/Checks.swift -o build/PufflineChecks
build/PufflineChecks | tee build/checks.log
xcrun swift scripts/icon.swift
xcodegen generate
xcodebuild -project Puffline.xcodeproj -scheme Puffline -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  -resultBundlePath build/Release.xcresult ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 TARGETED_DEVICE_FAMILY=1 \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' build 2>&1 | tee build/build.log

app='build/DerivedData/Build/Products/Release-iphoneos/Puffline.app'
widget="$app/PlugIns/PufflineWidget.appex"
test -d "$widget"
for bundle in "$app" "$widget"; do
  executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$bundle/Info.plist")
  xcrun lipo "$bundle/$executable" -verify_arch arm64
  /usr/libexec/PlistBuddy -c 'Print MinimumOSVersion' "$bundle/Info.plist" | grep -Fx '15.0'
done
# Sign nested frameworks before their enclosing bundles.
if [[ -d "$app/Frameworks" ]]; then
  while IFS= read -r -d '' library; do
    codesign --force --sign - --timestamp=none "$library"
  done < <(find "$app/Frameworks" -type f -name '*.dylib' -print0)
  while IFS= read -r -d '' framework; do
    codesign --force --sign - --timestamp=none "$framework"
  done < <(find "$app/Frameworks" -type d -name '*.framework' -depth -print0)
fi
# Only the shared widget container is requested; no unsandboxing or root access.
codesign --force --sign - --timestamp=none --entitlements App/Puffline.entitlements "$widget"
codesign --force --sign - --timestamp=none --entitlements App/Puffline.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements :- "$app" > build/app-entitlements.plist
codesign -d --entitlements :- "$widget" > build/widget-entitlements.plist
xcrun nm "$app/Puffline" > build/symbols.txt
if grep -q 'DemoData' build/symbols.txt; then
  echo 'Unexpected debug demonstration code in Release' >&2; exit 1
fi
mkdir -p build/Package/Payload
ditto "$app" build/Package/Payload/Puffline.app
(cd build/Package && zip -qry ../Puffline-1.0.ipa Payload)
unzip -tq build/Puffline-1.0.ipa
python3 scripts/validate-ipa.py build/Puffline-1.0.ipa | tee build/package-validation.json
(cd build && shasum -a 256 Puffline-1.0.ipa > Puffline-1.0.ipa.sha256)
echo 'Puffline IPA ready for installation with TrollStore.'
