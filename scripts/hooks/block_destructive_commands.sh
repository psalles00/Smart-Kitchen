#!/bin/zsh

set -eu

payload="$(cat)"

if print -r -- "$payload" | grep -Eiq 'git reset --hard|git checkout --|git restore([[:space:]]|$)|git clean([[:space:]]|$)|git revert([[:space:]]|$)|rm -rf|xcrun simctl uninstall'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Dangerous command detected. Explicit user confirmation is required before discarding work or app data."},"systemMessage":"Comando potencialmente destrutivo detectado. Não execute reset, restore, clean, uninstall ou remoção recursiva sem confirmação explícita do usuário no mesmo turno."}
EOF
else
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF
fi