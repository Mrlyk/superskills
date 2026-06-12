#!/usr/bin/env bash
# superskills installer for tools without Claude Code plugin support.
#
#   ./install.sh                       # autodetect: Codex (~/.codex), Aone Copilot (~/.aone_copilot)
#   ./install.sh --tools codex,aone
#   ./install.sh --tools claude        # legacy settings-based install (prefer the plugin:
#                                      #   /plugin marketplace add Mrlyk/superskills)
#   ./install.sh --all                 # codex + aone + claude(legacy)
#   ./install.sh --uninstall [--tools ...]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(learn discover clarify test)   # installed as ss-<name> to avoid collisions
HOOK_FILES=(session-start.js stop-learn.js)

TOOLS=""
UNINSTALL=0
ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools) TOOLS="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)
      sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

tool_base() {
  case "$1" in
    claude) echo "$HOME/.claude" ;;
    codex)  echo "$HOME/.codex" ;;
    aone)   echo "$HOME/.aone_copilot" ;;
    *) return 1 ;;
  esac
}

detect_tools() {
  local found=""
  for t in codex aone; do
    [[ -d "$(tool_base "$t")" ]] && found="${found:+$found,}$t"
  done
  echo "$found"
}

if [[ -z "$TOOLS" ]]; then
  if [[ "$ALL" == 1 ]]; then
    TOOLS="codex,aone,claude"
  else
    TOOLS="$(detect_tools)"
    if [[ -z "$TOOLS" ]]; then
      echo "No supported tool directory found (~/.codex, ~/.aone_copilot)." >&2
      echo "For Claude Code, install the plugin instead:" >&2
      echo "  /plugin marketplace add Mrlyk/superskills && /plugin install superskills@superskills" >&2
      echo "Or force the legacy install with --tools claude." >&2
      exit 1
    fi
  fi
fi

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "node is required (hooks and settings merge run on Node.js)." >&2
    exit 1
  fi
}

# Merge (or remove) superskills hook entries in <base>/settings.json.
# Idempotent: existing superskills entries are replaced, others untouched.
merge_settings() {
  local base="$1" mode="$2"
  node - "$base" "$mode" <<'EOF'
const fs = require('fs');
const path = require('path');
const [base, mode] = process.argv.slice(2);
const file = path.join(base, 'settings.json');
let settings = {};
if (fs.existsSync(file)) {
  const raw = fs.readFileSync(file, 'utf8').trim();
  if (raw) {
    try { settings = JSON.parse(raw); } catch (e) {
      console.error(`refusing to touch invalid JSON: ${file}`);
      process.exit(1);
    }
  }
}
settings.hooks = settings.hooks || {};
const isOurs = (entry) =>
  JSON.stringify(entry).includes(path.join('superskills', 'hooks'));
const strip = (event) => {
  if (!Array.isArray(settings.hooks[event])) return;
  settings.hooks[event] = settings.hooks[event].filter((e) => !isOurs(e));
  if (settings.hooks[event].length === 0) delete settings.hooks[event];
};
const add = (event, matcher, script, timeout) => {
  settings.hooks[event] = settings.hooks[event] || [];
  const entry = {
    hooks: [{
      type: 'command',
      command: `node "${path.join(base, 'superskills', 'hooks', script)}"`,
      timeout,
    }],
  };
  if (matcher) entry.matcher = matcher;
  settings.hooks[event].push(entry);
};
strip('SessionStart');
strip('Stop');
if (mode === 'install') {
  add('SessionStart', 'startup|resume|clear', 'session-start.js', 10);
  add('Stop', null, 'stop-learn.js', 15);
}
if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
EOF
}

# Copy a skill, renaming it ss-<name> (frontmatter name kept in sync).
copy_skill_prefixed() { # src-skill dest-dir
  local s="$1" dest="$2"
  mkdir -p "$dest"
  sed "s/^name: $s\$/name: ss-$s/" "$REPO_DIR/skills/$s/SKILL.md" > "$dest/SKILL.md"
}

install_claude_like() {
  local base="$1"
  mkdir -p "$base/skills" "$base/superskills/hooks"
  for s in "${SKILLS[@]}"; do
    rm -rf "$base/skills/ss-$s"
    copy_skill_prefixed "$s" "$base/skills/ss-$s"
  done
  for h in "${HOOK_FILES[@]}"; do
    cp "$REPO_DIR/hooks/$h" "$base/superskills/hooks/$h"
  done
  merge_settings "$base" install
}

uninstall_claude_like() {
  local base="$1"
  for s in "${SKILLS[@]}"; do rm -rf "$base/skills/ss-$s"; done
  rm -rf "$base/superskills"
  [[ -f "$base/settings.json" ]] && merge_settings "$base" uninstall
}

# Codex has no hooks; skills become custom prompts (frontmatter stripped).
install_codex() {
  local base="$1"
  mkdir -p "$base/prompts"
  for s in "${SKILLS[@]}"; do
    awk 'BEGIN{fm=0} /^---$/{fm++; next} fm!=1' \
      "$REPO_DIR/skills/$s/SKILL.md" > "$base/prompts/ss-$s.md"
  done
}

uninstall_codex() {
  local base="$1"
  for s in "${SKILLS[@]}"; do rm -f "$base/prompts/ss-$s.md"; done
}

require_node

IFS=',' read -ra TOOL_LIST <<< "$TOOLS"
for t in "${TOOL_LIST[@]}"; do
  base="$(tool_base "$t")" || { echo "unknown tool: $t" >&2; exit 1; }
  mkdir -p "$base"
  if [[ "$UNINSTALL" == 1 ]]; then
    case "$t" in
      codex) uninstall_codex "$base" ;;
      *) uninstall_claude_like "$base" ;;
    esac
    echo "superskills removed from $t ($base)"
  else
    case "$t" in
      codex) install_codex "$base" ;;
      claude)
        install_claude_like "$base"
        echo "note: legacy install for Claude Code; the plugin is preferred:" >&2
        echo "  /plugin marketplace add Mrlyk/superskills && /plugin install superskills@superskills" >&2
        ;;
      *) install_claude_like "$base" ;;
    esac
    echo "superskills installed for $t ($base)"
  fi
done

if [[ "$UNINSTALL" != 1 ]]; then
  cat <<'EOS'

Done. In each project, run the discover skill once to generate
.superskills/conventions.md + AGENTS.md + CLAUDE.md, then commit them.
Skills: ss-discover / ss-learn / ss-clarify / ss-test
Auto-learning hooks: active in Aone Copilot (and legacy Claude Code installs).
Codex: skills are installed as custom prompts (/ss-learn etc.); no hooks.
EOS
fi
