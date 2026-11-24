#!/usr/bin/env python3
"""Report static UI labels missing from the Simplified Chinese strings table."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
source = "\n".join(path.read_text() for path in (root / "PostManage/Sources").glob("*.swift"))
strings = (root / "PostManage/Resources/zh-Hans.lproj/Localizable.strings").read_text()
keys = set(re.findall(r'^"((?:\\.|[^"])*)"\s*=', strings, re.MULTILINE))
ui_calls = (
    "Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField",
    "ContentUnavailableView", r"\.help", r"\.alert", r"\.accessibilityLabel",
    "L10n.string", "L10n.format",
)
pattern = r"(?:" + "|".join(ui_calls) + r')\(\s*"((?:\\.|[^"\\])*)"'
literal_keys = set(re.findall(pattern, source))
intentional = {"", "PostManage", "简体中文"}
missing = sorted(key for key in literal_keys - keys - intentional if r"\(" not in key)

if missing:
    print("Missing zh-Hans UI strings:")
    for key in missing:
        print(f"  {key}")
    sys.exit(1)
print(f"Localization audit passed: {len(literal_keys - intentional)} static UI labels covered.")
