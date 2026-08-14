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
    just sync-extra "$folder" "$version" "$tag"
  done

# Onboard a new major.minor line, seeding from the newest existing folder
[group("maintenance")]
add-version version:
  #!/usr/bin/env bash
  set -e
  [[ -z "{{source_repo}}" ]] && { echo "× Set 'source_repo' in the local justfile"; exit 1; }
  requested="{{version}}"; requested="${requested#v}"
  major_minor="$(echo "$requested" | grep -oP '^\d+\.\d+')"
  [[ -z "$major_minor" ]] && { echo "× could not parse a major.minor from '{{version}}'"; exit 1; }
  [[ -d "$major_minor" ]] && { echo "→ $major_minor/ already exists, nothing to do"; exit 0; }
  read -r version tag < <(just resolve-tag "$major_minor")
  [[ -z "$version" ]] && { echo "× no upstream release found for {{source_repo}} on the $major_minor line"; exit 1; }
  template="{{latest_version}}"
  [[ -z "$template" ]] && { echo "× no existing X.Y folder to copy from"; exit 1; }
  echo "Seeding $major_minor/ from $template/ ..."
  cp -r "$template" "$major_minor"
  just sync-extra "$major_minor" "$version" "$tag"
  echo "✓ Created $major_minor/ at $version"

# Pin the version, embedded K6_VERSION reference, and Go build-snap for a single folder
[private]
sync-extra folder version tag:
  #!/usr/bin/env bash
  set -e
  version="{{version}}" yq -i '.version = strenv(version)' "{{folder}}/rockcraft.yaml"
  sed -i "s|K6_VERSION=[^']*|K6_VERSION={{version}}|g" "{{folder}}/rockcraft.yaml"
  TMP_DIR="$(mktemp -d)"
  gh repo clone "{{source_repo}}" "$TMP_DIR/src" -- --branch "{{tag}}" --depth 1 2>/dev/null || true
  if [[ -f "$TMP_DIR/src/go.mod" ]]; then
    go_snap_version="$(grep -Po '^go \K(\S+)' "$TMP_DIR/src/go.mod" | sed -E 's/([0-9]+\.[0-9]+).*/\1/')"
    go_snap_version="$go_snap_version" yq -i \
      '(.parts.k6.build-snaps[] | select(test("^go/"))) = "go/"+strenv(go_snap_version)+"/candidate"' \
      "{{folder}}/rockcraft.yaml"
  fi
  rm -rf "$TMP_DIR"

