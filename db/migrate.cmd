@echo off
rem Windows launcher (cmd.exe and PowerShell). Requires Docker Desktop.
rem Usage: migrate.cmd [--env NAME] up ^| down ^| config ^| plan ^| step ^| migrate ^| sql "SELECT ..." ^| status ^| validate ^| undo ^| repair ^| baseline [ver] ^| smoke ^| deploy
rem Environment: --env NAME or "set DB_ENV=NAME". Settings: config\*.conf (see docs\CONFIGURATION.md)
setlocal EnableExtensions
set "F=%~dp0docker-compose.yml"
for %%I in ("%~dp0.") do set "DBNAME=%%~nxI"

set "CMD=%~1"
if /I "%~1"=="--env" (
  set "DB_ENV=%~2"
  set "CMD=%~3"
)
if "%CMD%"=="" goto usage

rem ---- load config: default.conf, then <env>.conf; DB_ENV / RUNNER from the environment win ----
set "OVR_DB_ENV=%DB_ENV%"
set "OVR_RUNNER=%RUNNER%"
call :load "%~dp0config\default.conf"
if defined OVR_DB_ENV set "DB_ENV=%OVR_DB_ENV%"
if not defined DB_ENV set "DB_ENV=local"
call :load "%~dp0config\%DB_ENV%.conf"
if defined OVR_RUNNER set "RUNNER=%OVR_RUNNER%"
if not defined RUNNER set "RUNNER=docker"
if not defined PROJECT_NAME set "PROJECT_NAME=dbproject"
if not defined CONTAINER_NAME set "CONTAINER_NAME=%PROJECT_NAME%-oracle"
if defined COMPOSE_PROJECT (set "COMPOSE_PROJECT_NAME=%COMPOSE_PROJECT%") else (set "COMPOSE_PROJECT_NAME=%PROJECT_NAME%")

if /I "%RUNNER%"=="local" (
  echo RUNNER=local needs bash and sqlplus: run db/scripts/migrate.sh from Git Bash or WSL instead.
  exit /b 1
)
set "SERVICE=oracle"
if /I "%RUNNER%"=="docker-client" set "SERVICE=client"

if /I "%CMD%"=="up" goto up
if /I "%CMD%"=="down" goto down

docker compose -f "%F%" exec -T -w /workspace/%DBNAME% -e MIGRATE_IN_CONTAINER=1 -e "DB_ENV=%DB_ENV%" -e "CONFIRM=%CONFIRM%" -e "OUT_OF_ORDER=%OUT_OF_ORDER%" -e "DB_PASSWORD=%DB_PASSWORD%" -e "CONN=%CONN%" %SERVICE% bash scripts/migrate.sh %*
if errorlevel 1 (
  docker compose -f "%F%" ps --status running -q %SERVICE% | findstr . >nul || echo The %SERVICE% container is not running. Start it with: migrate.cmd --env %DB_ENV% up
)
exit /b %errorlevel%

:up
if /I "%SERVICE%"=="client" (
  docker compose -f "%F%" up -d client
) else (
  echo Starting Oracle %CONTAINER_NAME% - the first run takes a few minutes...
  docker compose -f "%F%" up -d --wait oracle
)
exit /b %errorlevel%

:down
docker compose -f "%F%" rm -s -f -v %SERVICE%
exit /b %errorlevel%

:load
if not exist "%~1" exit /b 0
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~1") do set "%%a=%%b"
exit /b 0

:usage
echo Usage: migrate.cmd [--env NAME] up ^| down ^| config ^| plan ^| step ^| migrate ^| sql "SELECT ..." ^| status ^| validate ^| undo ^| repair ^| baseline [ver] ^| smoke ^| deploy
exit /b 1
