#!/usr/bin/env bash
# BaseFortify – Components CSV export (macOS)
# Output: $HOME/Desktop/basefortify_components.csv

set -euo pipefail

OUT="$HOME/Desktop/basefortify_components.csv"
TMP="$(mktemp)"

node="$(hostname 2>/dev/null || echo '')"
arch="$(uname -m 2>/dev/null || echo '')"

if command -v sw_vers >/dev/null 2>&1; then
  os_name="$(sw_vers -productName)"
  os_version="$(sw_vers -productVersion)"
  os_build="$(sw_vers -buildVersion)"
else
  os_name="macOS"
  os_version=""
  os_build="$(uname -r 2>/dev/null || echo '')"
fi

device_id="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $4; exit}')"

latest_kb=""
latest_kb_date=""

# Header
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  vendor product version node device_id os_name os_version os_build arch latest_kb latest_kb_date source > "$TMP"

# OS row
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "Apple" "$os_name" "$os_version" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "OS" >> "$TMP"

# --- Applications from system_profiler (no vendor info available) ---
if command -v system_profiler >/dev/null 2>&1; then
  system_profiler SPApplicationsDataType -detailLevel mini 2>/dev/null | \
  awk 'BEGIN{FS=": ";OFS="\t"}
       /^        Name: /{name=$2}
       /^        Version: /{ver=$2; if (name!="" && ver!=""){print "", name, ver; name=""; ver=""}}' | \
  while IFS=$'\t' read -r vendor name ver; do
    [ -z "${name:-}" ] && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$vendor" "$name" "$ver" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "system_profiler" >> "$TMP"
  done
fi

# --- Homebrew packages (if installed) ---
if command -v brew >/dev/null 2>&1; then
  brew list --versions 2>/dev/null | \
  while read -r name versions; do
    [ -z "${name:-}" ] && continue
    ver="${versions%% *}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "Homebrew" "$name" "$ver" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "brew" >> "$TMP"
  done
fi

# TSV -> CSV
python3 - "$TMP" "$OUT" << 'PY'
import csv, sys
tsv_path, csv_path = sys.argv[1], sys.argv[2]

with open(tsv_path, encoding="utf-8") as f_in, \
     open(csv_path, "w", newline="", encoding="utf-8") as f_out:
    reader = csv.reader(f_in, delimiter="\t")
    writer = csv.writer(f_out)
    for row in reader:
        writer.writerow(row)
PY

rm -f "$TMP"
echo "Wrote components CSV to: $OUT"
