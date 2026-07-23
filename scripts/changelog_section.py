#!/usr/bin/env python3
"""Print the CHANGELOG section for a release tag.

The release workflow uses this so the GitHub Release notes are always exactly what the CHANGELOG
says — no second, hand-written copy that can drift from it.

    changelog_section.py CHANGELOG.md 0.51.0
    changelog_section.py Android/CHANGELOG.md android-0.9.0

Exits non-zero when the version has no section, which fails the release rather than publishing a
release with empty notes.
"""

import re
import sys


def section_for(changelog: str, version: str) -> str | None:
    """Return the body of the `## [version]` section, without its heading."""
    heading = re.compile(r"^##\s*\[" + re.escape(version) + r"\]", re.MULTILINE)
    match = heading.search(changelog)
    if not match:
        return None

    rest = changelog[match.end():]
    # The section runs until the next `## [` heading, or to the end of the file.
    next_heading = re.search(r"^##\s*\[", rest, re.MULTILINE)
    body = rest[: next_heading.start()] if next_heading else rest

    # Drop the remainder of the heading line (the date) and surrounding blank lines.
    body = body.split("\n", 1)[1] if "\n" in body else ""
    return body.strip()


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <changelog> <tag>", file=sys.stderr)
        return 2

    path, tag = sys.argv[1], sys.argv[2]
    # Android tags carry the platform prefix; the CHANGELOG entries do not.
    version = tag.removeprefix("android-")

    with open(path, encoding="utf-8") as handle:
        changelog = handle.read()

    body = section_for(changelog, version)
    if not body:
        print(f"No CHANGELOG section found for [{version}] in {path}", file=sys.stderr)
        return 1

    print(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
