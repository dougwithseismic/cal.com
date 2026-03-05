---
name: pr-prepare
description: Prepares a pull request description using Cal.com's PR template. Generates the title, body, and checklist — then STOPS and presents everything for user review. Does NOT create the PR or push code without explicit user consent.
argument-hint: <issue-number> [--draft]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

# PR Preparation Skill

Drafts a complete pull request using Cal.com's PR template, then **stops for your review**. Nothing is pushed or created without your explicit say-so.

## Instructions

### 1. Gather Context

```bash
# Current branch and diff from main
git branch --show-current
git log main..HEAD --oneline
git diff --stat main...HEAD
git diff main...HEAD -- . ':!yarn.lock' ':!*.generated.*'
```

If `$ARGUMENTS` contains an issue number, fetch the issue:

```bash
gh issue view <NUMBER> --json title,body,labels,state
```

### 2. Generate PR Title

**Rules (from agents/rules/quality-pr-creation.md + CI enforcement):**
- Must follow Conventional Commits: `feat:`, `fix:`, `refactor:`, `chore:`, etc.
- Under 70 characters
- Be specific about what changed and why
- Examples:
  - `fix: handle timezone edge case in booking creation`
  - `refactor: migrate webhooks page to coss/ui components`
  - `feat: add upgrade banners for teams and organizations`

### 3. Generate PR Body

Use the template from `.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## What does this PR do?

<Summary of changes — what and why, not just what files changed>

- Fixes #<NUMBER> (GitHub issue number)

## Visual Demo (For contributors especially)

<If UI changes: describe what to screenshot/record>
<If no UI changes: "N/A — backend/infrastructure change">

## Mandatory Tasks (DO NOT REMOVE)

- [ ] I have self-reviewed the code (A decent size PR without self-review might be rejected).
- [ ] I have updated the developer docs in /docs if this PR makes changes that would require a documentation change. If N/A, write N/A here and check the checkbox.
- [ ] I confirm automated tests are in place that prove my fix is effective or that my feature works.

## How should this be tested?

<Step-by-step reproduction/testing instructions>
- What environment variables are needed?
- What test data is required?
- What is the expected behavior (input → output)?

## Checklist

- I have read the [contributing guide](https://github.com/calcom/cal.com/blob/main/CONTRIBUTING.md)
- My code follows the style guidelines of this project
- I have commented my code, particularly in hard-to-understand areas
- I have checked that my changes generate no new warnings
- My PR is appropriately sized (<500 lines, <10 files)
```

### 4. Size Validation

```bash
git diff --numstat main...HEAD -- . ':!yarn.lock' ':!*.generated.*' ':!*.lock' | awk '{ added += $1; removed += $2; files += 1 } END { print files, added, removed }'
```

If >500 lines or >10 files, suggest how to split:
- Database/schema changes separate from app logic
- Frontend and backend in separate PRs
- Refactoring separate from new features

### 5. Present for Review — STOP HERE

Display the complete PR draft to the user:

```
## PR Ready for Review

**Title:** fix: handle timezone edge case in booking creation

**Base:** main ← your-branch-name

**Body:**
<the full PR body from step 3>

---

### Pre-push checklist
- [ ] `yarn biome check --write .` passes
- [ ] `yarn type-check:ci --force` passes
- [ ] Relevant tests pass
- [ ] Branch is up to date with main

### Next steps (requires your approval):
1. Push branch: `git push -u origin <branch-name>`
2. Create PR: `gh pr create --draft --title "..." --body "..."`
```

**CRITICAL**: Do NOT execute the "Next steps" commands. Only show them. Wait for the user to explicitly ask you to push and/or create the PR.

### 6. Only On Explicit User Consent

If the user explicitly says to proceed (e.g., "go ahead", "create the PR", "push it"):
- Create PR in **draft mode** by default (per agents/rules/quality-pr-creation.md)
- Use `--draft` flag unless user specifically says "ready for review"
- Show the PR URL after creation

**NEVER auto-push or auto-create PRs. The user must explicitly consent each time.**
