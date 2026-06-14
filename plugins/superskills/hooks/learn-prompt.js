'use strict';
// Single source of truth for the auto-learning instruction.
//
// The Stop hook (stop-learn.js) injects this into a background `claude -p`
// learner; the learn-auto / learn-wiki benchmarks read it back (via the hook's
// dry-run mode) so arm B always tests the exact instruction production ships.
// Keep the wiki-merge cues here intact — they are what the benchmark grades.

const REPLAY_HEADER =
  'The following development session just happened in THIS project '
  + '(replayed for you verbatim):';

// What the learner must do with the session it just reviewed. Phrased to work
// both as a background prompt (after a replay) and as an inline Stop-block
// reason (the sync fallback), so there is one wording to benchmark and ship.
const LEARN_INSTRUCTION =
  'Review this development session for durable learnings: user corrections, '
  + 'pitfalls with their fixes, or project decisions not visible in code. '
  + 'If none qualify, do nothing and stop. Otherwise persist them in the project '
  + 'knowledge wiki at the repository root (the directory containing .git, NOT a '
  + 'subdirectory you happen to be working in): <repo-root>/.superskills/learnings/ '
  + 'holds one markdown page per topic (frontmatter topic/tags; concise rules), '
  + 'not a file per learning. Read INDEX.md, then merge each learning into the '
  + 'existing <topic>.md page it belongs to — keep the page focused and '
  + 'deduplicated, cross-link related topics with [[topic]] — creating a new '
  + '<topic>.md only when no topic fits. Then always update INDEX.md so it lists '
  + 'every page as a markdown link with a one-line summary, exactly in the form '
  + '`- [Topic](topic.md) — what it covers` — INDEX.md is the only file injected '
  + 'into future sessions, so a page missing from it (or listed without its '
  + '[link](file.md)) is invisible; then stop.';

// Render a transcript-derived replay plus the instruction for the background
// learner. The replay is the only context a fresh `claude -p` session has.
function buildChildPrompt(replay) {
  return `${REPLAY_HEADER}\n\n${replay}\n\n${LEARN_INSTRUCTION}`;
}

module.exports = { REPLAY_HEADER, LEARN_INSTRUCTION, buildChildPrompt };
