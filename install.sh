#!/usr/bin/env bash
# superskills installer for tools that cannot use the marketplace one-liners.
#
#   ./install.sh                       # autodetect: Codex (~/.codex), Aone Copilot (~/.aone_copilot)
#   ./install.sh --tools codex,aone
#   ./install.sh --tools claude        # legacy settings-based install (prefer the plugin:
#                                      #   /plugin marketplace add Mrlyk/superskills)
#   ./install.sh --all                 # codex + aone + claude(legacy)
#   ./install.sh --project [dir]       # project-level install (default dir: cwd):
#                                      #   claude → <dir>/.claude/settings.json plugin entries
#                                      #   aone   → <dir>/.aone_copilot/ skills + hooks
#                                      #   nothing user-global is touched
#   ./install.sh --uninstall [--tools ...] [--project [dir]]
#
# Codex: installs the real Codex plugin via `codex plugin` when available
# (set SUPERSKILLS_CODEX_MODE=prompts to force the custom-prompts fallback).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/superskills"
SKILLS=(learn discover clarify test)   # installed as ss-<name> to avoid collisions
HOOK_FILES=(session-start.js stop-verify.js stop-learn.js learn-prompt.js)

TOOLS=""
UNINSTALL=0
ALL=0
PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools) TOOLS="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --project)
      if [[ $# -gt 1 && "${2:0:1}" != "-" ]]; then PROJECT="$2"; shift 2; else PROJECT="$PWD"; shift; fi ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

if [[ -z "$TOOLS" && -z "$PROJECT" ]]; then
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

# Merge (or remove) superskills hook entries in <settingsDir>/settings.json.
# cmdBase prefixes the hook command path: an absolute dir for user-level
# installs, or a $CLAUDE_PROJECT_DIR-relative prefix for project installs.
# Idempotent: existing superskills entries are replaced, others untouched.
merge_settings() {
  local settingsDir="$1" mode="$2" cmdBase="$3"
  node - "$settingsDir" "$mode" "$cmdBase" <<'EOF'
const fs = require('fs');
const path = require('path');
const [base, mode, cmdBase] = process.argv.slice(2);
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
      command: `node "${cmdBase}/superskills/hooks/${script}"`,
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
  add('Stop', null, 'stop-verify.js', 15);
add('Stop', null, 'stop-learn.js', 15);
}
if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
EOF
}

# Codex auto-learning: merge a Stop hook into ~/.codex/hooks.json (same hook JSON
# shape as Claude Code). Only stop-learn (validated on `codex exec`); recall stays
# via the AGENTS.md INDEX pointer. SUPERSKILLS_LEARN_CLI=codex selects the codex
# learner. Idempotent: strips our prior entry before adding.
merge_codex_hooks() {
  local base="$1" mode="$2"
  node - "$base" "$mode" <<'EOF'
const fs = require('fs');
const path = require('path');
const [base, mode] = process.argv.slice(2);
const file = path.join(base, 'hooks.json');
let cfg = {};
if (fs.existsSync(file)) {
  const raw = fs.readFileSync(file, 'utf8').trim();
  if (raw) {
    try { cfg = JSON.parse(raw); } catch (e) {
      console.error(`refusing to touch invalid JSON: ${file}`);
      process.exit(1);
    }
  }
}
cfg.hooks = cfg.hooks || {};
const isOurs = (entry) =>
  JSON.stringify(entry).includes(path.join('superskills', 'hooks'));
if (Array.isArray(cfg.hooks.Stop)) {
  cfg.hooks.Stop = cfg.hooks.Stop.filter((e) => !isOurs(e));
  if (cfg.hooks.Stop.length === 0) delete cfg.hooks.Stop;
}
if (mode === 'install') {
  const script = path.join(base, 'superskills', 'hooks', 'stop-learn.js');
  cfg.hooks.Stop = cfg.hooks.Stop || [];
  cfg.hooks.Stop.push({
    hooks: [{ type: 'command', command: `SUPERSKILLS_LEARN_CLI=codex node "${script}"`, timeout: 15 }],
  });
}
if (Object.keys(cfg.hooks).length === 0) delete cfg.hooks;
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n');
EOF
}

install_codex_hooks() { # base
  local base="$1"
  mkdir -p "$base/superskills/hooks"
  cp "$PLUGIN_DIR/hooks/stop-learn.js" "$base/superskills/hooks/stop-learn.js"
  cp "$PLUGIN_DIR/hooks/learn-prompt.js" "$base/superskills/hooks/learn-prompt.js"
  merge_codex_hooks "$base" install
}

uninstall_codex_hooks() { # base
  local base="$1"
  [[ -f "$base/hooks.json" ]] && merge_codex_hooks "$base" uninstall
  rm -f "$base/superskills/hooks/stop-learn.js" "$base/superskills/hooks/learn-prompt.js"
}

# Copy a skill, renaming it ss-<name> (frontmatter name kept in sync).
copy_skill_prefixed() { # src-skill dest-dir
  local s="$1" dest="$2"
  mkdir -p "$dest"
  sed "s/^name: $s\$/name: ss-$s/" "$PLUGIN_DIR/skills/$s/SKILL.md" > "$dest/SKILL.md"
}

install_claude_like() {
  local base="$1"
  mkdir -p "$base/skills" "$base/superskills/hooks"
  for s in "${SKILLS[@]}"; do
    rm -rf "$base/skills/ss-$s"
    copy_skill_prefixed "$s" "$base/skills/ss-$s"
  done
  for h in "${HOOK_FILES[@]}"; do
    cp "$PLUGIN_DIR/hooks/$h" "$base/superskills/hooks/$h"
  done
  merge_settings "$base" install "$base"
}

uninstall_claude_like() {
  local base="$1"
  for s in "${SKILLS[@]}"; do rm -rf "$base/skills/ss-$s"; done
  rm -rf "$base/superskills"
  [[ -f "$base/settings.json" ]] && merge_settings "$base" uninstall "$base"
}

# Project-level Claude Code install: declare the marketplace and enable the
# plugin in <project>/.claude/settings.json only — the exact files written by
# `claude plugin ... --scope project`. Nothing user-global is touched; when a
# teammate opens the project, Claude Code prompts to install from GitHub.
merge_project_claude() { # projectDir mode
  local proj="$1" mode="$2"
  mkdir -p "$proj/.claude"
  node - "$proj" "$mode" <<'EOF'
const fs = require('fs');
const path = require('path');
const [proj, mode] = process.argv.slice(2);
const file = path.join(proj, '.claude', 'settings.json');
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
if (mode === 'install') {
  settings.extraKnownMarketplaces = settings.extraKnownMarketplaces || {};
  settings.extraKnownMarketplaces.superskills = {
    source: { source: 'github', repo: 'Mrlyk/superskills' },
  };
  settings.enabledPlugins = settings.enabledPlugins || {};
  settings.enabledPlugins['superskills@superskills'] = true;
} else {
  if (settings.extraKnownMarketplaces) {
    delete settings.extraKnownMarketplaces.superskills;
    if (Object.keys(settings.extraKnownMarketplaces).length === 0) delete settings.extraKnownMarketplaces;
  }
  if (settings.enabledPlugins) {
    delete settings.enabledPlugins['superskills@superskills'];
    if (Object.keys(settings.enabledPlugins).length === 0) delete settings.enabledPlugins;
  }
}
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
EOF
}

# Project-level Aone Copilot install: skills + hooks live inside the project
# (commit .aone_copilot/ to share with the team); hook commands resolve via
# $CLAUDE_PROJECT_DIR so they work on every teammate's machine.
install_aone_project() {
  local proj="$1"
  local base="$proj/.aone_copilot"
  mkdir -p "$base/skills" "$base/superskills/hooks"
  for s in "${SKILLS[@]}"; do
    rm -rf "$base/skills/ss-$s"
    copy_skill_prefixed "$s" "$base/skills/ss-$s"
  done
  for h in "${HOOK_FILES[@]}"; do
    cp "$PLUGIN_DIR/hooks/$h" "$base/superskills/hooks/$h"
  done
  merge_settings "$base" install '$CLAUDE_PROJECT_DIR/.aone_copilot'
}

uninstall_aone_project() {
  local proj="$1"
  local base="$proj/.aone_copilot"
  for s in "${SKILLS[@]}"; do rm -rf "$base/skills/ss-$s"; done
  rm -rf "$base/superskills"
  [[ -f "$base/settings.json" ]] && merge_settings "$base" uninstall '$CLAUDE_PROJECT_DIR/.aone_copilot'
}

codex_plugin_capable() {
  [[ "${SUPERSKILLS_CODEX_MODE:-plugin}" != prompts ]] \
    && command -v codex >/dev/null 2>&1 \
    && codex plugin --help >/dev/null 2>&1
}

# Native Codex plugin install: register this repo as a marketplace, then add.
install_codex_plugin() {
  if ! codex plugin marketplace list 2>/dev/null | grep -q "superskills"; then
    codex plugin marketplace add "$REPO_DIR" >/dev/null
  fi
  if ! codex plugin list 2>/dev/null | grep -q "superskills"; then
    codex plugin add superskills@superskills >/dev/null
  fi
  echo "superskills installed for codex as a plugin (marketplace: $REPO_DIR)"
  echo "note: keep this clone in place; Codex resolves the plugin from it."
}

uninstall_codex_plugin() {
  codex plugin remove superskills >/dev/null 2>&1 || true
  codex plugin marketplace remove superskills >/dev/null 2>&1 || true
}

# Fallback for Codex CLIs without plugin support: custom prompts, no hooks.
install_codex_prompts() {
  local base="$1"
  mkdir -p "$base/prompts"
  for s in "${SKILLS[@]}"; do
    awk 'BEGIN{fm=0} /^---$/{fm++; next} fm!=1' \
      "$PLUGIN_DIR/skills/$s/SKILL.md" > "$base/prompts/ss-$s.md"
  done
  echo "superskills installed for codex as custom prompts ($base/prompts)"
}

uninstall_codex_prompts() {
  local base="$1"
  for s in "${SKILLS[@]}"; do rm -f "$base/prompts/ss-$s.md"; done
}

require_node

# Project-level mode: write only inside the target project, never user-global.
if [[ -n "$PROJECT" ]]; then
  PROJECT="$(cd "$PROJECT" && pwd)" || { echo "project dir not found: $PROJECT" >&2; exit 1; }
  PROJ_TOOLS="${TOOLS:-claude,aone}"
  IFS=',' read -ra PROJ_LIST <<< "$PROJ_TOOLS"
  for t in "${PROJ_LIST[@]}"; do
    case "$t" in
      claude)
        if [[ "$UNINSTALL" == 1 ]]; then
          [[ -f "$PROJECT/.claude/settings.json" ]] && merge_project_claude "$PROJECT" uninstall
          echo "superskills removed from project claude config ($PROJECT/.claude/settings.json)"
        else
          merge_project_claude "$PROJECT" install
          echo "superskills enabled for claude at project scope ($PROJECT/.claude/settings.json)"
          echo "commit .claude/settings.json; teammates get an install prompt on next session."
        fi
        ;;
      aone)
        if [[ "$UNINSTALL" == 1 ]]; then
          uninstall_aone_project "$PROJECT"
          echo "superskills removed from project aone config ($PROJECT/.aone_copilot)"
        else
          install_aone_project "$PROJECT"
          echo "superskills installed for aone at project scope ($PROJECT/.aone_copilot)"
          echo "commit .aone_copilot/ to share it with the team."
        fi
        ;;
      codex)
        echo "codex: plugins are global-only (no project scope in codex CLI)." >&2
        echo "Project-level coverage for Codex comes from AGENTS.md + .superskills/ (run the discover skill)." >&2
        ;;
      *) echo "unknown tool: $t" >&2; exit 1 ;;
    esac
  done
  exit 0
fi

IFS=',' read -ra TOOL_LIST <<< "$TOOLS"
for t in "${TOOL_LIST[@]}"; do
  base="$(tool_base "$t")" || { echo "unknown tool: $t" >&2; exit 1; }
  mkdir -p "$base"
  if [[ "$UNINSTALL" == 1 ]]; then
    case "$t" in
      codex)
        if codex_plugin_capable; then uninstall_codex_plugin; fi
        uninstall_codex_prompts "$base"
        uninstall_codex_hooks "$base"
        ;;
      *) uninstall_claude_like "$base" ;;
    esac
    echo "superskills removed from $t ($base)"
  else
    case "$t" in
      codex)
        if codex_plugin_capable; then install_codex_plugin; else install_codex_prompts "$base"; fi
        install_codex_hooks "$base"
        echo "codex auto-learning enabled via ~/.codex/hooks.json (Stop -> codex exec learner)"
        ;;
      claude)
        install_claude_like "$base"
        echo "superskills installed for claude ($base)"
        echo "note: legacy install for Claude Code; the plugin is preferred:" >&2
        echo "  /plugin marketplace add Mrlyk/superskills && /plugin install superskills@superskills" >&2
        ;;
      *)
        install_claude_like "$base"
        echo "superskills installed for $t ($base)"
        ;;
    esac
  fi
done

if [[ "$UNINSTALL" != 1 ]]; then
  cat <<'EOS'

Done. In each project, run the discover skill once to generate
.superskills/conventions.md + AGENTS.md + CLAUDE.md, then commit them.
Auto-learning hooks: Claude Code (plugin), Aone Copilot, and Codex (Stop hook in
~/.codex/hooks.json, learner runs via `codex exec`). The learn skill also works
manually everywhere.
EOS
fi
