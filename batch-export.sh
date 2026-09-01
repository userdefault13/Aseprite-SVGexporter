#!/usr/bin/env bash
# Batch-export Paarcel side-scroll .aseprite assets to SVG JSON.
# Usage:
#   ./batch-export.sh                         # amAAVE only (smoke)
#   ./batch-export.sh amAAVE amWETH
#   ./batch-export.sh --all
#   ASEPRITE=/path/to/aseprite ./batch-export.sh --all

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASEPRITE="${ASEPRITE:-aseprite}"
PAARCEL_ASE="${PAARCEL_ASE:-/Users/juliuswong/Dev/Paarcel/Assets/Resources/Aavegotchi/Aseprites/Aavegotchi}"
OUT_ROOT="${OUT_ROOT:-/Users/juliuswong/Dev/Paarcel/Assets/Resources/Aavegotchi/JSONs/_side-scroll-raw}"
RUNNER="$ROOT/batch-export-cli.lua"

COLLATERALS_ALL=(
  amAAVE amDAI amUSDC amUSDT amWBTC amWETH amWMATIC
  maAAVE maDAI maLINK maTUSD maUNI maUSDC maUSDT maWETH maYFI
)

die() { echo "Error: $*" >&2; exit 1; }

need_aseprite() {
  command -v "$ASEPRITE" >/dev/null 2>&1 || die "aseprite not found. Set ASEPRITE=..."
  [[ -f "$RUNNER" ]] || die "Missing $RUNNER"
  [[ -d "$PAARCEL_ASE" ]] || die "Missing Paarcel Aseprites: $PAARCEL_ASE"
}

export_one() {
  local input="$1" output="$2"
  mkdir -p "$(dirname "$output")"
  echo "→ $(basename "$input")"
  "$ASEPRITE" -b \
    --script-param "input=$input" \
    --script-param "output=$output" \
    --script-param "optimized=1" \
    --script-param "css=1" \
    --script "$RUNNER" 2>&1 | grep -v '^\[DEBUG\]' || true
  [[ -f "$output" ]] || die "Export failed for $input"
}

export_collateral() {
  local collateral="$1"
  local src="$PAARCEL_ASE/$collateral"
  local dest="$OUT_ROOT/$collateral"
  [[ -d "$src" ]] || die "Collateral not found: $src"

  echo ""
  echo "=== $collateral ==="
  mkdir -p "$dest"

  # body / hands / mouth / shadow / collateral
  local dir part
  for part in body hands mouth shadow collateral; do
    dir="$src/$part"
    [[ -d "$dir" ]] || continue
    mkdir -p "$dest/$part"
    local f
    for f in "$dir"/*.aseprite; do
      [[ -f "$f" ]] || continue
      export_one "$f" "$dest/$part/$(basename "$f" .aseprite).svg.json"
    done
  done

  # eye shapes (nested)
  if [[ -d "$src/eye shape" ]]; then
    while IFS= read -r -d '' f; do
      local rel="${f#"$src/"}"
      local out="$dest/${rel%.aseprite}.svg.json"
      mkdir -p "$(dirname "$out")"
      export_one "$f" "$out"
    done < <(find "$src/eye shape" -name '*.aseprite' -print0)
  fi
}

need_aseprite

TARGETS=()
if [[ $# -eq 0 ]]; then
  TARGETS=(amAAVE)
elif [[ "$1" == "--all" ]]; then
  TARGETS=("${COLLATERALS_ALL[@]}")
else
  TARGETS=("$@")
fi

echo "Aseprite: $ASEPRITE"
echo "Source:   $PAARCEL_ASE"
echo "Output:   $OUT_ROOT"
echo "Targets:  ${TARGETS[*]}"

ok=0
for c in "${TARGETS[@]}"; do
  export_collateral "$c"
  ok=$((ok + 1))
done

echo ""
echo "Exported $ok collateral(s) → $OUT_ROOT"
echo "Next: python3 assemble-side-scroll-library.py"
