@echo off
chcp 65001 >nul
title Claude Code
set CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
claude --dangerously-skip-permissions
