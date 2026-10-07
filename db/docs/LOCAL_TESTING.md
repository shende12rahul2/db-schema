# Testing on your local machine - step by step

> Your local Oracle **already has the bank tables**? Use [EXISTING_DB_TESTING.md](EXISTING_DB_TESTING.md) instead.

About 30-45 minutes the first time. Each step says what to run, what you should see, and how to check it yourself.
You change nothing on any shared database: everything runs in a local Docker container that you can wipe at any time.

---

## Step 0 - Install the prerequisites (once)

| | Windows 10/11 | macOS (Intel or Apple Silicon) | Linux |
|---|---|---|---|
| Docker | Docker Desktop (WSL 2 backend) | Docker Desktop | Docker Engine + Compose plugin |
| Git | Git for Windows (includes **Git Bash**) | Xcode CLT or Homebrew `git` | distro package |
| Shell for this guide | **Git Bash** (recommended) or cmd/PowerShell | Terminal | any |
| Free | 4 GB RAM for Docker, 5 GB disk | same | same |

Check:
```bash
docker version                  # shows Client and Server; if "Server" errors, start Docker Desktop
docker compose version          # v2.x
git --version
```

> **Windows:** run this guide in **Git Bash**, so every command below works as written. In cmd/PowerShell, replace
> `./db/scripts/migrate.sh` with `db\migrate.cmd`; the file-editing steps (heredocs `<<`) then need an editor instead.

---

## Step 1 - Get the code

```bash
git clone https://github.com/shende12rahul2/db-schema.git
cd db-schema
git checkout claude/versioned-db-structure
ls db                           # baseline  docker-compose.yml  docs  examples  migrate.cmd  migrations  repeatable  scripts
```
If you already had a clone: `git fetch origin && git checkout claude/versioned-db-structure && git pull`.

Check which database the tools will use (from `db/config/`; default = local Docker DB):
```bash
./db/scripts/migrate.sh config
```
Expected: `environment : local`, `runner : docker`, `connection : bank@//localhost:1521/FREEPDB1   password: set`.

Static checks need no database:
```bash
./db/scripts/lint_migrations.sh
```
Expected: `LINT OK`

---

## Step 2 - Start Oracle

If you followed the old instructions earlier, remove that container first: `docker rm -f oracle-free`.

```bash
./db/scripts/migrate.sh up
```
Expected: `Starting Oracle ...` then, after a few minutes the first time (image download + DB creation), `Oracle is ready.`
Later starts take about 30 seconds.

Check: `docker ps` shows `oracle-free` with status `(healthy)`.

---

## Step 3 - See what will happen (changes nothing)

```bash
./db/scripts/migrate.sh plan
```
Expected:
```
Target   : bank@//localhost:1521/FREEPDB1   DB_ENV=local
History  : none yet (fresh database) - schema_version will be created by migrate

1) Versioned migrations, run once, in this order:
   1. V001  migrations/V001__baseline.sql
   2. V002  migrations/V002__add_customer_email_verified.sql
   3. V003  migrations/V003__loan_status_check.sql
   4. V004  migrations/V004__create_customer_preferences.sql
   5. V005  migrations/V005__index_transactions_account_date.sql
   6. V006  migrations/V006__cleanup_legacy_invalid_objects.sql

2) Repeatable files, run after the migrations:
   - repeatable/01_types/t_address_typ.tps  (new)
   ... (78 files, all "(new)")

Nothing was changed. Next: 'step' (one migration) or 'migrate' (everything above).
```
Add `--sql` to also print the SQL of each migration: `./db/scripts/migrate.sh plan --sql`.

---

## Step 4 - Apply ONE migration and inspect it

```bash
./db/scripts/migrate.sh step
```
Expected: `-> applying V001  baseline` ... `V001 OK (... ms)`

Verify by hand:
```bash
./db/scripts/migrate.sh sql "SELECT table_name FROM user_tables ORDER BY 1"
./db/scripts/migrate.sh sql "SELECT version, type, status, script FROM schema_version ORDER BY installed_rank"
```
Expected: 13 tables (the 12 from the baseline + `SCHEMA_VERSION`); one history row `001 VERSIONED SUCCESS`.

Apply the next one and check its effect:
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT column_name, data_default FROM user_tab_columns WHERE table_name='CUSTOMERS' AND column_name='EMAIL_VERIFIED'"
```
Expected: `V002 OK`; one row `EMAIL_VERIFIED 'N'`.

---

## Step 5 - Apply everything else

```bash
./db/scripts/migrate.sh migrate
```
Expected (abridged):
```
-> applying V003  loan_status_check
   V003 OK
-> applying V004  create_customer_preferences
   V004 OK
-> applying V005  index_transactions_account_date
   V005 OK
-> applying V006  cleanup_legacy_invalid_objects     (does nothing on a new DB)
   V006 OK
-> applying 78 repeatable file(s):
   repeatable/01_types/t_address_typ.tps  (new)
   ...
   repeatable objects OK
MIGRATE OK
```

---

## Step 6 - Validate

```bash
./db/scripts/migrate.sh validate      # expected: VALIDATE OK
./db/scripts/migrate.sh smoke         # object counts, function results, a test insert (rolled back)
./db/scripts/migrate.sh status        # V001..V006 SUCCESS; Pending: (none); Repeatable: (none)
./db/scripts/migrate.sh plan          # both sections "(none)"
```
In the `smoke` output check:

| Check | Expected |
|---|---|
| Object counts | SEQUENCE 13, TABLE 14, TYPE 11, FUNCTION 11, PROCEDURE 11, PACKAGE 10, PACKAGE BODY 10, TRIGGER 11, VIEW 11 |
| Invalid objects / compile errors | `no rows selected` |
| EMI / masked mobile | about `10500` / `XXXXXX3210` |
| Insert test | one customer, `KYC_STATUS PENDING`, `EMAIL_VERIFIED N` |

Optional GUI: connect DBeaver / SQL Developer / VS Code to `localhost:1521`, service `FREEPDB1`, user `bank`, password `Bank123`.

**At this point the base setup works. Steps 7-11 exercise the day-to-day scenarios.**

---

## Step 7 - Change a function (repeatable object)

```bash
sed -i.bak "s/DEFAULT 'INR'/DEFAULT 'EUR'/" db/repeatable/03_functions/fn_format_currency.fnc && rm db/repeatable/03_functions/fn_format_currency.fnc.bak
./db/scripts/migrate.sh plan
```
Expected under "2) Repeatable files": only `repeatable/03_functions/fn_format_currency.fnc  (changed)`.

```bash
./db/scripts/migrate.sh migrate
./db/scripts/migrate.sh sql "SELECT fn_format_currency(1234.5) AS formatted FROM dual"
```
Expected: `-> applying 1 repeatable file(s)` ... `MIGRATE OK`; result `EUR 1,234.50`.

Put it back (this is also how a code rollback works):
```bash
git checkout -- db/repeatable/03_functions/fn_format_currency.fnc
./db/scripts/migrate.sh migrate       # re-applies the original (checksum changed again)
./db/scripts/migrate.sh sql "SELECT fn_format_currency(1234.5) AS formatted FROM dual"   # INR 1,234.50
```

---

## Step 8 - Add a new migration, verify it, undo it, re-apply it

```bash
./db/scripts/new_migration.sh "add account nickname"
cat >> db/migrations/V007__add_account_nickname.sql <<'SQL'
ALTER TABLE accounts ADD (nickname VARCHAR2(40));
SQL
cat >> db/migrations/undo/U007__add_account_nickname.sql <<'SQL'
ALTER TABLE accounts DROP COLUMN nickname;
SQL
./db/scripts/lint_migrations.sh        # LINT OK
./db/scripts/migrate.sh plan --sql     # V007 listed with its SQL
./db/scripts/migrate.sh step           # V007 OK
./db/scripts/migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='ACCOUNTS' AND column_name='NICKNAME'"
```
Expected: one row `NICKNAME`.

Undo and re-apply:
```bash
./db/scripts/migrate.sh undo           # -> undoing V007 ... V007 undone.
./db/scripts/migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='ACCOUNTS' AND column_name='NICKNAME'"   # no rows selected
./db/scripts/migrate.sh status         # V007 shows UNDONE and is pending again
./db/scripts/migrate.sh migrate        # V007 OK, MIGRATE OK
./db/scripts/migrate.sh validate       # VALIDATE OK
```
Clean up so the next steps start from V006:
```bash
./db/scripts/migrate.sh undo
rm db/migrations/V007__add_account_nickname.sql db/migrations/undo/U007__add_account_nickname.sql
./db/scripts/migrate.sh validate       # VALIDATE OK (an UNDONE version without a file is fine)
```

---

## Step 9 - A migration that fails halfway, and how to recover

Statement 1 is fine, statement 2 has a typo (`overdraft_limt`):
```bash
cp db/examples/failing/V900__broken_example.sql db/migrations/V007__broken_example.sql
cp db/examples/failing/U900__broken_example.sql db/migrations/undo/U007__broken_example.sql
./db/scripts/migrate.sh migrate
```
Expected: `ORA-00904: "OVERDRAFT_LIMT": invalid identifier`, then `x V007 FAILED ... The database may be PARTIALLY changed` with the 4 recovery steps.

See the partial state and the block:
```bash
./db/scripts/migrate.sh status         # V007 FAILED
./db/scripts/migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='ACCOUNTS' AND column_name='OVERDRAFT_LIMIT'"   # exists! (DDL auto-committed)
./db/scripts/migrate.sh migrate        # refused: "V007 is recorded as FAILED ..."
```
Recover:
```bash
./db/scripts/migrate.sh sql "ALTER TABLE accounts DROP COLUMN overdraft_limit"   # 1. undo the partial change by hand
./db/scripts/migrate.sh repair                                                   # 2. clear the FAILED row
sed -i.bak 's/overdraft_limt/overdraft_limit/' db/migrations/V007__broken_example.sql && rm db/migrations/V007__broken_example.sql.bak   # 3. fix the file
./db/scripts/migrate.sh migrate                                                  # 4. V007 OK, MIGRATE OK
./db/scripts/migrate.sh validate
```
Clean up:
```bash
./db/scripts/migrate.sh undo
rm db/migrations/V007__broken_example.sql db/migrations/undo/U007__broken_example.sql
```

---

## Step 10 - Protection against editing an applied migration

```bash
echo "-- harmless looking edit" >> db/migrations/V002__add_customer_email_verified.sql
./db/scripts/migrate.sh validate       # x V002 checksum mismatch ... VALIDATE FAILED
./db/scripts/migrate.sh migrate        # refused for the same reason
git checkout -- db/migrations/V002__add_customer_email_verified.sql
./db/scripts/migrate.sh validate       # VALIDATE OK
```

---

## Step 11 - Try an example branch

This mirrors real life: the database is at the current base version, then a branch brings new changes.
Each example branch adds migrations the others do not have, so start each one from a fresh database at the base version:
```bash
./db/scripts/migrate.sh down                    # wipe the local DB
git checkout claude/versioned-db-structure
./db/scripts/migrate.sh up
./db/scripts/migrate.sh deploy                  # DB at V006 = base version -> DEPLOY OK
git checkout example/tables                     # the branch under test
./db/scripts/migrate.sh plan --sql              # only the branch's changes: V007-V009 + its repeatable files
```
Then follow **"Try it and verify by hand"** at the end of that branch's page (`step`, the `sql` checks with expected
results, `migrate`, `validate`, `undo`). To test the next branch, repeat the block above with the other branch name.

| Branch | Page |
|---|---|
| `example/tables` | `db/docs/examples/tables.md` |
| `example/indexes-constraints-sequences` | `db/docs/examples/indexes-constraints-sequences.md` |
| `example/data-migrations` | `db/docs/examples/data-migrations.md` |
| `example/views` | `db/docs/examples/views.md` |
| `example/functions-procedures` | `db/docs/examples/functions-procedures.md` |
| `example/packages-types-triggers` | `db/docs/examples/packages-types-triggers.md` |

Why the reset: if you switch from one example branch to another on the same DB, `validate` correctly reports
"V009 was applied but its file is missing" - the database is ahead of the code you checked out.

---

## Step 12 - Repeat what CI does (fresh install + round trip)

```bash
git checkout claude/versioned-db-structure
./db/scripts/migrate.sh down
./db/scripts/migrate.sh up
./db/scripts/migrate.sh deploy         # DEPLOY OK
./db/scripts/migrate.sh undo           # V006 undone
./db/scripts/migrate.sh migrate        # MIGRATE OK
./db/scripts/migrate.sh validate       # VALIDATE OK
```

## Step 13 - Clean up

```bash
./db/scripts/migrate.sh down           # stops the container and deletes the database volume
docker image rm gvenzl/oracle-free:slim   # optional: frees about 1.5 GB
```

---

## Step 14 (optional) - Point the tools at a database you already have

```bash
cp db/config/dev.conf.example db/config/dev.conf      # edit DB_HOST / DB_PORT / DB_SERVICE / DB_USER
printf 'DB_PASSWORD=your-password\n' > db/config/dev.secret.conf   # git-ignored
./db/scripts/migrate.sh --env dev config               # password: set
./db/scripts/migrate.sh --env dev up                   # starts only the small sqlplus helper container
./db/scripts/migrate.sh --env dev plan                 # read-only
```
- Empty schema: `--env dev migrate`.
- Schema already has the tables: `plan` says so; run `--env dev baseline <version>` first (see [CONFIGURATION.md](CONFIGURATION.md) section 3).
- DB on this same machine: `DB_HOST=host.docker.internal`. Connection problems: `--env dev sql "SELECT 1 FROM dual"` shows the Oracle error.

## Step 15 (optional) - Create a new project with the same structure

```bash
./db/scripts/init_project.sh ../my-new-project mynew
cd ../my-new-project
./db/scripts/migrate.sh config          # container mynew-oracle, user mynew
./db/scripts/lint_migrations.sh         # LINT OK (empty project)
./db/scripts/new_migration.sh "create first table"
```
Running it next to this project at the same time? Set `HOST_PORT=1522` in its `db/config/default.conf` first.

## Step 16 (optional) - Adopt a database that already has the legacy objects

Re-creates the situation "the schema was deployed with the old flat files" and adopts it.
```bash
./db/scripts/migrate.sh down                         # remove the managed local DB (frees port 1521)
git checkout main                                    # old layout
docker run -d --name oracle-free -p 1521:1521 -e ORACLE_PASSWORD=Oracle123 \
  -e APP_USER=bank -e APP_USER_PASSWORD=Bank123 gvenzl/oracle-free:slim
docker logs -f oracle-free                           # wait for DATABASE IS READY TO USE!, then Ctrl+C
./scripts/deploy.sh                                  # legacy deploy; it reports errors for the 8 empty type bodies (that is the point)
git checkout claude/versioned-db-structure
./db/scripts/migrate.sh --env legacy-local up        # sqlplus helper only
./db/scripts/migrate.sh --env legacy-local sql "SELECT object_name FROM user_objects WHERE status='INVALID'"   # 8 type bodies
./db/scripts/migrate.sh --env legacy-local plan      # "none, but the schema already has tables"
./db/scripts/migrate.sh --env legacy-local migrate   # refused: baseline first
./db/scripts/migrate.sh --env legacy-local baseline  # V001 marked as applied
./db/scripts/migrate.sh --env legacy-local migrate   # V002..V006 + repeatable -> MIGRATE OK
./db/scripts/migrate.sh --env legacy-local validate  # VALIDATE OK, no invalid objects left
```
Clean up: `./db/scripts/migrate.sh --env legacy-local down` (helper) and `docker rm -f oracle-free` (the legacy DB).

## Tester checklist

- [ ] Step 2 `Oracle is ready.`
- [ ] Step 3 plan lists V001-V006 and 78 repeatable files
- [ ] Step 4 `step` applies exactly one migration; `sql` shows it
- [ ] Step 5 `MIGRATE OK`
- [ ] Step 6 `VALIDATE OK`, smoke counts match, plan shows nothing pending
- [ ] Step 7 only the edited function is re-applied
- [ ] Step 8 undo removes the column, migrate puts it back
- [ ] Step 9 failure is recorded, migrate refuses, repair + fix succeeds
- [ ] Step 10 checksum drift is detected
- [ ] Step 11 at least one example branch deploys and its checks pass
- [ ] Step 12 fresh install + undo/redo pass
- [ ] (optional) Step 14 `--env dev plan` works against your own DB
- [ ] (optional) Step 15 new project created, `config` shows its own names
- [ ] (optional) Step 16 legacy database adopted: baseline + migrate + `VALIDATE OK`

If a step's output differs, save it and the log:
`./db/scripts/migrate.sh log > migrate.log`

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot connect to the Docker daemon` / Server error in `docker version` | start Docker Desktop and wait until it is running |
| `a container named oracle-free already exists` | `docker rm -f oracle-free`, then `up` |
| `port is already allocated` (1521) | another Oracle is running locally: stop it, or change `"1521:1521"` to `"1522:1521"` in `db/docker-compose.yml` (only GUI tools use the host port) |
| `up` takes very long / container `unhealthy` | give Docker at least 4 GB RAM; `docker logs oracle-free` |
| `the Oracle container is not running` | `./db/scripts/migrate.sh up` |
| `cannot connect to Oracle with ...` right after `up` | wait 30 s and retry; check `docker logs oracle-free` ends with `DATABASE IS READY TO USE!` |
| `bash\r: No such file or directory` or `$'\r': command not found` | the clone has Windows line endings: `git add --renormalize . && git checkout -- .`, or re-clone |
| `Permission denied` running `./db/scripts/...` | `bash db/scripts/migrate.sh ...` or `chmod +x db/scripts/*.sh` |
| Git Bash: paths like `C:/Program Files/Git/workspace` in errors | update to this branch's latest `migrate.sh` (it disables MSYS path conversion) |
