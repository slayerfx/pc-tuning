@echo off
title pc-tuning - Apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-tuning.ps1" -Mode Apply %*
