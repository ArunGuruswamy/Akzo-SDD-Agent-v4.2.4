@echo off
rem Akzo Master SDD Agent - uninstall (asks first; keeps repos.json, tasks, inbox, specs, backups).
dir /r "%~dp0scripts\Install-MasterAgent.ps1" 2>nul | find ":Zone.Identifier" >nul && echo NOTE: Windows marks these files as downloaded. If PowerShell refuses to run them, follow "Blocked or unsigned scripts" in installation-guide.html. Policy is never bypassed.
powershell.exe -NoProfile -STA -File "%~dp0scripts\Install-MasterAgent.ps1" -Action Uninstall %*
