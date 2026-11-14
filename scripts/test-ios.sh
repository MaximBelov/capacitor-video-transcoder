#!/usr/bin/env bash
# Runs the XCTest target on an iOS simulator. The package depends on Capacitor, which needs UIKit, so `swift test` on the Mac
# cannot build it. IOS_SIMULATOR_UDID picks the simulator; without it the script takes an iPhone on the newest runtime, preferring
# one that is shut down, so that it does not share a simulator another test run has booted.
set -euo pipefail
cd "$(dirname "$0")/.."

udid=${IOS_SIMULATOR_UDID:-}
[ -n "$udid" ] || udid=$(xcrun simctl list devices available --json | node -e '
  const { devices } = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const ios = Object.entries(devices).filter(([runtime]) => runtime.includes("iOS")).sort(([a], [b]) => b.localeCompare(a, undefined, { numeric: true }));
  for (const [, list] of ios) {
    const phones = list.filter((d) => d.name.startsWith("iPhone"));
    const phone = phones.find((d) => d.state === "Shutdown") ?? phones[0];
    if (phone) { console.log(phone.udid); process.exit(0); }
  }
  process.exit(1);
') || { echo "no available iPhone simulator" >&2; exit 1; }

echo "simulator: $udid"
xcodebuild test \
  -scheme CapacitorVideoTranscoder \
  -destination "id=$udid" \
  -derivedDataPath build/ios \
  "$@"
