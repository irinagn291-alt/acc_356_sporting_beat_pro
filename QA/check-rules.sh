#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d /private/tmp/sporting-beat-rules.XXXXXXXX)"
trap 'rm -rf "$tmp"' EXIT
swiftc -O -module-cache-path "$tmp" SportingBeat/Take.swift QA/Rules.swift -o "$tmp/rules"
"$tmp/rules" "$@"
