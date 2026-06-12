#!/usr/bin/env bash
# Tests for install.sh — runs the real installer against a temp HOME.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.aone_copilot"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }
assert_file()    { if [[ -f "$2" ]]; then ok "$1"; else fail "$1 (missing $2)"; fi }
assert_no_file()  { if [[ ! -e "$2" ]]; then ok "$1"; else fail "$1 (still exists: $2)"; fi }
assert_contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3)"; fi }

# Pre-existing user settings with an unrelated hook must survive everything.
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "echo user-hook" }] }
    ]
  }
}
EOF

echo "== install (autodetect) =="
bash "$REPO_DIR/install.sh" >/dev/null

for base in "$HOME/.claude" "$HOME/.aone_copilot"; do
  name="$(basename "$base")"
  for s in ss-learn ss-discover ss-clarify ss-test; do
    assert_file "$name skill $s" "$base/skills/$s/SKILL.md"
  done
  assert_file "$name session-start hook" "$base/superskills/hooks/session-start.js"
  assert_file "$name stop hook" "$base/superskills/hooks/stop-learn.js"
  settings="$(cat "$base/settings.json")"
  assert_contains "$name SessionStart registered" "$settings" "session-start.js"
  assert_contains "$name Stop registered" "$settings" "stop-learn.js"
done

settings="$(cat "$HOME/.claude/settings.json")"
assert_contains "user model setting preserved" "$settings" '"model": "opus"'
assert_contains "user hook preserved" "$settings" "echo user-hook"

for s in ss-learn ss-discover ss-clarify ss-test; do
  assert_file "codex prompt $s" "$HOME/.codex/prompts/$s.md"
done
first_line="$(head -1 "$HOME/.codex/prompts/ss-learn.md")"
if [[ "$first_line" != "---" ]]; then ok "codex prompt frontmatter stripped"; else fail "codex frontmatter not stripped"; fi
assert_contains "codex prompt keeps body" "$(cat "$HOME/.codex/prompts/ss-learn.md")" "# Learn"

echo "== idempotency =="
bash "$REPO_DIR/install.sh" >/dev/null
count="$(grep -o "stop-learn.js" "$HOME/.claude/settings.json" | wc -l | tr -d ' ')"
if [[ "$count" == 1 ]]; then ok "reinstall does not duplicate hooks"; else fail "duplicated hooks ($count entries)"; fi
if node -e "JSON.parse(require('fs').readFileSync('$HOME/.claude/settings.json','utf8'))"; then
  ok "settings.json stays valid JSON"
else
  fail "settings.json corrupted"
fi

echo "== uninstall =="
bash "$REPO_DIR/install.sh" --uninstall >/dev/null
assert_no_file "claude skills removed" "$HOME/.claude/skills/ss-learn"
assert_no_file "claude hooks removed" "$HOME/.claude/superskills"
assert_no_file "aone skills removed" "$HOME/.aone_copilot/skills/ss-learn"
assert_no_file "codex prompts removed" "$HOME/.codex/prompts/ss-learn.md"
settings="$(cat "$HOME/.claude/settings.json")"
assert_contains "user hook survives uninstall" "$settings" "echo user-hook"
if [[ "$settings" != *"superskills"* ]]; then ok "our hooks removed from settings"; else fail "superskills entries remain"; fi

echo
echo "install: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
