#!/usr/bin/env bash
# Every check, in one command. Run before claiming anything works.
cd "$(dirname "$0")/.." || exit 1

pass=0; fail=0
run() {
  local label="$1"; shift
  printf '\n\033[1m== %s ==\033[0m\n' "$label"
  if "$@"; then
    pass=$((pass+1))
  else
    printf '\033[31mFAILED\033[0m (%s, exit %d)\n' "$label" "$?"
    fail=$((fail+1))
  fi
}

run "syntax"     python3 tools/check_syntax.py
run "server boot" python3 tools/check_boot.py
run "baked map"  python3 tools/check_bake.py
run "map build"  python3 tools/check_map.py
run "data safety" python3 tools/check_data.py
run "trading"    python3 tools/check_trade.py
run "pets"       python3 tools/check_pets.py
run "pet models" python3 tools/check_petmodels.py
run "eggs"       python3 tools/check_eggs.py
run "onboarding" python3 tools/check_onboarding.py
run "motion"     python3 tools/check_motion.py
run "hatch"      python3 tools/check_hatch.py
run "pet view"   python3 tools/check_petview.py
run "pet follow" python3 tools/check_follow.py
run "panels"     python3 tools/check_panels.py
run "buttons"    python3 tools/check_buttons.py
run "first play" python3 tools/check_firstplay.py
run "installer"  python3 tools/check_install.py
run "remotes"    python3 tools/check_remotes.py
run "client boot" python3 tools/check_client.py
run "game loop"  python3 tools/check_loop.py
run "ui panels"  python3 tools/check_ui.py
run "sound"      python3 tools/check_sound.py
run "session"    python3 tools/check_session.py
run "economy"    python3 tools/check_economy.py
run "exploits"   python3 tools/check_exploit.py
run "quests"     python3 tools/check_quests.py
run "sync bridge" python3 tools/check_bridge.py
run "studio panel" python3 tools/check_ai.py

printf '\n\033[1m---------------------------------------\033[0m\n'
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
