#!/usr/bin/env bash
# normalize-encoding.sh — repair common encoding corruption in shared .ai/ files.
#
# Repairs, in order:
#   - UTF-16LE (with BOM)  -> UTF-8
#   - UTF-8 BOM            -> stripped
#   - cp1252 em-dash (0x97) -> UTF-8 em-dash (U+2014)
#   - NUL bytes (0x00)     -> '0' (common in corrupted commit SHAs)
#
# Any other invalid UTF-8 byte is unrepairable and causes a non-zero exit.
#
# Usage: bash .ai/tools/normalize-encoding.sh <file>...
# Exit: 0 if every file is valid UTF-8 after repair.
#       1 if any file could not be fully repaired.
#       2 if arguments are missing.
set -u

if [ "$#" -eq 0 ]; then
    echo "normalize-encoding: missing file argument(s)" >&2
    exit 2
fi

python3 - "$@" <<'PY'
import sys


def repair(path):
    with open(path, 'rb') as f:
        raw = f.read()

    changes = []

    # 1. UTF-16LE with BOM -> UTF-8.
    if raw.startswith(b'\xff\xfe'):
        try:
            raw = raw.decode('utf-16-le').encode('utf-8')
            changes.append('UTF-16LE->UTF-8')
        except UnicodeError as e:
            return False, f'UTF-16LE decode failed: {e}'

    # 2. Strip UTF-8 BOM.
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
        changes.append('stripped-UTF-8-BOM')

    # 3. NUL bytes are valid UTF-8 but corrupt text tools; replace with '0'.
    if b'\x00' in raw:
        raw = raw.replace(b'\x00', b'0')
        changes.append('NUL')

    # 4. Try strict UTF-8; if good, write back any repaired bytes.
    try:
        raw.decode('utf-8')
        if changes:
            with open(path, 'wb') as f:
                f.write(raw)
        return True, ', '.join(changes) if changes else 'no change'
    except UnicodeDecodeError:
        pass

    # 5. Decode with surrogateescape so each invalid byte surfaces as U+DC80..U+DCFF.
    text = raw.decode('utf-8', errors='surrogateescape')
    repaired = []
    bad_bytes = set()
    for ch in text:
        code = ord(ch)
        if 0xDC80 <= code <= 0xDCFF:
            byte = code - 0xDC00
            bad_bytes.add(byte)
            if byte == 0x97:
                repaired.append('\u2014')  # em-dash
                changes.append('cp1252-em-dash')
            else:
                return False, f'unrepairable byte 0x{byte:02x}'
        else:
            repaired.append(ch)

    out = ''.join(repaired).encode('utf-8')
    with open(path, 'wb') as f:
        f.write(out)
    summary = ', '.join(sorted(set(changes)))
    return True, summary


fail = 0
for path in sys.argv[1:]:
    ok, msg = repair(path)
    print(f'normalize-encoding: {path}: {msg}')
    if not ok:
        fail += 1

sys.exit(1 if fail else 0)
PY
