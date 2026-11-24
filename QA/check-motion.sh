#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GF_SIMULATOR_UDID:?Use the factory simulator pool}"
role="${1:?iphone or ipad}"
run="${2:-$role}"
base="$PWD/../../artifacts/genesis/studio.sportingbeat.acc356"
build="$base/motion-build"
review="$base/motion-review"
evidence="$build/$run"
mkdir -p "$evidence" "$review/$role"
bundle=studio.sportingbeat.acc356
seat=testMotionPhone
if [[ "$role" == ipad ]]; then seat=testMotionCampaign; fi

xcrun simctl bootstatus "$GF_SIMULATOR_UDID" -b > "$evidence/boot.log" 2>&1
xcrun simctl status_bar "$GF_SIMULATOR_UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
if [[ -n "${3:-}" ]]; then
    origin="$3"
    if [[ "$role" == ipad ]]; then seat=testMotionResume; else seat=testMotionPhoneLateStills; fi
    xcodebuild -project SportingBeat.xcodeproj -scheme SportingBeat -configuration Debug \
        -destination "id=$GF_SIMULATOR_UDID" -parallel-testing-enabled NO \
        -derivedDataPath "$build/Debug" build-for-testing > "$evidence/prepare.log" 2>&1
    xcrun simctl install "$GF_SIMULATOR_UDID" "$build/Debug/Build/Products/Debug-iphonesimulator/SportingBeat.app"
    resume="$(xcrun simctl get_app_container "$GF_SIMULATOR_UDID" "$bundle" data)"
    mkdir -p "$resume/Documents"
    cp "$origin" "$resume/Documents/studio.json"
fi
recorder=""
if [[ "$seat" != testMotionPhoneLateStills ]]; then
    python3 -c 'import time; print(time.time())' > "$evidence/video-start.txt"
    xcrun simctl io "$GF_SIMULATOR_UDID" recordVideo --codec=h264 --force "$evidence/session.mp4" > "$evidence/video.log" 2>&1 &
    recorder=$!
fi
finish() {
    if [[ -n "$recorder" ]]; then
        kill -INT "$recorder" 2>/dev/null || true
        wait "$recorder" || true
    fi
    data="$(xcrun simctl get_app_container "$GF_SIMULATOR_UDID" "$bundle" data 2>/dev/null || true)"
    if [[ -n "$data" && -d "$data/Documents" ]]; then
        mkdir -p "$evidence/saved"
        cp -R "$data/Documents/." "$evidence/saved/"
    fi
    if [[ -d "$evidence/Interaction.xcresult" ]]; then
        xcrun xcresulttool export attachments --path "$evidence/Interaction.xcresult" --output-path "$evidence/frames" > "$evidence/attachments.log" 2>&1 || true
    fi
}
trap finish EXIT
xcodebuild -project SportingBeat.xcodeproj -scheme SportingBeat -configuration Debug \
    -destination "id=$GF_SIMULATOR_UDID" -parallel-testing-enabled NO \
    -derivedDataPath "$build/Debug" -resultBundlePath "$evidence/Interaction.xcresult" \
    "-only-testing:SportingBeatUITests/InteractionTests/$seat" test > "$evidence/test.log" 2>&1
