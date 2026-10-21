#!/usr/bin/env bash
#
# Check docs/fedora/targets.json and docs/fedora/dependency-map.tsv:
# targets.json parses and follows the expected shape; the TSV has the expected
# columns, a valid status on every row, and an owner on every gap or problem.
# If the Fedora stage tree exists, every blocking and canary release has a
# folder in it.
#
# Usage: tests/fedora-docs.sh [path/to/voulage]

set -euo pipefail

REPO="$(realpath "${1:-$(dirname "$0")/..}")"
TARGETS="$REPO/docs/fedora/targets.json"
MAP="$REPO/docs/fedora/dependency-map.tsv"

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# targets.json
if ! jq empty "$TARGETS" 2>/dev/null; then
  fail "targets.json does not parse"
else
  jq -e '
    (.targets | type == "array" and length >= 1) and
    (.canary | type == "array") and
    (.early_warning | type == "array") and
    (.updated | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
    (.rule | type == "string" and length > 0) and
    ([.targets[] | .blocking == true] | all) and
    ([(.canary + .early_warning)[] | .blocking == false] | all) and
    ([(.targets + .early_warning + .canary)[] |
       (.release | type == "string") and (.arches == ["x86_64", "aarch64"]) and (.versions | type == "object")] | all)
  ' "$TARGETS" >/dev/null || fail "targets.json does not have the expected shape"
  [ "$failures" -gt 0 ] || echo "ok: targets.json ($(jq -r '[.targets[].release] | join(", ")' "$TARGETS") blocking; canary $(jq -r '[.canary[].release] | join(", ")' "$TARGETS"))"
fi

# dependency-map.tsv
before=$failures
expected="debian_name field used_by constraints"
if [ -f "$TARGETS" ]; then
  for release in $(jq -r '(.targets + .early_warning + .canary)[].release' "$TARGETS" | sort -n); do
    expected+=" fedora_$release"
  done
fi
expected+=" status owner notes"

header="$(head -n1 "$MAP" | tr '\t' ' ')"
for column in $expected; do
  if [[ " $header " != *" $column "* ]]; then
    fail "dependency-map.tsv has no column $column"
  fi
done

columns="$(head -n1 "$MAP" | awk -F'\t' '{print NF}')"
awk -F'\t' -v n="$columns" '
  NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
  NF != n { printf "FAIL: line %d has %d fields, expected %d\n", NR, NF, n; bad++ }
  $col["debian_name"] == "" { printf "FAIL: line %d has no debian_name\n", NR; bad++ }
  $col["status"] !~ /^(same|renamed|capability|gap|problem|drop|regolith)$/ { printf "FAIL: line %d (%s) has status \"%s\"\n", NR, $1, $col["status"]; bad++ }
  $col["status"] ~ /^(gap|problem)$/ && $col["owner"] == "" { printf "FAIL: line %d (%s) is a %s without an owner\n", NR, $1, $col["status"]; bad++ }
  seen[$1]++ == 1 { printf "FAIL: %s appears more than once\n", $1; bad++ }
  END { exit bad > 0 }
' "$MAP" || failures=$((failures + 1))
[ "$failures" -gt "$before" ] || echo "ok: dependency-map.tsv ($(($(wc -l < "$MAP") - 1)) names)"

# stage tree follows targets.json
if [ -d "$REPO/stage/unstable/fedora" ] && [ -f "$TARGETS" ]; then
  for release in $(jq -r '(.targets + .canary)[].release' "$TARGETS"); do
    for stage in unstable testing; do
      if [ ! -f "$REPO/stage/$stage/fedora/$release/package-model.json" ]; then
        fail "targets.json lists $release but stage/$stage/fedora/$release/ is missing"
      fi
    done
  done
  for release in $(jq -r '.early_warning[].release' "$TARGETS"); do
    if [ ! -d "$REPO/stage/unstable/fedora/$release" ]; then
      echo "warning: early-warning release $release has no stage/unstable/fedora/$release/"
    fi
  done
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
