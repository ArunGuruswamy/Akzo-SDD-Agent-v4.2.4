@echo off
rem Akzo Master SDD Agent - choose the refined PBI file and queue it for the agent.
dir /r "%~dp0scripts\Start-Development.ps1" 2>nul | find ":Zone.Identifier" >nul && echo NOTE: Windows marks these files as downloaded. If PowerShell refuses to run them, follow "Blocked or unsigned scripts" in installation-guide.html. Policy is never bypassed.
powershell.exe -NoProfile -STA -File "%~dp0scripts\Start-Development.ps1" %*
