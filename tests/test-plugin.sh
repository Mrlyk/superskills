#!/usr/bin/env bash
# Validates the Claude Code plugin structure (manifest, marketplace, hooks).
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

echo "== plugin structure =="

node - "$REPO_DIR" <<'EOF' && ok "plugin.json valid" || fail "plugin.json invalid"
const fs = require('fs'), path = require('path');
const p = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.claude-plugin/plugin.json'), 'utf8'));
if (p.name !== 'superskills') throw new Error('bad name');
if (!/^\d+\.\d+\.\d+$/.test(p.version)) throw new Error('bad version');
if (!p.description) throw new Error('missing description');
EOF

node - "$REPO_DIR" <<'EOF' && ok "marketplace.json valid and points at repo root" || fail "marketplace.json invalid"
const fs = require('fs'), path = require('path');
const m = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.claude-plugin/marketplace.json'), 'utf8'));
if (m.name !== 'superskills') throw new Error('bad marketplace name');
const entry = m.plugins.find((p) => p.name === 'superskills');
if (!entry || entry.source !== './') throw new Error('bad plugin entry');
EOF

node - "$REPO_DIR" <<'EOF' && ok "hooks.json wires both hooks via CLAUDE_PLUGIN_ROOT" || fail "hooks.json invalid"
const fs = require('fs'), path = require('path');
const root = process.argv[2];
const h = JSON.parse(fs.readFileSync(path.join(root, 'hooks/hooks.json'), 'utf8')).hooks;
for (const event of ['SessionStart', 'Stop']) {
  const cmds = (h[event] || []).flatMap((e) => e.hooks.map((x) => x.command));
  if (cmds.length === 0) throw new Error(`missing ${event}`);
  for (const c of cmds) {
    if (!c.includes('${CLAUDE_PLUGIN_ROOT}')) throw new Error(`no plugin root in: ${c}`);
    const script = c.match(/hooks\/([a-z-]+\.js)/)[1];
    if (!fs.existsSync(path.join(root, 'hooks', script))) throw new Error(`missing script ${script}`);
  }
}
EOF

for s in learn discover clarify test; do
  if head -2 "$REPO_DIR/skills/$s/SKILL.md" | grep -q "^name: $s$"; then
    ok "skill '$s' frontmatter matches directory"
  else
    fail "skill '$s' frontmatter name mismatch"
  fi
done

if command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate "$REPO_DIR" 2>&1)"; then
    ok "claude plugin validate passes"
  else
    fail "claude plugin validate: ${out:0:300}"
  fi
else
  echo "  skip: claude CLI not available for official validation"
fi

echo
echo "plugin: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
