@echo off
rem Akzo Master SDD Agent - install, upgrade, repair, verify, or uninstall (window).
rem Files extracted from a downloaded zip carry the "downloaded from the internet" mark; policy may refuse them. Inform only.
dir /r "%~dp0scripts\Install-MasterAgent.ps1" 2>nul | find ":Zone.Identifier" >nul && echo NOTE: Windows marks these files as downloaded. If PowerShell refuses to run them, verify the package SHA-256, then follow "Blocked or unsigned scripts" in installation-guide.html. Policy is never bypassed.
powershell.exe -NoProfile -STA -File "%~dp0scripts\Install-MasterAgent.ps1" %*
