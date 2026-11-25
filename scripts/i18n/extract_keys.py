#!/usr/bin/env python3
"""List candidate user-facing string literals in RoamControl/**/*.swift as catalog keys.
Used to seed / audit Localizable.xcstrings (see scripts/i18n/build_catalog.py)."""
import re, glob, sys, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP_FILES = ("UsageAnalyticsService", "BackgroundTaskIdentifier", "AppLanguage.swift")
SKIP_LINE = re.compile(r'systemName|forKey|forInfoDictionaryKey|forHTTPHeaderField|^\s*import |#if|arguments|httpMethod|configuredValue|"RoamControl\.|withCString|Key = |rawValue|UIPasteboard|localizedCaseInsensitiveContains|verbatim|Identifier|^\s*//|case \w+ = "|URL\(|localdevvpn')
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')

def to_key(lit: str) -> str:
    def conv(m):
        expr = m.group(1)
        if re.search(r'Int\(|minutes|hours|remainingMinutes|number|selectedPage|pages\.count|progress|status\b', expr):
            return '%lld'
        return '%@'
    k = re.sub(r'\\\(((?:[^()]|\([^()]*(?:\([^()]*\)[^()]*)*\))*)\)', conv, lit)
    k = k.replace('\\"', '"').replace('\\\\', '\\').replace('%', '%%') if '%lld' not in k and '%@' not in k else k.replace('\\"', '"').replace('\\\\', '\\')
    return k

def main():
    keys = {}
    for f in sorted(glob.glob(str(ROOT / 'RoamControl/**/*.swift'), recursive=True)):
        if any(s in f for s in SKIP_FILES):
            continue
        for i, line in enumerate(open(f, encoding='utf-8'), 1):
            if SKIP_LINE.search(line):
                continue
            for m in LIT.finditer(line):
                lit = m.group(1)
                if not re.search(r'[A-Za-z]{2}', lit):
                    continue
                if re.fullmatch(r'[a-z0-9._\-/]+', lit) :
                    continue
                if lit in ('PinDrop', 'LocalDevVPN', 'Unknown') and False:
                    continue
                keys.setdefault(to_key(lit), f"{Path(f).name}:{i}")
    return keys

if __name__ == '__main__':
    ks = main()
    if '--json' in sys.argv:
        print(json.dumps(list(ks), ensure_ascii=False, indent=1))
    else:
        for n, (k, w) in enumerate(ks.items()):
            print(f"{n:03d} {k}   [{w}]")
        print(len(ks), file=sys.stderr)
