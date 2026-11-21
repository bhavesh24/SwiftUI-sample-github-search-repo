#!/usr/bin/env bash
# Fails if line coverage of the app target in an .xcresult bundle is below a threshold.
#
#   scripts/check-coverage.sh <bundle.xcresult> [threshold-percent=80] [label]
#
# Prints a per-file report, writes coverage.json / coverage.txt next to the bundle, and,
# on GitHub Actions, adds a markdown summary to the job page.
set -euo pipefail

BUNDLE="${1:?usage: $0 <bundle.xcresult> [threshold] [label]}"
THRESHOLD="${2:-80}"
LABEL="${3:-$(basename "$BUNDLE" .xcresult)}"
TARGET="SwiftUISampleApp.app"
OUT_DIR="$(dirname "$BUNDLE")"
BASE="$OUT_DIR/$(basename "$BUNDLE" .xcresult)"

xcrun xccov view --report --json "$BUNDLE" > "$BASE-coverage.json"
xcrun xccov view --report --files-for-target "$TARGET" "$BUNDLE" > "$BASE-coverage.txt"
cat "$BASE-coverage.txt"

python3 - "$BASE-coverage.json" "$TARGET" "$THRESHOLD" "$LABEL" <<'PY'
import json, os, sys

path, target_name, threshold, label = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
report = json.load(open(path))
target = next((t for t in report.get("targets", []) if t["name"] == target_name), None)
if target is None:
    sys.exit(f"error: no coverage for {target_name} in {path}. Is code coverage enabled?")

percent = target["lineCoverage"] * 100
passed = percent >= threshold
status = "PASS" if passed else "FAIL"
print(f"\n{label}: {target_name} line coverage {percent:.2f}% "
      f"({target['coveredLines']}/{target['executableLines']} lines), threshold {threshold:.0f}% -> {status}")

summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    rows = "\n".join(
        f"| `{f['name']}` | {f['lineCoverage'] * 100:.1f}% | {f['coveredLines']}/{f['executableLines']} |"
        for f in sorted(target["files"], key=lambda f: f["lineCoverage"])
    )
    with open(summary, "a") as out:
        out.write(
            f"### {label} coverage: {percent:.2f}% {'✅' if passed else '❌'} (threshold {threshold:.0f}%)\n\n"
            f"| File | Lines | Covered |\n|---|---|---|\n{rows}\n\n"
        )
sys.exit(0 if passed else 1)
PY
