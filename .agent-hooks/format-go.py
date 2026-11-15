#!/usr/bin/env python3
"""Format a Go file edited by a supported coding-agent tool."""

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PATCH_FILE = re.compile(r"^\*\*\* (?:Update|Add|Move to): (.+)$", re.MULTILINE)


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 0

    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0

    file_names = []
    direct_path = tool_input.get("file_path") or tool_input.get("path")
    if isinstance(direct_path, str):
        file_names.append(direct_path)
    for key in ("patch", "command"):
        patch = tool_input.get(key)
        if isinstance(patch, str):
            file_names.extend(PATCH_FILE.findall(patch))

    paths = set()
    for file_name in file_names:
        if not file_name.endswith(".go"):
            continue

        try:
            path = Path(file_name)
            if not path.is_absolute():
                path = ROOT / path
            path = path.resolve(strict=True)
            relative_path = path.relative_to(ROOT).as_posix()
        except (OSError, ValueError):
            continue

        if path.is_file() and not relative_path.startswith(".agents/skills/"):
            paths.add(path)

    if not paths:
        return 0

    for path in sorted(paths):
        try:
            subprocess.run(["gofmt", "-w", str(path)], check=True, timeout=5)
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            print(f"Go formatting hook failed: {error}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
