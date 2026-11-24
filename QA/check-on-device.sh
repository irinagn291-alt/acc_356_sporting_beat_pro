#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GF_SIMULATOR_UDID:?Run this script through the factory simulator pool}"
role="${1:?phone, pad, range or campaign}"
attempt="${2:?unique evidence folder}"
test="${3:-}"
out="$PWD/QA/evidence/$attempt"
mkdir -p "$out"
build="$PWD/Build"
bundle=studio.sportingbeat.acc356
app="$build/Build/Products/Debug-iphonesimulator/SportingBeat.app"
xcrun simctl bootstatus "$GF_SIMULATOR_UDID" -b > "$out/boot.log" 2>&1
xcrun simctl status_bar "$GF_SIMULATOR_UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100 || true
flags=()
if [[ "$role" == pad || "$role" == range ]]; then
    xcodebuild -project SportingBeat.xcodeproj -scheme SportingBeat -configuration Debug \
        -destination "id=$GF_SIMULATOR_UDID" -parallel-testing-enabled NO \
        -derivedDataPath "$build" build-for-testing > "$out/prepare.log" 2>&1
    xcrun simctl install "$GF_SIMULATOR_UDID" "$app"
    if [[ "$role" == range ]]; then
        data="$(xcrun simctl get_app_container "$GF_SIMULATOR_UDID" "$bundle" data)"
        mkdir -p "$data/Documents"
        cp "$PWD/QA/evidence/campaign-final/saved/studio.json" "$data/Documents/studio.json"
        flags+=(-only-testing:SportingBeatUITests/InteractionTests/testPadFullRangeHandles)
    else
        xcrun simctl launch "$GF_SIMULATOR_UDID" "$bundle" -AppleLanguages '(zh-Hant)' -AppleLocale zh_TW
        sleep 2
        xcrun simctl io "$GF_SIMULATOR_UDID" screenshot "$out/ipad-first-launch-zh-Hant.png"
        xcrun simctl terminate "$GF_SIMULATOR_UDID" "$bundle"
        xcrun simctl launch "$GF_SIMULATOR_UDID" "$bundle" -AppleLanguages '(ar)' -AppleLocale ar
        sleep 2
        xcrun simctl io "$GF_SIMULATOR_UDID" screenshot "$out/ipad-first-launch-ar.png"
        xcrun simctl terminate "$GF_SIMULATOR_UDID" "$bundle"
        data="$(xcrun simctl get_app_container "$GF_SIMULATOR_UDID" "$bundle" data)"
        mkdir -p "$data/Documents"
        cp "$PWD/QA/evidence/late-fixture.json" "$data/Documents/qa-studio.json"
        flags+=(-only-testing:SportingBeatUITests/InteractionTests/testPadThreeLayersAndBroadcast)
    fi
elif [[ "$role" == campaign ]]; then
    flags+=(-only-testing:SportingBeatUITests/InteractionTests/testFullCampaignFromNewFile)
elif [[ "$role" == layout-pad ]]; then
    flags+=(-only-testing:SportingBeatUITests/InteractionTests/testPadFillsPortraitAndLandscape)
else
    if [[ -z "$test" ]]; then
        flags+=(-only-testing:SportingBeatUITests/InteractionTests/testPhoneFirstOrder
                -only-testing:SportingBeatUITests/InteractionTests/testPhoneCleanReleasePathAndSuspension
                -only-testing:SportingBeatUITests/InteractionTests/testPhoneFillsAllOrientations)
    fi
fi
if [[ -n "$test" ]]; then flags=(-only-testing:SportingBeatUITests/InteractionTests/"$test"); fi
recorder=""
if [[ "$role" == phone ]]; then
    xcrun simctl io "$GF_SIMULATOR_UDID" recordVideo --codec=h264 --force "$out/session.mp4" > "$out/video.log" 2>&1 &
    recorder=$!
fi
finish() {
    if [[ -n "$recorder" ]]; then
        kill -INT "$recorder" 2>/dev/null || true
        wait "$recorder" || true
    fi
    data="$(xcrun simctl get_app_container "$GF_SIMULATOR_UDID" "$bundle" data 2>/dev/null || true)"
    if [[ -n "$data" && -d "$data/Documents" ]]; then
        mkdir -p "$out/saved"
        cp -R "$data/Documents/." "$out/saved/"
    fi
    if [[ -d "$out/Interaction.xcresult" ]]; then
        xcrun xcresulttool export attachments --path "$out/Interaction.xcresult" --output-path "$out/frames" > "$out/attachments.log" 2>&1 || true
    fi
    python3 QA/collect-evidence.py "$out" > "$out/evidence-check.log" 2>&1 || true
}
trap finish EXIT
xcodebuild -project SportingBeat.xcodeproj -scheme SportingBeat -configuration Debug \
    -destination "id=$GF_SIMULATOR_UDID" -parallel-testing-enabled NO \
    -derivedDataPath "$build" -resultBundlePath "$out/Interaction.xcresult" \
    "${flags[@]}" test > "$out/test.log" 2>&1
