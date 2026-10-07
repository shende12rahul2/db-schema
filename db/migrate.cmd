@echo off
rem Windows launcher (cmd.exe and PowerShell). Requires Docker Desktop (the runner and sqlplus run inside a container).
rem Usage: migrate.cmd [--env NAME ^| --env-file FILE] COMMAND ...      (same commands as migrate.sh; try: migrate.cmd help)
rem Target database: .env in this folder (copy .env.example), or .env.NAME for --env NAME. See docs\ONBOARDING.md
setlocal EnableExtensions
set "F=%~dp0docker-compose.yml"
for %%I in ("%~dp0.") do set "DBNAME=%%~nxI"
set "ENVARG="

:args
if /I "%~1"=="--env"      ( set "ENV_NAME=%~2" & set "ENVARG=-e ENV_NAME=%~2" & shift & shift & goto args )
if /I "%~1"=="--env-file" ( set "ENV_FILE=%~2" & set "ENVARG=-e ENV_FILE=%~2" & shift & shift & goto args )
if "%~1"=="" goto usage
set "CMD=%~1"

rem ---- read RUNNER and container names (default.conf, then the .env file) ----
call :load "%~dp0config\default.conf"
if defined ENV_FILE (set "EF=%~dp0%ENV_FILE%") else if defined ENV_NAME (set "EF=%~dp0.env.%ENV_NAME%") else (set "EF=%~dp0.env")
if exist "%EF%" (call :load "%EF%") else (echo NOTE: %EF% not found - copy .env.example to .env and fill it in.)
if not defined RUNNER set "RUNNER=local"
if not defined PROJECT_NAME set "PROJECT_NAME=dbproject"
if not defined CONTAINER_NAME set "CONTAINER_NAME=%PROJECT_NAME%-oracle"
if defined COMPOSE_PROJECT (set "COMPOSE_PROJECT_NAME=%COMPOSE_PROJECT%") else (set "COMPOSE_PROJECT_NAME=%PROJECT_NAME%")

if /I "%RUNNER%"=="local" (
  echo RUNNER=local needs bash and sqlplus: run db/scripts/migrate.sh from Git Bash or WSL, or set RUNNER=docker-client in .env.
  exit /b 1
)
set "SERVICE=oracle"
if /I "%RUNNER%"=="docker-client" set "SERVICE=client"

if /I "%CMD%"=="up" goto up
if /I "%CMD%"=="down" goto down

rem CONFIRM / OUT_OF_ORDER / DB_PASSWORD / CONN given in this window are forwarded; everything else is read from .env inside the container
docker compose -f "%F%" exec -T -w /workspace/%DBNAME% -e MIGRATE_IN_CONTAINER=1 %ENVARG% -e "CONFIRM=%CONFIRM%" -e "OUT_OF_ORDER=%OUT_OF_ORDER%" -e "DB_PASSWORD=%DB_PASSWORD%" -e "CONN=%CONN%" %SERVICE% bash scripts/migrate.sh %*
set "RC=%errorlevel%"
if not "%RC%"=="0" docker compose -f "%F%" ps --status running -q %SERVICE% | findstr . >nul || echo The %SERVICE% container is not running. Start it with: migrate.cmd up
exit /b %RC%

:up
if /I "%SERVICE%"=="client" (
  docker compose -f "%F%" up -d client
) else (
  echo Starting Oracle %CONTAINER_NAME% - the first run takes a few minutes...
  docker compose -f "%F%" up -d --wait oracle
)
exit /b %errorlevel%

:down
if defined APP_ENV (
  echo ,%PROTECTED_ENVS%, | findstr /I /C:",%APP_ENV%," >nul && (
    echo Refusing down for protected environment %APP_ENV%.
    exit /b 1
  )
)
docker compose -f "%F%" rm -s -f -v %SERVICE%
exit /b %errorlevel%

:load
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~1") do set "%%a=%%b"
exit /b 0

:usage
echo Usage: migrate.cmd [--env NAME ^| --env-file FILE] up ^| down ^| config ^| plan ^| status ^| validate ^| verify-baseline V ^| baseline V ^| migrate ^| step ^| undo ^| repair ^| unlock ^| manifest V ^| sql "SELECT ..." ^| smoke ^| deploy ^| log
exit /b 1
