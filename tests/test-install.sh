#!/usr/bin/env bash
# Tests for install.sh — runs the real installer against a temp HOME.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
# Hermetic: force the prompts fallback so tests never invoke the real codex CLI.
export SUPERSKILLS_CODEX_MODE=prompts
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.aone_copilot"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }
assert_file()    { if [[ -f "$2" ]]; then ok "$1"; else fail "$1 (missing $2)"; fi }
assert_no_file()  { if [[ ! -e "$2" ]]; then ok "$1"; else fail "$1 (still exists: $2)"; fi }
assert_contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3)"; fi }

# Pre-existing user settings with an unrelated hook must survive everything.
cat > "$HOME/.aone_copilot/settings.json" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "echo user-hook" }] }
    ]
  }
}
EOF

echo "== install (autodetect: codex + aone, never claude) =="
bash "$REPO_DIR/install.sh" >/dev/null

assert_no_file "claude untouched by autodetect" "$HOME/.claude/skills/ss-learn"

for s in ss-learn ss-discover ss-clarify ss-test; do
  assert_file "aone skill $s" "$HOME/.aone_copilot/skills/$s/SKILL.md"
done
assert_contains "aone skill renamed in frontmatter" \
  "$(head -2 "$HOME/.aone_copilot/skills/ss-learn/SKILL.md")" "name: ss-learn"
assert_file "aone session-start hook" "$HOME/.aone_copilot/superskills/hooks/session-start.js"
assert_file "aone stop hook" "$HOME/.aone_copilot/superskills/hooks/stop-learn.js"
settings="$(cat "$HOME/.aone_copilot/settings.json")"
assert_contains "aone SessionStart registered" "$settings" "session-start.js"
assert_contains "aone Stop registered" "$settings" "stop-learn.js"
assert_contains "user model setting preserved" "$settings" '"model": "opus"'
assert_contains "user hook preserved" "$settings" "echo user-hook"

for s in ss-learn ss-discover ss-clarify ss-test; do
  assert_file "codex prompt $s" "$HOME/.codex/prompts/$s.md"
done
first_line="$(head -1 "$HOME/.codex/prompts/ss-learn.md")"
if [[ "$first_line" != "---" ]]; then ok "codex prompt frontmatter stripped"; else fail "codex frontmatter not stripped"; fi
assert_contains "codex prompt keeps body" "$(cat "$HOME/.codex/prompts/ss-learn.md")" "# Learn"

echo "== legacy claude install (explicit --tools claude) =="
bash "$REPO_DIR/install.sh" --tools claude >/dev/null 2>&1
assert_file "claude legacy skill" "$HOME/.claude/skills/ss-learn/SKILL.md"
assert_contains "claude legacy hooks registered" \
  "$(cat "$HOME/.claude/settings.json")" "stop-learn.js"

echo "== idempotency =="
bash "$REPO_DIR/install.sh" >/dev/null
count="$(grep -o "stop-learn.js" "$HOME/.aone_copilot/settings.json" | wc -l | tr -d ' ')"
if [[ "$count" == 1 ]]; then ok "reinstall does not duplicate hooks"; else fail "duplicated hooks ($count entries)"; fi
if node -e "JSON.parse(require('fs').readFileSync('$HOME/.aone_copilot/settings.json','utf8'))"; then
  ok "settings.json stays valid JSON"
else
  fail "settings.json corrupted"
fi

echo "== uninstall =="
bash "$REPO_DIR/install.sh" --uninstall --tools codex,aone,claude >/dev/null
assert_no_file "aone skills removed" "$HOME/.aone_copilot/skills/ss-learn"
assert_no_file "aone hooks removed" "$HOME/.aone_copilot/superskills"
assert_no_file "claude legacy removed" "$HOME/.claude/skills/ss-learn"
assert_no_file "codex prompts removed" "$HOME/.codex/prompts/ss-learn.md"
settings="$(cat "$HOME/.aone_copilot/settings.json")"
assert_contains "user hook survives uninstall" "$settings" "echo user-hook"
if [[ "$settings" != *"superskills"* ]]; then ok "our hooks removed from settings"; else fail "superskills entries remain"; fi

echo "== project-level install =="
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude"
echo '{"model": "sonnet"}' > "$PROJ/.claude/settings.json"   # pre-existing project settings
bash "$REPO_DIR/install.sh" --project "$PROJ" >/dev/null

psettings="$(cat "$PROJ/.claude/settings.json")"
assert_contains "project marketplace declared (github source)" "$psettings" '"repo": "Mrlyk/superskills"'
assert_contains "project plugin enabled" "$psettings" '"superskills@superskills": true'
assert_contains "pre-existing project settings preserved" "$psettings" '"model": "sonnet"'
for s in ss-learn ss-discover ss-clarify ss-test; do
  assert_file "project aone skill $s" "$PROJ/.aone_copilot/skills/$s/SKILL.md"
done
assert_file "project aone hooks" "$PROJ/.aone_copilot/superskills/hooks/session-start.js"
assert_contains "project aone hooks resolve via CLAUDE_PROJECT_DIR" \
  "$(cat "$PROJ/.aone_copilot/settings.json")" '$CLAUDE_PROJECT_DIR/.aone_copilot/superskills/hooks'
assert_no_file "project install leaves user claude untouched" "$HOME/.claude/skills/ss-learn"

bash "$REPO_DIR/install.sh" --project "$PROJ" >/dev/null
count="$(grep -o '"superskills@superskills"' "$PROJ/.claude/settings.json" | wc -l | tr -d ' ')"
if [[ "$count" == 1 ]]; then ok "project reinstall is idempotent"; else fail "duplicated project entries ($count)"; fi

bash "$REPO_DIR/install.sh" --project "$PROJ" --uninstall >/dev/null
psettings="$(cat "$PROJ/.claude/settings.json")"
if [[ "$psettings" != *"superskills"* ]]; then ok "project claude entries removed"; else fail "project claude entries remain"; fi
assert_contains "project settings survive uninstall" "$psettings" '"model": "sonnet"'
assert_no_file "project aone skills removed" "$PROJ/.aone_copilot/skills/ss-learn"

echo
echo "install: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
