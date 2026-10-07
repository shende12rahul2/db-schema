# Configuration loader, sourced by the db scripts (needs DB_DIR set).
#
# Precedence (later wins):
#   built-in defaults < config/default.conf (project layout, committed) < .env (target database, NOT committed)
#   < real environment variables
#
# .env is read as data, never executed: plain KEY=VALUE lines, optional single/double quotes, '#' comment lines.
# Select another target file with  --env-file <path>  or  ENV_FILE=<path>  or  --env <name>  (= .env.<name>).

CONFIG_KEYS="PROJECT_NAME APP_ENV RUNNER DB_HOST DB_PORT DB_SERVICE DB_USER DB_PASSWORD CONN EXPECTED_DB
PROTECTED_ENVS HISTORY_TABLE MIGRATIONS_DIR UNDO_DIR REPEATABLE_DIR BASELINE_DIR SMOKE_SQL LOG
ORACLE_IMAGE CONTAINER_NAME HOST_PORT ORACLE_PASSWORD APP_USER APP_USER_PASSWORD COMPOSE_PROJECT
OUT_OF_ORDER CONFIRM"
CONFIG_KEYS=$(printf '%s ' $CONFIG_KEYS)      # one space between keys (the membership test below needs it)

# Remember values that came from the real environment; they override every file.
__cfg_env_overrides=""
for __k in $CONFIG_KEYS; do
  if [ -n "${!__k+x}" ] && [ -n "${!__k}" ]; then __cfg_env_overrides="$__cfg_env_overrides $__k"; eval "__cfg_ovr_$__k=\${$__k}"; fi
done
__cfg_reapply() { local k; for k in $__cfg_env_overrides; do eval "$k=\${__cfg_ovr_$k}"; done; }

# __cfg_load <file>: read KEY=VALUE lines without executing anything
__cfg_load() {
  [ -f "$1" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}                                   # tolerate Windows line endings
    case "$line" in ''|'#'*|[[:space:]]'#'*) continue;; esac
    line=${line#"${line%%[![:space:]]*}"}                # trim leading blanks
    case "$line" in export\ *) line=${line#export };; esac
    key=${line%%=*}; val=${line#*=}
    [ "$key" = "$line" ] && continue                     # no '='
    key=${key%"${key##*[![:space:]]}"}
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    case " $CONFIG_KEYS " in *" $key "*) ;; *) continue;; esac
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
      *) val=${val%%[[:space:]]#*}; val=${val%"${val##*[![:space:]]}"} ;;   # strip trailing " # comment"
    esac
    printf -v "$key" '%s' "$val"
  done < "$1"
}

__cfg_load "$DB_DIR/config/default.conf"
__cfg_reapply

# ---- which .env file ----
if [ -z "${ENV_FILE:-}" ]; then
  if [ -n "${ENV_NAME:-}" ]; then ENV_FILE="$DB_DIR/.env.$ENV_NAME"; else ENV_FILE="$DB_DIR/.env"; fi
fi
case "$ENV_FILE" in /*|[A-Za-z]:*) ;; *) ENV_FILE="$DB_DIR/$ENV_FILE";; esac
ENV_FILE_FOUND=0
if [ -f "$ENV_FILE" ]; then ENV_FILE_FOUND=1; __cfg_load "$ENV_FILE"; fi
__cfg_reapply

# ---- built-in defaults for anything still unset ----
PROJECT_NAME=${PROJECT_NAME:-dbproject}
APP_ENV=${APP_ENV:-dev}
RUNNER=${RUNNER:-local}                     # local | docker-client | docker
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
DB_SERVICE=${DB_SERVICE:-}
DB_USER=${DB_USER:-}
DB_PASSWORD=${DB_PASSWORD:-}
EXPECTED_DB=${EXPECTED_DB:-}
HISTORY_TABLE=${HISTORY_TABLE:-schema_version}
MIGRATIONS_DIR=${MIGRATIONS_DIR:-migrations}
UNDO_DIR=${UNDO_DIR:-$MIGRATIONS_DIR/undo}
REPEATABLE_DIR=${REPEATABLE_DIR:-repeatable}
BASELINE_DIR=${BASELINE_DIR:-baseline}
SMOKE_SQL=${SMOKE_SQL:-}
LOG=${LOG:-${TMPDIR:-/tmp}/${PROJECT_NAME}-migrate.log}
PROTECTED_ENVS=${PROTECTED_ENVS:-prod}
OUT_OF_ORDER=${OUT_OF_ORDER:-0}
CONFIRM=${CONFIRM:-}
# Password is quoted so characters like @ / # work.
CONN=${CONN:-${DB_USER}/\"${DB_PASSWORD}\"@//${DB_HOST}:${DB_PORT}/${DB_SERVICE}}
COMPOSE_PROJECT=${COMPOSE_PROJECT:-$PROJECT_NAME}
export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT" ORACLE_IMAGE CONTAINER_NAME HOST_PORT ORACLE_PASSWORD APP_USER APP_USER_PASSWORD

# values to forward when the script re-runs itself inside a container (real overrides only; the container reads .env itself)
CONFIG_FORWARD="$__cfg_env_overrides"
