# Configuration loader, sourced at top level by the db scripts (needs DB_DIR set).
#
# Precedence (later wins):
#   built-in defaults < config/default.conf < config/<DB_ENV>.conf < config/<DB_ENV>.secret.conf < environment variables
# Files are plain KEY=VALUE lines (no spaces around '=', no shell expressions) so docker compose and
# Windows migrate.cmd can read them too.

CONFIG_KEYS="PROJECT_NAME DB_ENV RUNNER DB_HOST DB_PORT DB_SERVICE DB_USER DB_PASSWORD CONN
HISTORY_TABLE MIGRATIONS_DIR UNDO_DIR REPEATABLE_DIR SMOKE_SQL LOG PROTECTED_ENVS
ORACLE_IMAGE CONTAINER_NAME HOST_PORT ORACLE_PASSWORD APP_USER APP_USER_PASSWORD COMPOSE_PROJECT
OUT_OF_ORDER CONFIRM"

# Backward compatibility: ENVIRONMENT=... used to select the environment.
if [ -z "${DB_ENV:-}" ] && [ -n "${ENVIRONMENT:-}" ]; then DB_ENV=$ENVIRONMENT; fi

# Remember values that came from the real environment; they override every file.
__cfg_env_overrides=""
for __k in $CONFIG_KEYS; do
  if [ -n "${!__k+x}" ] && [ -n "${!__k}" ]; then __cfg_env_overrides="$__cfg_env_overrides $__k"; eval "__cfg_ovr_$__k=\${$__k}"; fi
done

__cfg_load() { [ -f "$1" ] || return 0; set -a; . "$1"; set +a; }
__cfg_reapply() { local k; for k in $__cfg_env_overrides; do eval "$k=\${__cfg_ovr_$k}"; done; }

__cfg_load "$DB_DIR/config/default.conf"
__cfg_reapply                                         # an exported DB_ENV beats DB_ENV in default.conf
DB_ENV=${DB_ENV:-local}
if [ "$DB_ENV" != "default" ] && [ ! -f "$DB_DIR/config/$DB_ENV.conf" ] && [ -d "$DB_DIR/config" ]; then
  echo "WARNING: config/$DB_ENV.conf not found - using defaults for environment '$DB_ENV'" >&2
fi
__cfg_load "$DB_DIR/config/$DB_ENV.conf"
__cfg_load "$DB_DIR/config/$DB_ENV.secret.conf"
__cfg_reapply

# ---- built-in defaults for anything still unset ----
PROJECT_NAME=${PROJECT_NAME:-dbproject}
RUNNER=${RUNNER:-docker}                    # docker | docker-client | local
ORACLE_IMAGE=${ORACLE_IMAGE:-gvenzl/oracle-free:slim}
CONTAINER_NAME=${CONTAINER_NAME:-${PROJECT_NAME}-oracle}
HOST_PORT=${HOST_PORT:-1521}
ORACLE_PASSWORD=${ORACLE_PASSWORD:-Oracle123}
APP_USER=${APP_USER:-app}
APP_USER_PASSWORD=${APP_USER_PASSWORD:-App12345}
if [ "$RUNNER" = "docker" ]; then
  # the runner executes inside the bundled DB container, so it reaches the DB on the container's own port
  DB_HOST=${DB_HOST:-localhost}; DB_PORT=${DB_PORT:-1521}; DB_SERVICE=${DB_SERVICE:-FREEPDB1}
  DB_USER=${DB_USER:-$APP_USER}; DB_PASSWORD=${DB_PASSWORD:-$APP_USER_PASSWORD}
fi
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-1521}
DB_SERVICE=${DB_SERVICE:-FREEPDB1}
DB_USER=${DB_USER:-$APP_USER}
DB_PASSWORD=${DB_PASSWORD:-}
HISTORY_TABLE=${HISTORY_TABLE:-schema_version}
MIGRATIONS_DIR=${MIGRATIONS_DIR:-migrations}
UNDO_DIR=${UNDO_DIR:-$MIGRATIONS_DIR/undo}
REPEATABLE_DIR=${REPEATABLE_DIR:-repeatable}
SMOKE_SQL=${SMOKE_SQL:-}
LOG=${LOG:-${TMPDIR:-/tmp}/${PROJECT_NAME}-migrate.log}
PROTECTED_ENVS=${PROTECTED_ENVS:-prod}
OUT_OF_ORDER=${OUT_OF_ORDER:-0}
CONFIRM=${CONFIRM:-}
# Password is quoted so characters like @ / # work.
CONN=${CONN:-${DB_USER}/\"${DB_PASSWORD}\"@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}}
COMPOSE_PROJECT=${COMPOSE_PROJECT:-$PROJECT_NAME}
export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT" ORACLE_IMAGE CONTAINER_NAME HOST_PORT ORACLE_PASSWORD APP_USER APP_USER_PASSWORD

# env vars to forward when the script re-runs itself inside a container (only real overrides)
CONFIG_FORWARD="$__cfg_env_overrides"
