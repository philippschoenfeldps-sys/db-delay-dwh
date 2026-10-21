@echo off
REM write the log file as UTF-8 so umlauts are stored correctly
set PYTHONIOENCODING=utf-8

REM Runs the collector once; started hourly by Windows Task Scheduler.

REM go to the folder the folder this .bat file lives in (= repo root).
cd /d "%~dp0"

if not exist logs mkdir logs

REM header line per run: when did it start, in which folder?
echo. >> logs\collector.log
echo ===== %date% %time%  folder: %cd% ===== >> logs\collector.log

REM fail with a clear message instead of a generic Windows error
if not exist ".venv\Scripts\python.exe" (
    echo ERROR: .venv\Scripts\python.exe not found in this folder >> logs\collector.log
    exit /b 1
)
.venv\Scripts\python.exe ingestion\collector.py >> logs\collector.log 2>&1