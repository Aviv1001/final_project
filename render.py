#!/usr/bin/env python3
"""Builds the library page. Reads every transcript, writes one HTML file."""

import fcntl
import html
import sys
from pathlib import Path

HEAD = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lecture library</title>
<style>
body { font-family: system-ui, sans-serif; max-width: 50rem;
       margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
summary { font-size: 1.2rem; padding: 0.6rem 0; cursor: pointer; }
details { border-bottom: 1px solid #ccc; }
.summary { background: #f4f6fa; padding: 0.8rem; white-space: pre-wrap; }
.transcript { white-space: pre-wrap; }
</style></head><body>
<h1>Lecture library</h1>
"""

BLOCK = """<details><summary>{name}</summary>
<div class="summary">{summary}</div>
<p class="transcript">{transcript}</p>
</details>
"""

FOOT = "</body></html>\n"


def read(path):
    # Not every lecture has a summary, so a missing file is not an error.
    return path.read_text(encoding="utf-8").strip() if path.is_file() else ""


def rebuild(library):
    page = HEAD
    lectures = [d for d in library.iterdir() if d.is_dir()]
    for lecture in sorted(lectures, reverse=True):
        page += BLOCK.format(
            name=html.escape(lecture.name),
            summary=html.escape(read(lecture / "summary.txt")),
            transcript=html.escape(read(lecture / "transcript.txt")),
        )
    # nginx is reading this file while we write it, so build it under a
    # different name and rename at the end. A rename is instant.
    temp = library / "index.html.new"
    temp.write_text(page + FOOT, encoding="utf-8")
    temp.replace(library / "index.html")


def main(library):
    # One rebuild at a time: several workers can call this together.
    with open(library / ".render.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        rebuild(library)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: render.py LIBRARY_DIR")
    main(Path(sys.argv[1]))
