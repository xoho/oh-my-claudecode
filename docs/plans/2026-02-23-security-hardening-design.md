# Design: Full Security Hardening for oh-my-claudecode Fork

**Date:** 2026-02-23
**Status:** Approved
**Approach:** Defense-in-Depth, Phased Feature Branches
**Reference:** `MITIGATE_SECURITY_RISK_OHMYCLAUDE.md`, `SECURITY-FIXES.md`

## Context

We're implementing all 5 mitigation layers from `MITIGATE_SECURITY_RISK_OHMYCLAUDE.md` on our fork (`xoho/oh-my-claudecode`). PR #135 security fixes are already applied in the current codebase. This design covers the additional hardening beyond those fixes.

**User profile:** Professional codebases, all autonomous modes retained with guardrails, active notification channels including bidirectional reply listener, critical supply chain verification requirement.

## Architecture

Five independent feature branches, one per defense layer. Each branch is independently testable and mergeable. All branches target `dev`.

### Branch 1: `security/supply-chain`

**Files to create:**
- `.github/workflows/verify-bundles.yml` — CI workflow: rebuild from source, sha256 comparison
- `.npmrc` — `save-exact=true`, `package-lock=true`, `engine-strict=true`
- `scripts/verify-bundles.sh` — Manual bundle verification script

**No source code changes.** Pure CI/scripts/config.

### Branch 2: `security/config-hardening`

**Files to modify:**
- `src/config/loader.ts` — Add `guardrails` and `keywordDetection` sections to `DEFAULT_CONFIG`
- `src/hooks/keyword-detector/index.ts` — Read `keywordDetection.requireSlashPrefix` from config; when true, require `/` prefix on mode-activating keywords

**Files to create:**
- `config/hardened.jsonc` — Template with restrictive defaults

**Key design decisions:**
- Keyword patterns switch from `\bralph\b` to `^\/ralph\b` when `requireSlashPrefix: true`
- Cancel keywords (`cancelomc`, `stopomc`) remain bare-word — you always want those to work
- Config loads at module init time (consistent with existing pattern in `loader.ts`)

### Branch 3: `security/runtime-guardrails`

**Files to modify:**
- `src/hooks/persistent-mode/index.ts` — Add hard iteration cap (20), wall-clock timeout (30 min), stop-attempt grace period (3 attempts in 60s force-allows stop)
- `src/hooks/permission-handler/index.ts` — Add `NEVER_AUTO_APPROVE` deny-list, add audit logging to `.omc/state/auto-approval-audit.jsonl`, remove heredoc auto-approval exception

**Files to create:**
- `src/hooks/permission-handler/__tests__/deny-list.test.ts` — Tests for deny-list
- `src/hooks/persistent-mode/__tests__/guardrails.test.ts` — Tests for hard caps and stop override

**Key design decisions:**
- Hard cap constants are configurable via `guardrails` config section (from Branch 2), with non-configurable absolute maximums in source (safety net)
- Stop-attempt tracking stored in ralph/ultrawork/autopilot state files as `stopAttempts: number[]` (timestamps)
- Audit log uses append-only JSONL format with 0600 permissions
- `NEVER_AUTO_APPROVE` is a source-code constant (not configurable — these should never be auto-approved)

### Branch 4: `security/env-controls`

**Files to create:**
- `.githooks/pre-commit` — Block `.omc/state/`, `.omc/skills/`, `.omc/config` from being committed
- `scripts/enforce-permissions.sh` — Set 0600 on sensitive files
- `scripts/watch-claude-md.sh` — Detect unexpected CLAUDE.md modifications

**Other changes:**
- `.gitignore` — Already has `.omc/` covered (verified: line 3 of current `.gitignore`)
- Document `OMC_SKIP_CLAUDE_MD=1` in hardened config template

### Branch 5: `security/monitoring`

**Files to create:**
- `scripts/security-scan.sh` — Periodic health check (file permissions, gitignore, hooks, state files)
- `scripts/skill-integrity.sh` — Skill file manifest generation and verification

**No source code changes.** Pure scripts.

## Testing Strategy

- Branches 1, 4, 5: Script-only — manual testing + CI validation
- Branch 2: Unit tests for config loading and keyword detection with prefix
- Branch 3: Unit tests for deny-list, guardrail caps, stop-override logic; integration tests for audit logging

All tests use vitest (existing test framework).

## Implementation Order

1. Branch 5 (monitoring) — no dependencies, scripts only
2. Branch 4 (env-controls) — no dependencies, scripts only
3. Branch 1 (supply-chain) — no dependencies, CI + scripts
4. Branch 2 (config-hardening) — needed by Branch 3
5. Branch 3 (runtime-guardrails) — depends on config schema from Branch 2

Branches 1, 4, 5 can be implemented in parallel. Branch 2 must complete before Branch 3.

## Success Criteria

- All existing tests pass (966 tests)
- New tests pass for deny-list, guardrails, keyword prefix
- CI bundle verification workflow runs green
- Security scan script reports 0 failures on clean fork
- `DISABLE_OMC=1` still works as emergency kill switch
