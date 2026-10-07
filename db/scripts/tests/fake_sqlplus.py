#!/usr/bin/env python3
"""Test double for sqlplus: emulates ONLY what migrate.sh asks (history/lock bookkeeping, inventory, identity, pre-checks).
It lets scripts/tests/test_runner.sh exercise the runner's decisions without Oracle. It says nothing about the SQL itself."""
import sys, os, re, json
STATE = os.environ["FAKE_STATE"]
HT = os.environ.get("FAKE_HIST", "schema_version")
LT = HT + "_lock"
DEF = {"hist": [], "rank": 0, "sv": False, "lock": None, "objs": [], "tables": False, "invalid": [],
       "ident": "OK|FREEPDB1|BANK|FREE", "pre": {}, "inv_remove": [], "inv_add": [], "col_types": {}, "log": []}
st = json.load(open(STATE)) if os.path.exists(STATE) else dict(DEF)
for k, v in DEF.items(): st.setdefault(k, v)
def save(): json.dump(st, open(STATE, "w"))
DIRS = {"01_types": "TYPE", "02_type_bodies": "TYPE BODY", "03_functions": "FUNCTION", "04_procedures": "PROCEDURE",
        "05_package_specs": "PACKAGE", "06_package_bodies": "PACKAGE BODY", "07_triggers": "TRIGGER", "08_views": "VIEW"}
src = sys.stdin.read(); out = []; H = st["hist"]

def insert_rows(sql):
    for v in re.findall(r"INSERT INTO %s \([^)]*\) VALUES \((.*?)\);" % HT, sql):
        p = [x.strip().strip("'") for x in v.split(",")]
        st["rank"] += 1
        H.append({"rank": st["rank"], "type": p[0], "version": None if p[1] == "NULL" else p[1], "desc": p[2],
                  "script": p[3], "checksum": p[4], "status": p[6]})

if re.search(r"^@", src, re.M):                                   # a script run (run_script / precheck)
    for line in src.splitlines():
        if line.startswith("PROMPT "): out.append(line[7:])
        elif line.startswith("@"):
            f = line[1:].strip()
            if f.endswith(".pre.sql"):
                out += st["pre"].get(os.path.basename(f), []); continue
            body = open(f).read()
            st["log"].append(f)
            if "MOCK_FAIL" in body:
                out.append("ORA-00904: mock failure"); print("\n".join(out)); save(); sys.exit(174)
            if "V001__" in f or "CREATE TABLE" in body.upper(): st["tables"] = True
            d = os.path.basename(os.path.dirname(f))
            if d in DIRS:
                o = [DIRS[d], os.path.basename(f).rsplit(".", 1)[0].upper()]
                if o not in st["objs"]: st["objs"].append(o)
            m = re.search(r"MOCK_DROP_OBJECT (\S+) (\S+)", body)
            if m: st["objs"] = [x for x in st["objs"] if x != [m.group(1), m.group(2)]]
            out.append("done")
    print("\n".join(out)); save(); sys.exit(0)

sql = src
if "SYS_CONTEXT('USERENV','CON_NAME')" in sql: out.append(st["ident"])
elif "installed_rank NUMBER GENERATED" in sql: st["sv"] = True
elif "INSERT INTO %s " % LT in sql:
    if st["lock"]: out.append("ORA-00001: unique constraint (BANK.SYS_C001) violated")
    else: st["lock"] = "BANK on testhost since 2026-01-01 00:00:00 (%s)" % re.search(r"'([a-z-]+)'\); COMMIT", sql).group(1)
elif "DELETE FROM %s WHERE id=1" % LT in sql: st["lock"] = None
elif "FROM %s WHERE id=1" % LT in sql:
    if st["lock"]: out.append(st["lock"])
elif "user_tables WHERE table_name NOT IN" in sql: out.append("12" if st["tables"] else "0")
elif re.search(r"user_tables WHERE table_name='%s'" % HT.upper(), sql): out.append("1" if st["sv"] else "0")
elif re.search(r"COUNT\(\*\) FROM user_tables;", sql): out.append(str(12 * int(st["tables"]) + 2 * int(st["sv"])))
elif "INSERT INTO %s " % HT in sql: insert_rows(sql)
elif re.search(r"DELETE FROM %s WHERE version=" % HT, sql):
    v = re.search(r"version='(\w+)'", sql).group(1)
    st["hist"] = [r for r in H if not (r["version"] == v and r["status"] in ("FAILED", "UNDONE"))]
elif "DELETE FROM %s WHERE status='FAILED'" % HT in sql: st["hist"] = [r for r in H if r["status"] != "FAILED"]
elif "SET status='UNDONE'" in sql:
    v = re.search(r"version='(\w+)'", sql).group(1)
    for r in H:
        if r["version"] == v: r["status"] = "UNDONE"
elif "COUNT(*) FROM %s;" % HT in sql: out.append(str(len(H)))
elif "PARTITION BY script" in sql:
    latest = {}
    for r in H:
        if r["type"] == "REPEATABLE": latest[r["script"]] = r
    out += ["%s|%s|%s" % (r["script"], r["status"], r["checksum"]) for r in latest.values()]
elif "type IN ('BASELINE','VERSIONED') ORDER BY installed_rank" in sql:
    out += ["%s|%s|%s" % (r["version"], r["status"], r["checksum"]) for r in H if r["type"] in ("BASELINE", "VERSIONED")]
elif "MAX(TO_NUMBER(version))" in sql:
    vs = [int(r["version"]) for r in H if r["type"] in ("BASELINE", "VERSIONED") and r["status"] == "SUCCESS"]
    out.append("%03d" % max(vs) if vs else "")
elif "ORDER BY installed_rank DESC) WHERE ROWNUM=1" in sql:
    c = [r for r in H if r["type"] == "VERSIONED" and r["status"] == "SUCCESS"]
    if c: out.append(c[-1]["version"])
elif "'TABLE|'||table_name" in sql:
    if st["tables"]:
        for line in open("baseline/V001.manifest"):
            line = line.rstrip("\n")
            if re.match(r"(TABLE|SEQUENCE)\|", line) or line.startswith("COLUMN|"):
                if line.startswith("COLUMN|"):
                    p = line.split("|"); p[3] = st["col_types"].get("|".join(p[1:3]), p[3]); line = "|".join(p)
                if line not in st["inv_remove"]: out.append(line)
        out += st["inv_add"]
    out += ["OBJECT|%s|%s|%s" % (t, n, "INVALID" if "%s %s" % (t, n) in st["invalid"] else "VALID") for t, n in st["objs"]]
elif "object_type||'|'||object_name FROM user_objects" in sql: out += ["%s|%s" % (t, n) for t, n in st["objs"]]
elif "object_type||' '||object_name FROM user_objects WHERE status='INVALID'" in sql: out += st["invalid"]
elif "RPAD(installed_rank" in sql:
    out += ["%-4s%-6s%-11s%-9s%s" % (r["rank"], r["version"] or "-", r["type"], r["status"], r["desc"]) for r in H if r["type"] != "REPEATABLE"]
elif "NVL(version,'repeatable')" in sql:
    out += ["  %s  %s" % (r["version"] or "repeatable", r["script"]) for r in H if r["status"] == "FAILED"]
elif "'OK' FROM dual" in sql: out.append("OK")
save(); print("\n".join(out))
