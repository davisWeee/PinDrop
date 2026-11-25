#!/usr/bin/env python3
"""Build RoamControl/Resources/Localizable.xcstrings + InfoPlist.xcstrings from scripts/i18n/translations/*.py.

Each translation module defines T = {english_key: (ar, fr, de, he, ja, zh-Hans, es, zh-Hant, vi)}.
English (source language) uses the key itself as the value.
Run:  python3 scripts/i18n/build_catalog.py        (writes the catalogs)
      python3 scripts/i18n/build_catalog.py --check (also lists literal keys in Swift code without translations)
"""
import importlib, json, pkgutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import translations  # noqa: E402
from translations import LANGS  # noqa: E402

OUT_DIR = ROOT / "RoamControl/Resources"


def load_all():
    merged = {}
    for m in pkgutil.iter_modules(translations.__path__):
        mod = importlib.import_module(f"translations.{m.name}")
        for k, v in mod.T.items():
            assert len(v) == len(LANGS), (m.name, k, len(v))
            if k in merged and merged[k] != v:
                print(f"warning: duplicate key with different value: {k!r} ({m.name})", file=sys.stderr)
            merged[k] = v
    return merged


def entry(values):
    locs = {"en": None}
    d = {"extractionState": "manual", "localizations": {}}
    for lang, val in zip(LANGS, values):
        d["localizations"][lang] = {"stringUnit": {"state": "translated", "value": val}}
    return d


def write_catalog(path, entries):
    doc = {"sourceLanguage": "en", "strings": dict(sorted(entries.items())), "version": "1.0"}
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8")


# Literal keys the extractor flags but that are NOT user-facing text: brand name, bare placeholders,
# GPX/XML fragments and namespaces, technical identifiers, file names and number fallbacks.
IGNORE_EXACT = {
    "PinDrop", "GB", "UTF-8", "authTag", "PinDrop-route",
    "%@", "%lld", "%@|%@", "%@-%@", "%lld s", "%@ · %lld%%",
}
IGNORE_PATTERNS = (
    r"^https?://",                 # XML namespaces / schema locations
    r"^\s*</?[A-Za-z]",            # XML tags (<trkpt ...>, <time>%@</time>, </trkpt>)
    r"^\s*, elevation\)\)</ele>",  # tail of an <ele> interpolation fragment
    r"^<ele>",                      # head of an <ele> interpolation fragment
    r"^&[a-z]+;$",                  # XML entities
)


def is_ignored(key):
    import re
    return key in IGNORE_EXACT or any(re.search(p, key) for p in IGNORE_PATTERNS)


INFOPLIST = {
    "CFBundleDisplayName": ("PinDrop",) * 9,
    "NSLocalNetworkUsageDescription": (
        "يستخدم PinDrop الشبكة المحلية للإقران بهذا الـ iPhone والتحكم فيه بأمان عبر LocalDevVPN.",
        "PinDrop utilise le réseau local pour s’associer à cet iPhone et le contrôler en toute sécurité via LocalDevVPN.",
        "PinDrop verwendet das lokale Netzwerk, um dieses iPhone über LocalDevVPN sicher zu koppeln und zu steuern.",
        "PinDrop משתמש ברשת המקומית כדי להתאים ולשלוט ב‑iPhone הזה בצורה מאובטחת דרך LocalDevVPN.",
        "PinDropは、LocalDevVPNを介してこのiPhoneを安全にペアリングし操作するために、ローカルネットワークを使用します。",
        "PinDrop 使用本地网络，通过 LocalDevVPN 与这台 iPhone 安全配对并对其进行控制。",
        "PinDrop usa la red local para emparejarse con este iPhone y controlarlo de forma segura mediante LocalDevVPN.",
        "PinDrop 使用本機網路，透過 LocalDevVPN 與這部 iPhone 安全配對並對其進行控制。",
        "PinDrop dùng mạng cục bộ để ghép đôi và điều khiển iPhone này một cách an toàn qua LocalDevVPN.",
    ),
    "NSLocationWhenInUseUsageDescription": (
        "يستخدم PinDrop موقعك لعرض موقعك الحقيقي وتوسيط الخريطة عليه بعد توقف جلسة الموقع.",
        "PinDrop utilise votre position pour afficher et recentrer la carte sur votre position réelle après l’arrêt d’une session de localisation.",
        "PinDrop verwendet Ihren Standort, um Ihre echte Position anzuzeigen und die Karte darauf zu zentrieren, nachdem eine Standortsitzung beendet wurde.",
        "PinDrop משתמש במיקום שלך כדי להציג את המיקום האמיתי שלך ולמרכז עליו את המפה לאחר שסשן מיקום נעצר.",
        "PinDropは、位置情報セッションの停止後に、実際の位置を表示して地図をその位置に合わせるために、お使いの位置情報を使用します。",
        "PinDrop 会使用您的位置，在定位会话停止后显示并将地图居中到您的真实位置。",
        "PinDrop usa tu ubicación para mostrar y centrar el mapa en tu posición real después de que se detenga una sesión de ubicación.",
        "PinDrop 會使用您的位置，在定位工作階段停止後顯示並將地圖置中到您的真實位置。",
        "PinDrop dùng vị trí của bạn để hiển thị và căn giữa bản đồ vào vị trí thật sau khi một phiên vị trí dừng lại.",
    ),
}


def main():
    merged = load_all()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_catalog(OUT_DIR / "Localizable.xcstrings", {k: entry(v) for k, v in merged.items()})
    write_catalog(OUT_DIR / "InfoPlist.xcstrings", {k: entry(v) for k, v in INFOPLIST.items()})
    print(f"Localizable.xcstrings: {len(merged)} keys x {len(LANGS)+1} languages")

    if "--check" in sys.argv:
        sys.path.insert(0, str(HERE))
        import extract_keys
        missing = [(k, w) for k, w in extract_keys.main().items() if k not in merged and not is_ignored(k)]
        for k, w in missing:
            print(f"MISSING  {k}   [{w}]")
        print(f"{len(missing)} literal keys without translations")


if __name__ == "__main__":
    main()
