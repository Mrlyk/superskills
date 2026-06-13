#!/usr/bin/env bash
# Validates the plugin structure for both ecosystems (Claude Code + Codex).
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/superskills"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

echo "== claude plugin structure =="

node - "$PLUGIN_DIR" <<'EOF' && ok "claude plugin.json valid" || fail "claude plugin.json invalid"
const fs = require('fs'), path = require('path');
const p = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.claude-plugin/plugin.json'), 'utf8'));
if (p.name !== 'superskills') throw new Error('bad name');
if (!/^\d+\.\d+\.\d+$/.test(p.version)) throw new Error('bad version');
if (!p.description) throw new Error('missing description');
EOF

node - "$REPO_DIR" <<'EOF' && ok "claude marketplace points at plugins/superskills" || fail "claude marketplace.json invalid"
const fs = require('fs'), path = require('path');
const m = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.claude-plugin/marketplace.json'), 'utf8'));
if (m.name !== 'superskills') throw new Error('bad marketplace name');
const entry = m.plugins.find((p) => p.name === 'superskills');
if (!entry || entry.source !== './plugins/superskills') throw new Error('bad plugin entry');
EOF

node - "$PLUGIN_DIR" <<'EOF' && ok "hooks.json wires both hooks via CLAUDE_PLUGIN_ROOT" || fail "hooks.json invalid"
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
  if head -2 "$PLUGIN_DIR/skills/$s/SKILL.md" | grep -q "^name: $s$"; then
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

echo "== codex plugin structure =="

node - "$PLUGIN_DIR" <<'EOF' && ok "codex plugin.json valid (manifest + interface, no hooks field)" || fail "codex plugin.json invalid"
const fs = require('fs'), path = require('path');
const p = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.codex-plugin/plugin.json'), 'utf8'));
if (p.name !== 'superskills') throw new Error('bad name');
if (!/^\d+\.\d+\.\d+$/.test(p.version)) throw new Error('bad semver');
if (!p.description || !p.author || !p.author.name) throw new Error('missing required fields');
if (p.hooks) throw new Error('codex manifest must not declare hooks');
const i = p.interface || {};
for (const k of ['displayName', 'shortDescription', 'longDescription', 'developerName', 'category']) {
  if (!i[k]) throw new Error(`missing interface.${k}`);
}
if ((i.defaultPrompt || []).some((s) => s.length > 128)) throw new Error('defaultPrompt too long');
EOF

node - "$REPO_DIR" <<'EOF' && ok "codex marketplace entry follows the spec" || fail "codex marketplace.json invalid"
const fs = require('fs'), path = require('path');
const m = JSON.parse(fs.readFileSync(path.join(process.argv[2], '.agents/plugins/marketplace.json'), 'utf8'));
if (m.name !== 'superskills') throw new Error('bad marketplace name');
const e = m.plugins.find((p) => p.name === 'superskills');
if (!e) throw new Error('missing entry');
if (e.source.source !== 'local' || e.source.path !== './plugins/superskills') throw new Error('bad source');
if (!['NOT_AVAILABLE', 'AVAILABLE', 'INSTALLED_BY_DEFAULT'].includes(e.policy.installation)) throw new Error('bad installation policy');
if (!['ON_INSTALL', 'ON_USE'].includes(e.policy.authentication)) throw new Error('bad auth policy');
if (!e.category) throw new Error('missing category');
EOF

CODEX_VALIDATOR="$HOME/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py"
if [[ -f "$CODEX_VALIDATOR" ]] && python3 -c 'import yaml' 2>/dev/null; then
  if python3 "$CODEX_VALIDATOR" "$PLUGIN_DIR" >/dev/null 2>&1; then
    ok "official codex validator passes"
  else
    fail "official codex validator rejected the plugin"
  fi
elif [[ -f "$CODEX_VALIDATOR" ]] && [[ -x /tmp/ssv/bin/python ]]; then
  if /tmp/ssv/bin/python "$CODEX_VALIDATOR" "$PLUGIN_DIR" >/dev/null 2>&1; then
    ok "official codex validator passes"
  else
    fail "official codex validator rejected the plugin"
  fi
else
  echo "  skip: codex official validator unavailable (needs PyYAML)"
fi

echo
echo "plugin: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
