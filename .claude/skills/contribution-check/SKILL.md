---
name: contribution-check
description: Pre-flight checklist for contributions to Cal.com. Validates code changes against CONTRIBUTING.md rules, the 45 agent rules, PR size limits, commit format, linting, and type-checking. Does NOT push or create PRs — only reports issues.
argument-hint: [--skip-lint|--skip-types|--verbose]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

# Contribution Pre-Flight Check

Validates your working changes against Cal.com's contribution guidelines before you push. This skill is **read-only** — it never pushes code, creates PRs, or modifies anything on GitHub.

## Instructions

Run each check below in order. Report results as a checklist with pass/fail status.

### 1. Diff Size Check

```bash
# Count changed lines (excluding lockfiles, generated files, docs)
git diff --stat HEAD | tail -1
git diff --numstat HEAD -- . ':!yarn.lock' ':!*.generated.*' ':!*.lock' | awk '{ added += $1; removed += $2; files += 1 } END { print files " files, +" added " -" removed " lines" }'
```

**Rules (from CONTRIBUTING.md):**
- WARN if >500 lines changed (excluding docs, lockfiles, auto-generated)
- WARN if >10 code files modified
- Suggest splitting if either limit exceeded

### 2. Commit Message Format

```bash
git log --format="%s" -5
```

**Rules (from agents/rules/quality-pr-creation.md):**
- Must follow Conventional Commits: `feat:`, `fix:`, `refactor:`, `chore:`, `test:`, `docs:`, `perf:`, `ci:`
- Must be specific, not generic (e.g., "fix: handle timezone edge case in booking creation" not "fix: booking bug")
- FAIL if any recent commit doesn't follow the format

### 3. Issue Eligibility

If the user specified an issue number (via `$ARGUMENTS` or conversation context):

```bash
gh issue view <NUMBER> --json labels,state
```

**Rules (from CONTRIBUTING.md):**
- Features with `needs approval` label: FAIL — must wait for core team to remove the label
- Bugs, security, performance, docs: PASS — can start immediately even with `needs approval`
- Closed issues: WARN

### 4. File Naming Conventions

Scan changed files for naming violations:

```bash
git diff --name-only HEAD
```

**Rules (from CONTRIBUTING.md + agents/rules/quality-review-checklist.md):**
- Repository files: must have `Repository` suffix, PascalCase, prefix with technology (e.g., `PrismaAppRepository.ts`)
- Service files: must have `Service` suffix, PascalCase (e.g., `MembershipService.ts`)
- NO dot-suffixes like `.service.ts` or `.repository.ts` on new files
- `.test.ts`, `.spec.ts`, `.types.ts` are reserved and allowed

### 5. Code Quality Checks

Read each changed file and check:

**Rules (from agents/rules/quality-review-checklist.md):**
- Early returns preferred over deep nesting
- Prisma queries use `select` not `include`
- `credential.key` is never returned from tRPC endpoints or APIs
- All user-facing text uses `t()` for i18n
- No O(n^2) patterns in backend code
- No circular references introduced
- No barrel file imports (`index.ts` re-exports)
- Day.js usage in hot paths should prefer `.utc()` or native Date

### 6. Lint Check (unless `--skip-lint`)

```bash
yarn biome check --write .
```

FAIL if biome reports errors.

### 7. Type Check (unless `--skip-types`)

```bash
yarn type-check:ci --force
```

FAIL if type errors found.

### 8. Relevant Tests

Check if there are test files related to changed code:

```bash
# For each changed source file, look for corresponding test files
```

WARN if changed source files have no corresponding tests.

### 9. API Breaking Changes

If any files under `apps/api/` were changed:

**Rules (from agents/rules/api-no-breaking-changes.md):**
- No breaking changes on existing endpoints
- New functionality requires a versioned endpoint
- Old endpoints must remain functional

### 10. Summary Report

Present a final summary:

```
## Contribution Check Results

| Check                  | Status | Notes                          |
|------------------------|--------|--------------------------------|
| Diff size              | PASS   | 12 files, +234 -45 lines      |
| Commit format          | PASS   | feat: add timezone handling    |
| Issue eligibility      | PASS   | #28283 - bug, no approval needed |
| File naming            | PASS   |                                |
| Code quality           | WARN   | 1 Prisma include found         |
| Lint                   | PASS   |                                |
| Type check             | PASS   |                                |
| Tests                  | WARN   | 2 files missing test coverage  |
| API breaking changes   | N/A    | No API files changed           |

### Action Items
- [ ] Convert Prisma include to select in src/foo.ts:42
- [ ] Add tests for src/bar.ts
```

**IMPORTANT**: This skill NEVER pushes code, creates branches, creates PRs, or modifies anything on GitHub. It only reads and reports.
