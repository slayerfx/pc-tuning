@echo off
title pc-tuning - SecureBoot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-tuning.ps1" -Mode SecureBoot %*
