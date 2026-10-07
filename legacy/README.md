# legacy

The original one-object-per-file layout (`Function/`, `Package/`, `Table/`, ...), kept **unchanged for reference only**.
Nothing in `db/` reads this folder. The live, versioned source of truth is [`../db`](../db).

Where things went:

| legacy | db |
|---|---|
| `Sequence/`, `Table/` | `db/baseline/` (frozen) + `db/migrations/` for every later change |
| `Type/` | `db/repeatable/01_types/` |
| `Type_Body/` | `db/repeatable/02_type_bodies/` |
| `Function/` | `db/repeatable/03_functions/` |
| `Procedure/` | `db/repeatable/04_procedures/` |
| `Package/` | `db/repeatable/05_package_specs/` |
| `Package_Body/` | `db/repeatable/06_package_bodies/` |
| `Trigger/` | `db/repeatable/07_triggers/` |
| `View/` | `db/repeatable/08_views/` |

Do not edit files here; changes made here will not reach any database.
