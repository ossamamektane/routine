"""Lists every user-facing string in the Swift code, converted to localization keys.

Run from the repository root: python3 scripts/extract_strings.py
Prints JSON: [{"key": ..., "file": ..., "line": ...}, ...]
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Routine")

STRING = r'"((?:[^"\\]|\\.)*)"'
CALLS = [
    r'\bText\(\s*' + STRING,
    r'\bLabel\(\s*' + STRING,
    r'\bButton\(\s*' + STRING,
    r'\bSection\(\s*' + STRING,
    r'\bToggle\(\s*' + STRING,
    r'\bPicker\(\s*' + STRING,
    r'\bDatePicker\(\s*' + STRING,
    r'\bStepper\(\s*' + STRING,
    r'\bLabeledContent\(\s*' + STRING,
    r'\bTextField\(\s*' + STRING,
    r'\bMenu\(\s*' + STRING,
    r'\bContentUnavailableView\(\s*' + STRING,
    r'\.navigationTitle\(\s*' + STRING,
    r'\.confirmationDialog\(\s*' + STRING,
    r'\.alert\(\s*' + STRING,
    r'\bString\(localized:\s*' + STRING,
    r'\bLocalizedStringKey\(\s*' + STRING,
    r'\.value\(\s*' + STRING,
    r'\bprompt:\s*' + STRING,
    r'\btitle:\s*' + STRING,
    r'\btext:\s*' + STRING,
    r'\blabel:\s*' + STRING,
    r'\bdescription:\s*' + STRING,
    r'\bentrySection\(\s*' + STRING,
    r'\bdatePicker\(\s*' + STRING,
    r'\bbreakdownTitle:\s*' + STRING,
    r'\bafterDoneTitle:\s*' + STRING,
]
# Literals returned from properties typed LocalizedStringKey.
RETURNS = [r'\breturn\s+' + STRING, r'\?\s*' + STRING + r'\s*:\s*' + STRING]

INT_NAMES = {"n", "count", "done", "total", "remaining", "left", "k", "number", "days", "hours", "minutes", "goal", "quota", "index", "weekCount", "todayCount"}


def interpolation_spec(expr: str) -> str:
    e = expr.strip()
    if e.startswith("Format.") or "displayTitle" in e or e.endswith("title") or e.endswith("name") or e.endswith("label") or e.endswith("Text") or "formatted(" in e or "String(" in e:
        return "%@"
    last = e.split(".")[-1]
    if last in INT_NAMES or last in {"day", "goalCount", "every", "progress"}:
        return "%lld"
    return "%@?" + e


def to_key(literal: str):
    out, i, specs = "", 0, []
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                if literal[j] == "(":
                    depth += 1
                elif literal[j] == ")":
                    depth -= 1
                j += 1
            expr = literal[i + 2 : j - 1]
            spec = interpolation_spec(expr)
            specs.append((expr, spec))
            out += spec if not spec.startswith("%@?") else "%@"
            i = j
        elif literal.startswith('\\"', i):
            out += '"'
            i += 2
        elif literal.startswith("\\n", i):
            out += "\n"
            i += 2
        elif literal.startswith("\\\\", i):
            out += "\\"
            i += 2
        else:
            out += literal[i]
            i += 1
    return out, specs


def lprojless_files():
    for base, _, files in os.walk(ROOT):
        for f in files:
            if f.endswith(".swift"):
                yield os.path.join(base, f)


SKIP = re.compile(r'^[a-z0-9_.|\-]*[._|\-][a-z0-9_.|\-]*$|^[A-Z]{3}$|^#|^\s*$|^[%@ ·()]+$')

results, unknown = {}, []
for path in sorted(lprojless_files()):
    text = open(path, encoding="utf-8").read()
    rel = os.path.relpath(path, ROOT)
    patterns = CALLS + (RETURNS if ("Views" in rel or "Prefs" in rel or "Components" in rel) else [])
    for pattern in patterns:
        for m in re.finditer(pattern, text):
            for literal in m.groups():
                if literal is None:
                    continue
                key, specs = to_key(literal)
                localized = pattern.startswith(r'\bString(localized')
                if not localized and SKIP.search(key):
                    continue
                line = text.count("\n", 0, m.start()) + 1
                for expr, spec in specs:
                    if spec.startswith("%@?"):
                        unknown.append((rel, line, expr))
                results.setdefault(key, f"{rel}:{line}")

json.dump([{"key": k, "where": v} for k, v in sorted(results.items())], sys.stdout, ensure_ascii=False, indent=1)
sys.stderr.write(f"\n{len(results)} keys\n")
for u in unknown:
    sys.stderr.write(f"UNSURE TYPE {u}\n")
