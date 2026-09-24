@echo off
title pc-tuning - Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-tuning.ps1" -Mode Check %*
