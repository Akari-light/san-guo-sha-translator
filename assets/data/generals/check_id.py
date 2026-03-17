#!/usr/bin/env python3
"""
convert_ids.py — Convert dot-prefixed general IDs to underscore format.

  jx.SHU001         -> JX_SHU001
  jx.SHU004_臥龍    -> JX_SHU004_臥龍     (non-ASCII suffix preserved verbatim)
  mo.QUN003_skin1   -> MO_QUN003_skin1    (lowercase suffix preserved verbatim)
  mo.wei001         -> MO_WEI001
  YJ.SHU001         -> YJ_SHU001          (any prefix works — not limited to jx/mo)

  LE001             -> LE001              (no dot → unchanged)
  SP008-1           -> SP008-1            (no dot → unchanged)
  e.g. something    -> e.g. something     (no digit after dot → unchanged)

Usage:
    # Dry-run — preview every change, write nothing
    python3 convert_ids.py --dry-run path/to/generals/

    # Apply in-place to all JSON files in a directory (recursive)
    python3 convert_ids.py path/to/generals/

    # Apply to specific files
    python3 convert_ids.py limit_break.json demon.json skin.json
"""

import argparse
import json
import sys
from pathlib import Path
import re

# Match:  <prefix>.<faction><serial>[<suffix>]
#   prefix   = 1-6 ASCII letters          e.g.  jx  mo  YJ
#   faction  = 1+ ASCII letters           e.g.  SHU  WEI  QUN  wei
#   serial   = 1+ digits                  e.g.  001  019
#   suffix   = optional, starts with - or _, no whitespace or dots
#              e.g.  _skin1  _臥龍  -1  -2
ID_RE = re.compile(
    r'\b'
    r'([A-Za-z]{1,6})'
    r'\.'
    r'([A-Za-z]+)'
    r'(\d+)'
    r'([-_][^\s.]*)?'
)


def convert_id(raw: str) -> str:
    def _replace(m):
        return f"{m.group(1).upper()}_{m.group(2).upper()}{m.group(3)}{m.group(4) or ''}"
    return ID_RE.sub(_replace, raw)


def convert_value(val):
    if isinstance(val, str):
        return convert_id(val)
    if isinstance(val, dict):
        return {k: convert_value(v) for k, v in val.items()}
    if isinstance(val, list):
        return [convert_value(item) for item in val]
    return val


def process_file(path, dry_run):
    try:
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"  SKIP (parse error): {path.name} — {e}")
        return 0
    except Exception as e:
        print(f"  SKIP (read error): {path.name} — {e}")
        return 0

    changes = []

    def _track(val):
        if isinstance(val, str):
            converted = convert_id(val)
            if converted != val:
                changes.append((val, converted))
            return converted
        if isinstance(val, dict):
            return {k: _track(v) for k, v in val.items()}
        if isinstance(val, list):
            return [_track(item) for item in val]
        return val

    converted_data = _track(data)

    if not changes:
        print(f"  no changes:  {path.name}")
        return 0

    prefix = "[DRY RUN] " if dry_run else ""
    print(f"  {prefix}CHANGED: {path.name} — {len(changes)} replacement(s)")
    for old, new in sorted(set(changes)):
        print(f"    {old!r:36s}  ->  {new!r}")

    if not dry_run:
        path.write_text(json.dumps(converted_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return len(changes)


def collect_json_files(targets):
    result = []
    for t in targets:
        p = Path(t)
        if p.is_dir():
            result.extend(sorted(p.rglob("*.json")))
        elif p.is_file() and p.suffix == ".json":
            result.append(p)
        else:
            print(f"WARNING: {t!r} not a .json file or directory — skipped", file=sys.stderr)
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Convert dot-prefixed general IDs (jx.SHU001 → JX_SHU001) in JSON files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("targets", nargs="+", metavar="PATH")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview changes without writing any files.")
    args = parser.parse_args()

    files = collect_json_files(args.targets)
    if not files:
        print("No JSON files found.", file=sys.stderr)
        sys.exit(1)

    total = sum(process_file(f, args.dry_run) for f in files)
    print()
    if args.dry_run:
        print(f"DRY RUN complete — {total} replacement(s) across {len(files)} file(s). Nothing written.")
    else:
        print(f"Done — {total} replacement(s) across {len(files)} file(s).")


if __name__ == "__main__":
    main()