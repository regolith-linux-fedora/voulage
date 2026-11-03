#!/usr/bin/env bash
#
# Check the Fedora package models: after merging the stage tree the way main.sh
# does, every package must build from a regolith-linux-fedora fork (or be null),
# and unstable refs must be fedora/* branches.
#
# Usage: tests/fedora-model.sh [path/to/voulage]

set -euo pipefail

REPO="$(realpath "${1:-$(dirname "$0")/..}")"
FORK_PREFIX="https://github.com/regolith-linux-fedora/"
EXCLUDED=(regolith-archive-keyring regolith-distro-ubuntu regolith-lightdm-config regolith-system-ubuntu ubiquity-slideshow-regolith)

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# Same merge order as merge_models in .github/scripts/main.sh
merged_model() {
  local stage="$1" codename="$2"
  local files=()
  for f in "stage/package-model.json" "stage/$stage/package-model.json" "stage/$stage/fedora/package-model.json" "stage/$stage/fedora/$codename/package-model.json"; do
    if [ -f "$REPO/$f" ]; then
      files+=("$REPO/$f")
    fi
  done
  jq -s 'reduce .[] as $m ({}; . * $m)' "${files[@]}"
}

for stage in unstable testing; do
  if [ ! -f "$REPO/stage/$stage/fedora/package-model.json" ]; then
    fail "stage/$stage/fedora/package-model.json is missing"
    continue
  fi

  for dir in "$REPO"/stage/"$stage"/fedora/*/; do
    codename="$(basename "$dir")"
    target="$stage/fedora/$codename"

    if [ ! -f "$dir/package-model.json" ]; then
      fail "$target: package-model.json is missing"
      continue
    fi

    model="$(merged_model "$stage" "$codename")"

    while IFS=$'\t' read -r name source ref; do
      if [[ "$source" != "$FORK_PREFIX"* ]]; then
        fail "$target: $name builds from $source, not a regolith-linux-fedora fork"
      fi
      if [ "$stage" == "unstable" ] && [[ "$ref" != fedora/* ]]; then
        fail "$target: $name ref $ref is not a fedora/* branch"
      fi
    done < <(echo "$model" | jq -r '.packages | to_entries[] | select(.value != null) | [.key, .value.source, .value.ref] | @tsv')

    for name in "${EXCLUDED[@]}"; do
      if [ "$(echo "$model" | jq --arg n "$name" '.packages[$n]')" != "null" ]; then
        fail "$target: excluded package $name is not null"
      fi
    done

    echo "ok: $target ($(echo "$model" | jq '[.packages[] | select(. != null)] | length') packages)"
  done
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
