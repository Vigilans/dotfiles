# AGENTS.md

This file provides user-level preferences that apply across all projects and repositories.

## Agent Conduct

### Suggestions must be text, not executable actions

- When the intent is to propose, suggest, or draft something for the user's review, present it as **text** (descriptions, tables, code blocks or diffs shown inline). Do not use file edits or shell commands to execute the proposal directly.
- Without auto-approve, commands go through permission prompts — this causes agents to treat command generation as a "showing the draft" mechanism (e.g. embedding a PR description inside `gh pr create`). But when the user has auto-approved commands, the same pattern silently executes the proposal without any review.
- Sequence: describe the proposal in text → wait for user approval → only then execute.

### Irreversible actions require explicit confirmation

- All irreversible actions (creating PRs/issues, pushing to remote, force push, posting comments, editing published content, git reset, git rebase, branch manipulation) require explicit user confirmation BEFORE execution.
- Draft the content, show it to the user, wait for "go ahead" / "发吧" / "确认" / "可以了".
- "先把X开了" / "先做X" does NOT mean "do everything". It means do ONLY that one step.
- Never chain irreversible steps together. Complete one, report back, wait for next instruction.
- "等确认" or similar — STOP and WAIT. Do not proceed with any irreversible action.
- Plan mode: user giving feedback on a plan does NOT mean "plan approved". Do not ExitPlanMode until user explicitly approves. A single comment may be one of multiple points.
- Do not modify branch history (reset, rebase, force push) without explicit instruction. The user's branches are their own — don't "sync", "update", or "clean up" branches unless explicitly told to.

### Minimal changes by default

- When modifying existing code, use the smallest possible change that achieves the goal.
- Do not refactor surrounding code that isn't part of the task.
- If the user reverted your changes because they were too invasive, take it seriously.

## Investigation workflow

- Investigations (tracing call chains, understanding architecture, reading large amounts of code) should be delegated to subagents. They consume significant context and distract the main agent from the ongoing conversation.
- All investigation conclusions must include citations. Use inline markers (e.g. `[1]`, `[2]`) in the text, with a references section at the end listing the actual sources as clickable links (`[file.py:123-134](path/to/file.py#L123-L134)`, PR/issue URLs, etc.).
- When an investigation traces a call chain or data flow, it must produce a **complete graph** (call graph, dependency graph, or data flow graph) as its primary deliverable.
- Graph format:
  - Tree structure with indentation showing caller→callee or data flow direction.
  - Each node annotated with `file.py:123-134` source references.
  - Phased/staged when the flow has distinct stages, e.g. use inline separator lines (`========== Stage 1: validation ==========`) within the tree.
  - Brief inline comments on each node explaining what happens at that step.
  - No need for decorative ASCII boxes when clean tree lines (`│`, `├─`, `└─`, `↓`, `→`) are sufficient.
- The graph should be globally complete — covering the full path from entry point to final effect. Every entity or concept mentioned in the summary should be traceable to a node in the graph, so the reader can map it back to a specific point in the chain rather than wondering "where did this come from?".

## Git/GitHub contribution workflow

### Remotes

- `origin` = upstream repo (e.g. <OriginAuthor>/<Repo>)
- `fork` = user's fork (e.g. Vigilans/<Repo>)

### Development flow

1. **dev branch**: All development happens on `dev`. Commit changes here first — this is the development record.
2. **Create PR branch**: `git fetch origin` first, then `git checkout -b vigilans/<topic> origin/main` — always branch off **latest** upstream main, NOT dev.
3. **Cherry-pick**: `git cherry-pick <commit-from-dev>` onto the PR branch.
4. **Show diff to user**: Review the diff before any push.
5. **User confirms** → push to fork: `git push -u fork vigilans/<topic>`
6. **Draft PR title + description**: Show to user for review.
7. **User confirms** → create PR via `gh pr create`.

### Rules

- Never skip the dev commit.
- Never push without explicit user confirmation.
- Never create a PR without explicit user confirmation of title + body. "先把分支开了" means push the branch, NOT create the PR.
- No Co-Authored-By: Claude lines unless user explicitly asks.
- No Claude/AI attribution anywhere — not in commits, PR body, issue body, or comments. Ever.

### Issue / PR comments

- Always draft the comment content and show to user first.
- User confirms → post via `gh api`.
- When editing a published comment, show the updated content to user first before patching.

### Syncing dev with upstream

- Only when the user explicitly requests it: `git fetch origin && git rebase origin/main` on dev to incorporate upstream changes.
- Already-merged commits will be skipped or produce conflicts. For cleanly merged commits, skip with `git rebase --skip`. For others, carefully assess the situation and determine the appropriate action.

### Rebase workflow

#### During rebase

- When `git rebase` reports conflicts, check **every** conflicting file before `git add`. Never let conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) get committed — a committed conflict marker corrupts that commit and all subsequent commits in the chain.
- When syncing dev with upstream, some dev commits may have been superseded by upstream commits with different content or message rather than cherry-picked directly. Carefully determine whether corresponding dev commits should be dropped, edited, split, or otherwise adjusted.

#### Iterative rebase

- Rebase is not a one-shot operation. After a rebase completes, new problems may be discovered (build errors, logic issues, review feedback). When that happens, **rebase again** to edit the specific commit where the problem was introduced — the previous rebase result is the starting point for the next iteration, not something to discard.
- **Never** try to fix a problem introduced in an earlier commit by only amending the latest commit. That leaves the earlier commits broken.
- **Never** `git reset --hard` back to before the rebase and redo the entire rebase from scratch.
- **Never** use `git cherry-pick` as a substitute for `git rebase -i` when the goal is to restructure existing commit history (editing, reordering, dropping, splitting commits). Rebase rewrites history in place; cherry-pick creates new commits and does not fix the existing chain.

### Partial staging workflow

**Trigger check**: any request to stage/unstage **part of a single file's changes** (not whole files) — phrases like "commit/stage 这个文件的某部分", "把某些部分排除出这次 commit", "exclude some lines from a staged file", "split this file's changes across commits" — STOP and follow this section. Do not reflexively reach for `git restore --staged` + edit + `git add`.

When the user wants to stage or unstage part of a file's changes (not the whole file), **MUST NOT** edit the file to the desired state and then `git add` the whole file. Instead, build a selected patch from a base diff and apply it to the index without touching the working tree.

#### Stage selected changes

- Base diff: `git diff path`.
- Build the selected patch by transforming each line of the base diff verbatim — no rewrites, no whitespace fixes:
  - context (` `): keep
  - `-` selected → keep as `-`; not selected → convert to ` ` (context)
  - `+` selected → keep as `+`; not selected → omit entirely
  - file and `@@` headers: keep — `--recount` rewrites `@@` counts
- Apply: feed the patch via single-quoted heredoc — `git apply --cached --recount <<'PATCH' ... PATCH`. Single quotes keep `$`, backticks, and `{{ ... }}` literal. Apply is atomic — a failed apply leaves the index unchanged.
- Verify: `git diff --cached` + `git diff` together must equal the full pre-stage diff. Mismatch = rebuild the patch.

#### Unstage selected changes

- Base diff: `git diff --cached -R path`. Same transformation rules as Stage. Apply forward with the same `git apply --cached --recount`.
- Never `git apply --reverse` on the forward diff: unselected `-` lines converted to context don't exist in the current index, so the `--reverse` context check fails. `-R` base + forward apply avoids this.
