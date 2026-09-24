@echo off
title pc-tuning - Undo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-tuning.ps1" -Mode Undo %*
