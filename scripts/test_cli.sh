#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"

if [[ -z "$APP" ]]; then
  for candidate in \
    "$ROOT_DIR/build_cli_make/flatPDF.app/Contents/MacOS/flatPDF" \
    "$ROOT_DIR/build_cli/appflatPdfQt2.app/Contents/MacOS/appflatPdfQt2" \
    "$ROOT_DIR/build/appflatPdfQt2.app/Contents/MacOS/appflatPdfQt2" \
    "$ROOT_DIR/build_ARM/appflatPdfQt2.app/Contents/MacOS/appflatPdfQt2"
  do
    if [[ -x "$candidate" ]]; then
      APP="$candidate"
      break
    fi
  done
fi

if [[ -z "$APP" || ! -x "$APP" ]]; then
  echo "App non trovata. Passa il binario come primo argomento." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flatpdf-cli-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

INPUT="$TMP_DIR/input.pdf"

python3 - "$INPUT" <<'PY'
import sys

path = sys.argv[1]
commands = []
commands.append("1 1 1 rg 0 0 420 595 re f\n")
for y in range(0, 595, 10):
    for x in range(0, 420, 10):
        r = ((x * 17 + y * 3) % 255) / 255
        g = ((x * 5 + y * 11) % 255) / 255
        b = ((x * 13 + y * 7) % 255) / 255
        commands.append(f"{r:.3f} {g:.3f} {b:.3f} rg {x} {y} 10 10 re f\n")
commands.append("0 0 0 rg BT /F1 24 Tf 36 540 Td (FlatPDF CLI test) Tj ET\n")
stream = "".join(commands).encode("ascii")

objects = []
objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
objects.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>")
objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
objects.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream")

pdf = bytearray(b"%PDF-1.4\n")
offsets = [0]
for i, obj in enumerate(objects, start=1):
    offsets.append(len(pdf))
    pdf += f"{i} 0 obj\n".encode("ascii") + obj + b"\nendobj\n"
xref = len(pdf)
pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii")
for off in offsets[1:]:
    pdf += f"{off:010d} 00000 n \n".encode("ascii")
pdf += f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode("ascii")
open(path, "wb").write(pdf)
PY

run_cli() {
  "$APP" --cli "$@"
}

assert_success_json() {
  python3 - "$1" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
if not data.get("success"):
    raise SystemExit(data.get("error", "CLI returned success=false"))
PY
}

size_of() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.getsize(sys.argv[1]))
PY
}

echo "== Preset =="
run_cli --list-presets

STD_OUT="$TMP_DIR/standard.pdf"
PNG_OUT="$TMP_DIR/lossless.pdf"
LOW_DPI_OUT="$TMP_DIR/low-dpi.pdf"
HIGH_DPI_OUT="$TMP_DIR/high-dpi.pdf"
LOW_Q_OUT="$TMP_DIR/low-quality.pdf"
HIGH_Q_OUT="$TMP_DIR/high-quality.pdf"

echo "== Standard preset =="
std_json="$(run_cli --input "$INPUT" --output "$STD_OUT" --preset standard)"
echo "$std_json"
assert_success_json "$std_json"
[[ -s "$STD_OUT" ]]

echo "== PNG lossless =="
png_json="$(run_cli --input "$INPUT" --output "$PNG_OUT" --preset lossless)"
echo "$png_json"
assert_success_json "$png_json"
[[ -s "$PNG_OUT" ]]

echo "== Estimate =="
estimate_json="$(run_cli --input "$INPUT" --preset standard --estimate)"
echo "$estimate_json"
python3 - "$estimate_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
if not data.get("success") or int(data.get("estimatedBytes", 0)) <= 0:
    raise SystemExit("Stima non valida")
PY

echo "== DPI effect =="
run_cli --input "$INPUT" --output "$LOW_DPI_OUT" --dpi 72 --quality 85 --format jpg >/dev/null
run_cli --input "$INPUT" --output "$HIGH_DPI_OUT" --dpi 220 --quality 85 --format jpg >/dev/null
low_dpi_size="$(size_of "$LOW_DPI_OUT")"
high_dpi_size="$(size_of "$HIGH_DPI_OUT")"
echo "low dpi:  $low_dpi_size"
echo "high dpi: $high_dpi_size"
if (( high_dpi_size <= low_dpi_size )); then
  echo "DPI non sembra influire sulla dimensione finale." >&2
  exit 1
fi

echo "== JPEG quality effect =="
run_cli --input "$INPUT" --output "$LOW_Q_OUT" --dpi 180 --quality 40 --format jpg >/dev/null
run_cli --input "$INPUT" --output "$HIGH_Q_OUT" --dpi 180 --quality 95 --format jpg >/dev/null
low_q_size="$(size_of "$LOW_Q_OUT")"
high_q_size="$(size_of "$HIGH_Q_OUT")"
echo "quality 40: $low_q_size"
echo "quality 95: $high_q_size"
if (( high_q_size == low_q_size )); then
  echo "La qualita JPG non sembra influire sulla dimensione finale." >&2
  exit 1
fi

echo "OK: test CLI completati in $TMP_DIR"
