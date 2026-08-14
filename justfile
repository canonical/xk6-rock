set allow-duplicate-recipes
set allow-duplicate-variables
import? 'rocks.just'

rock_name := "xk6"
source_repo := 'grafana/k6'

[private]
@default:
  just --list
  echo ""
  echo "For help with a specific recipe, run: just --usage <recipe>"

# Patch all existing major.minor folders to the newest upstream patch version
[group("maintenance")]
update:
  #!/usr/bin/env bash
  set -e
  [[ -z "{{source_repo}}" ]] && { echo "× Set 'source_repo' in the local justfile"; exit 1; }
  for folder in $(find . -maxdepth 1 -type d -regextype posix-extended -regex '\./[0-9]+\.[0-9]+' -printf '%f\n' | sort -V); do
    read -r version tag < <(just resolve-tag "$folder")
    if [[ -z "$version" ]]; then echo "→ no upstream patch found for $folder, skipping"; continue; fi
    current="$(yq -r '.version' "$folder/rockcraft.yaml")"
    if [[ "$current" == "$version" ]]; then echo "→ $folder already at $version"; continue; fi
    echo "Updating $folder: $current → $version"
    version="$version" yq -i '.version = strenv(version)' "$folder/rockcraft.yaml"
    # Sync the embedded K6_VERSION build reference
    sed -i "s|K6_VERSION=[^']*|K6_VERSION=${version}|g" "$folder/rockcraft.yaml"
    # Refresh the Go build-snap from the upstream go.mod
    TMP_DIR="$(mktemp -d)"
    gh repo clone "{{source_repo}}" "$TMP_DIR/src" -- --branch "$tag" --depth 1 2>/dev/null || true
    if [[ -f "$TMP_DIR/src/go.mod" ]]; then
      go_snap_version="$(grep -Po '^go \K(\S+)' "$TMP_DIR/src/go.mod" | sed -E 's/([0-9]+\.[0-9]+).*/\1/')"
      go_snap_version="$go_snap_version" yq -i \
        '(.parts.k6.build-snaps[] | select(test("^go/"))) = "go/"+strenv(go_snap_version)+"/candidate"' \
        "$folder/rockcraft.yaml"
    fi
    rm -rf "$TMP_DIR"
  done

