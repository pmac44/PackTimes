#!/usr/bin/env python3
"""
Keep PackTimes' CLAUDE.md short by retiring old version entries to an archive.

WHAT IT DOES
  CLAUDE.md holds a "Recent version log" between two HTML comment markers.
  This script keeps the newest N entries there (default 10) and moves every
  older one, unchanged, to the top of CLAUDE-log-archive.md.

WHY IT EXISTS
  On 2 Sep 2026 CLAUDE.md had reached 492 kB, of which 95% was version log and
  the durable reference sat at the very bottom where nothing read it. Trimming
  by hand is the kind of job that never gets done, so it is a script.

USAGE
  python trim_log.py                # dry run: says what it would move, writes nothing
  python trim_log.py --write        # actually move them
  python trim_log.py --keep 5 --write

SAFETY
  Never deletes anything - entries are moved, not dropped.
  Writes CLAUDE.md.bak and CLAUDE-log-archive.md.bak before changing either.
  Refuses to run if the markers are missing or the entry text would not survive.
"""

import argparse, os, re, sys

MAIN    = "CLAUDE.md"
ARCHIVE = "CLAUDE-log-archive.md"
START   = "<!-- VERSION-LOG-START"
END     = "<!-- VERSION-LOG-END -->"
INSERT  = "<!-- ARCHIVE-INSERT-POINT"
ENTRY   = re.compile(r"^### v\d")


def die(msg):
    print("STOP: " + msg)
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", type=int, default=10, help="versions to leave in CLAUDE.md")
    ap.add_argument("--write", action="store_true", help="apply the change")
    ap.add_argument("--dir", default=os.path.dirname(os.path.abspath(__file__)))
    a = ap.parse_args()

    main_path = os.path.join(a.dir, MAIN)
    arch_path = os.path.join(a.dir, ARCHIVE)
    for p in (main_path, arch_path):
        if not os.path.exists(p):
            die("cannot find %s" % p)

    text = open(main_path, encoding="utf-8").read()
    lines = text.split("\n")

    s = next((i for i, l in enumerate(lines) if l.startswith(START)), None)
    e = next((i for i, l in enumerate(lines) if l.startswith(END)), None)
    if s is None or e is None or e <= s:
        die("the VERSION-LOG markers are missing or out of order in %s. "
            "Nothing was changed - put them back before running this again." % MAIN)

    starts = [i for i in range(s, e) if ENTRY.match(lines[i])]
    if not starts:
        print("No version entries found between the markers. Nothing to do.")
        return

    print("%d version entries in %s, keeping %d." % (len(starts), MAIN, a.keep))
    if len(starts) <= a.keep:
        print("Nothing to move.")
        return

    cut = starts[a.keep]
    moving = [lines[i][4:78] for i in starts[a.keep:]]
    print("Would move %d:" % len(moving) if not a.write else "Moving %d:" % len(moving))
    for m in moving:
        print("   " + m)

    retired = "\n".join(lines[cut:e]).strip("\n")
    new_main = "\n".join(lines[:cut]).rstrip("\n") + "\n\n" + "\n".join(lines[e:])

    arch = open(arch_path, encoding="utf-8").read()
    ai = next((i for i, l in enumerate(arch.split("\n")) if l.startswith(INSERT)), None)
    if ai is None:
        die("the ARCHIVE-INSERT-POINT marker is missing from %s. Nothing was changed." % ARCHIVE)
    al = arch.split("\n")
    new_arch = "\n".join(al[:ai + 1]) + "\n\n" + retired + "\n\n" + "\n".join(al[ai + 1:])

    # every retired line must land in the archive before we shorten the main file
    for l in retired.split("\n"):
        if l.strip() and l not in new_arch:
            die("a retired line did not survive the move. Nothing was changed.")

    if not a.write:
        print("\nDRY RUN - nothing written. Re-run with --write.")
        return

    open(main_path + ".bak", "w", encoding="utf-8", newline="").write(text)
    open(arch_path + ".bak", "w", encoding="utf-8", newline="").write(arch)
    open(arch_path, "w", encoding="utf-8", newline="").write(new_arch)
    open(main_path, "w", encoding="utf-8", newline="").write(new_main)
    print("\nDone. %s is now %d bytes. Backups written as .bak beside each file."
          % (MAIN, os.path.getsize(main_path)))


if __name__ == "__main__":
    main()
