#!/bin/sh
set -eu

if [ -z "${SCOREMAKER_SIGN_IDENTITY:-}" ]; then
  echo "SCOREMAKER_SIGN_IDENTITY must name a Developer ID Application certificate." >&2
  exit 2
fi
if [ -z "${SCOREMAKER_NOTARY_PROFILE:-}" ]; then
  echo "SCOREMAKER_NOTARY_PROFILE must name a notarytool keychain profile." >&2
  exit 2
fi

make clean
make test
xcodebuild -project ScoreMaker.xcodeproj -scheme ScoreMakerCompatibilityTests \
  -configuration Release test CODE_SIGNING_ALLOWED=NO
xcodebuild -project ScoreMaker.xcodeproj -scheme ScoreMaker \
  -configuration Release -derivedDataPath build/xcode-release \
  build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO

release_dir="build/release"
app_path="build/xcode-release/Build/Products/Release/ScoreMaker.app"
archive_path="$release_dir/ScoreMaker.zip"
mkdir -p "$release_dir"

codesign --force --deep --options runtime --timestamp \
  --entitlements ScoreMaker.entitlements \
  --sign "$SCOREMAKER_SIGN_IDENTITY" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" \
  --keychain-profile "$SCOREMAKER_NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
ditto -c -k --keepParent "$app_path" "$archive_path"

echo "Release archive: $archive_path"
