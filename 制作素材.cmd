@echo off
cd /d "%~dp0"
python tools\convert_gui.pyw
if errorlevel 1 pause
