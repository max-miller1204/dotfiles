#!/usr/bin/env bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

MINS=$((DURATION_MS / 60000))
SECS=$(((DURATION_MS % 60000) / 1000))

BRANCH=""
git rev-parse --git-dir >/dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

COST_FMT=$(printf '$%.2f' "$COST")
echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}$BRANCH | ${PCT}% context | ${YELLOW}${COST_FMT}${RESET} | ⌛ ${MINS}m ${SECS}s"
