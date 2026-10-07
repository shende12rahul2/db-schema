# Examples by change type

Each page has 2-3 copy-paste examples. Each page and its code live on the matching branch until you merge it (the links below work after the merge). Merge in this order so version numbers stay sequential; all six merge cleanly together (verified with a trial merge and lint) (merge in this order so version numbers stay sequential):

| Branch | Change type | Versions | Page |
|---|---|---|---|
| `example/tables` | add column, widen column, new table with FK | V006-V008 | [tables.md](tables.md) |
| `example/indexes-constraints-sequences` | index, constraints with data cleanup, sequence tuning | V009-V011 | [indexes-constraints-sequences.md](indexes-constraints-sequences.md) |
| `example/data-migrations` | reference data seed, batched backfill, data fix with backup | V012-V014 | [data-migrations.md](data-migrations.md) |
| `example/views` | change a view, add a view, drop a view | V015 | [views.md](views.md) |
| `example/functions-procedures` | change a function, add a function, extend a procedure (needs a column) | V016 | [functions-procedures.md](functions-procedures.md) |
| `example/packages-types-triggers` | extend a package, add a trigger, evolve an object type | none | [packages-types-triggers.md](packages-types-triggers.md) |

Workflow for every example: `new_migration.sh` (if the change is versioned) -> edit -> `lint_migrations.sh` -> `migrate.sh deploy` -> PR.
