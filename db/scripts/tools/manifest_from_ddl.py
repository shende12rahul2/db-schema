#!/usr/bin/env python3
"""Generate a baseline manifest from DDL files (offline; no database needed).

  python3 scripts/tools/manifest_from_ddl.py <version> <ddl-root> > baseline/V<version>.manifest

<ddl-root> is the folder with the DDL exactly as deployed to clients:
  Sequence/*.seq  Table/*.tab  and code folders Type, Type_Body, Function, Procedure, Package, Package_Body, Trigger, View.
Code objects are recorded with the checksum of the matching file under repeatable/ (so that, after adoption,
only files that differ from what clients have are re-applied). A code file with no counterpart in repeatable/
(for example an empty TYPE BODY that cannot compile) is not required.

The generic alternative, run on a freshly installed reference database:  migrate.sh manifest <version>
"""
import hashlib, os, re, sys

ver, root = sys.argv[1], sys.argv[2]
db = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CODE = [("Type", "01_types", "TYPE"), ("Type_Body", "02_type_bodies", "TYPE BODY"), ("Function", "03_functions", "FUNCTION"),
        ("Procedure", "04_procedures", "PROCEDURE"), ("Package", "05_package_specs", "PACKAGE"),
        ("Package_Body", "06_package_bodies", "PACKAGE BODY"), ("Trigger", "07_triggers", "TRIGGER"), ("View", "08_views", "VIEW")]

def norm_type(t):
    return re.sub(r"\(.*\)", "", t).upper()

out = ["# Baseline manifest for V%s: what an existing database must contain to be adopted at this version." % ver,
       "# Derived from the DDL files deployed to clients (%s). Verify against a fresh install with: migrate.sh verify-baseline %s" % (os.path.basename(os.path.abspath(root)), ver),
       "SCHEMA|%s" % ver]
tables, cols = [], []
tdir = os.path.join(root, "Table")
for f in sorted(os.listdir(tdir)):
    txt = open(os.path.join(tdir, f)).read()
    m = re.search(r"CREATE TABLE\s+(\w+)\s*\((.*)\)\s*;", txt, re.S | re.I)
    name = m.group(1).upper(); tables.append(name)
    for line in m.group(2).splitlines():
        line = line.strip()
        if not line or line.upper().startswith("CONSTRAINT"):
            continue
        c = re.match(r"(\w+)\s+([A-Za-z0-9_]+(?:\s*\([^)]*\))?)", line)
        cols.append((name, c.group(1).upper(), norm_type(c.group(2))))
out += ["TABLE|%s" % t for t in sorted(tables)]
out += ["COLUMN|%s|%s|%s" % c for c in sorted(cols)]
sdir = os.path.join(root, "Sequence")
out += ["SEQUENCE|%s" % re.search(r"CREATE SEQUENCE\s+(\w+)", open(os.path.join(sdir, f)).read(), re.I).group(1).upper() for f in sorted(os.listdir(sdir))]
skipped = []
for folder, rep, typ in CODE:
    d = os.path.join(root, folder)
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        rp = os.path.join(db, "repeatable", rep, f)
        if not os.path.isfile(rp):
            skipped.append("%s %s" % (typ, os.path.splitext(f)[0].upper())); continue
        data = open(rp, "rb").read()
        if data != open(os.path.join(d, f), "rb").read():
            sys.exit("repeatable/%s/%s differs from %s/%s/%s: the manifest must describe what clients have" % (rep, f, root, folder, f))
        out.append("OBJECT|%s|%s|repeatable/%s/%s|%s" % (typ, os.path.splitext(f)[0].upper(), rep, f, hashlib.sha256(data).hexdigest()))
for s in skipped:
    out.append("# not required (no repeatable file; cannot compile as shipped): %s" % s)
print("\n".join(out))
