@echo off
rem Windows launcher (cmd.exe and PowerShell). Only Docker Desktop is required.
rem Usage: migrate.cmd up ^| down ^| migrate ^| status ^| validate ^| undo ^| repair ^| baseline ^| smoke ^| deploy
setlocal
set "F=%~dp0docker-compose.yml"
if "%~1"=="" goto usage
if /I "%~1"=="up" goto up
if /I "%~1"=="down" goto down
if "%ENVIRONMENT%"=="" set "ENVIRONMENT=local"
if "%OUT_OF_ORDER%"=="" set "OUT_OF_ORDER=0"
docker compose -f "%F%" exec -T -w /workspace/db -e ENVIRONMENT=%ENVIRONMENT% -e CONFIRM=%CONFIRM% -e OUT_OF_ORDER=%OUT_OF_ORDER% oracle bash scripts/migrate.sh %*
goto :eof
:up
docker compose -f "%F%" up -d --wait
goto :eof
:down
docker compose -f "%F%" down -v
goto :eof
:usage
echo Usage: migrate.cmd up ^| down ^| migrate ^| status ^| validate ^| undo ^| repair ^| baseline ^| smoke ^| deploy
