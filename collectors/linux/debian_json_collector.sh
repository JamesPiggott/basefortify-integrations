#!/usr/bin/env bash
# BaseFortify – Components JSON export (Linux)
# Output: $HOME/Desktop/basefortify_components.json

set -euo pipefail

OUT="$HOME/Desktop/basefortify_components.json"
TMP="$(mktemp)"

node="$(hostname 2>/dev/null || echo '')"
device_id="$(cat /etc/machine-id 2>/dev/null || echo '')"
arch="$(uname -m 2>/dev/null || echo '')"

os_name="Linux"
os_version=""
os_build="$(uname -r 2>/dev/null || echo '')"

if [ -f /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  os_name="${PRETTY_NAME:-${NAME:-Linux}}"
  os_version="${VERSION_ID:-}"
fi

latest_kb=""
latest_kb_date=""

# Header row
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  vendor product version node device_id os_name os_version os_build arch latest_kb latest_kb_date source > "$TMP"

# OS row
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "Linux" "$os_name" "$os_version" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "OS" >> "$TMP"

# --- DPKG packages ---
if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='${Maintainer}\t${Package}\t${Version}\n' 2>/dev/null | \
  while IFS=$'\t' read -r vendor pkg ver; do
    [ -z "${pkg:-}" ] && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$vendor" "$pkg" "$ver" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "dpkg" >> "$TMP"
  done
fi

# --- RPM packages ---
if command -v rpm >/dev/null 2>&1; then
  rpm -qa --qf '%{VENDOR}\t%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null | \
  while IFS=$'\t' read -r vendor pkg ver; do
    [ -z "${pkg:-}" ] && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$vendor" "$pkg" "$ver" "$node" "$device_id" "$os_name" "$os_version" "$os_build" "$arch" "$latest_kb" "$latest_kb_date" "rpm" >> "$TMP"
  done
fi

# Convert TSV -> JSON using Python
python3 - "$TMP" "$OUT" << 'PY'
import csv, json, sys

tsv_path, json_path = sys.argv[1], sys.argv[2]

with open(tsv_path, encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    rows = [row for row in reader if row.get("product") and row.get("version")]

with open(json_path, "w", encoding="utf-8") as f_out:
    json.dump(rows, f_out, indent=2, ensure_ascii=False)

print(f"Wrote {len(rows)} entries to: {json_path}")
PY

rm -f "$TMP"
