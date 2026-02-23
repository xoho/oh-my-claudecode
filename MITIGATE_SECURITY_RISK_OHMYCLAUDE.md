# Security Mitigation Plan: oh-my-claudecode

**Date:** 2026-02-23
**Scope:** Fork of [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) for professional codebase usage
**Approach:** Defense-in-Depth — five independent mitigation layers, each reducing risk regardless of other layers
**Reference:** `SECURITY_REVIEW_OHMYCLAUDECODE.md` (11 identified issues: 3 CRITICAL, 5 HIGH, 3 MEDIUM)

---

## 1. Executive Summary & Risk Matrix

Every issue from the security review is mapped to the mitigation layer(s) that address it, the implementation effort required, and the residual risk after mitigation.

| # | Issue | Severity | Mitigation Layer(s) | Effort | Residual Risk |
|---|-------|----------|---------------------|--------|---------------|
| 1 | Total hook interception | CRITICAL | L2 Config Hardening | Medium | **Low** — hooks remain but are scoped, audited, and individually toggleable |
| 2 | Stop-blocking (persistent-mode) | CRITICAL | L3 Runtime Guardrails | Medium | **Low** — hard caps, confirmation gates, and timeout enforcement |
| 3 | CLAUDE.md overwrite | CRITICAL | L2 Config Hardening, L4 Environmental | Low | **Very Low** — overwrite prevented, content reviewed before merge |
| 4 | Auto-approval of bash commands | HIGH | L3 Runtime Guardrails | Low | **Low** — tighter allowlist, no heredoc exceptions, audit logging |
| 5 | External data channels + reply listener | HIGH | L4 Environmental, L5 Monitoring | High | **Medium** — channels hardened but bidirectional injection remains an inherent risk |
| 6 | Un-auditable pre-built bundles | HIGH | L1 Supply Chain | Medium | **Very Low** — rebuild from source, CI-verified checksums |
| 7 | Python REPL via MCP | HIGH | L3 Runtime Guardrails, L4 Environmental | Medium | **Low** — sandboxed or disabled per-project |
| 8 | Persistent autonomous state | HIGH | L3 Runtime Guardrails, L4 Environmental | Low | **Very Low** — state validation, `.gitignore`, pre-commit rejection |
| 9 | Learned skills as injection vectors | MEDIUM | L4 Environmental, L5 Monitoring | Medium | **Low** — file permissions, integrity checks, content scanning |
| 10 | Keyword hijacking | MEDIUM | L2 Config Hardening | Low | **Very Low** — explicit prefix requirement eliminates accidental activation |
| 11 | npm name mismatch | MEDIUM | L1 Supply Chain | Low | **Very Low** — lockfile pinning, hash verification |

**Legend:**
- **Very Low** — Risk effectively eliminated for practical purposes
- **Low** — Risk reduced to acceptable level; requires active circumvention to exploit
- **Medium** — Risk reduced but residual attack surface exists; monitoring compensates

---

## 2. Layer 1 — Supply Chain Verification

**Addresses:** Issue #6 (un-auditable bundles), Issue #11 (npm name mismatch)

### 2.1 Reproducible Build Verification

The `/bridge/` directory contains pre-built minified JavaScript bundles that cannot be audited by inspection:

| Bundle | Size | Source Location |
|--------|------|-----------------|
| `mcp-server.cjs` | 805 KB | `src/mcp/` via `scripts/build-mcp-server.mjs` |
| `team-mcp.cjs` | 622 KB | `src/interop/` via `scripts/build-mcp-server.mjs` |
| `team-bridge.cjs` | 59 KB | `src/interop/` via `scripts/build-bridge-entry.mjs` |
| `runtime-cli.cjs` | 39 KB | `src/cli/` via `scripts/build-bridge-entry.mjs` |

**Mitigation procedure:**

1. **Rebuild from source and compare:**
   ```bash
   # Clean build environment
   rm -rf dist/ bridge/mcp-server.cjs bridge/team-mcp.cjs bridge/team-bridge.cjs bridge/runtime-cli.cjs

   # Install exact dependency versions
   npm ci

   # Build from TypeScript source
   npm run build

   # Generate checksums for freshly built bundles
   sha256sum bridge/*.cjs > bridge/checksums-rebuilt.sha256

   # Compare with committed bundles (restore from git)
   git checkout -- bridge/
   sha256sum bridge/*.cjs > bridge/checksums-committed.sha256

   # Diff the checksum files
   diff bridge/checksums-committed.sha256 bridge/checksums-rebuilt.sha256
   ```

2. **If checksums differ:** Investigate the delta. Minification non-determinism (e.g., variable naming) may cause benign differences. Use a JavaScript formatter to compare structure:
   ```bash
   # Decompile and compare structure
   npx prettier --parser babel bridge/mcp-server.cjs > /tmp/committed.js
   npm run build
   npx prettier --parser babel bridge/mcp-server.cjs > /tmp/rebuilt.js
   diff /tmp/committed.js /tmp/rebuilt.js
   ```

3. **If semantic differences exist:** Do not use the committed bundles. Replace with your own builds and commit them to your fork.

### 2.2 CI Workflow for Bundle Verification

Add a GitHub Actions workflow to your fork that rebuilds on every PR and fails if bundles diverge:

**File: `.github/workflows/verify-bundles.yml`**
```yaml
name: Verify Bridge Bundles
on:
  pull_request:
    branches: [dev, main]
  push:
    branches: [dev]

jobs:
  verify-bundles:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Save committed bundle checksums
        run: sha256sum bridge/*.cjs | sort > /tmp/committed.sha256

      - name: Clean install and rebuild
        run: |
          npm ci
          npm run build

      - name: Compare bundle checksums
        run: |
          sha256sum bridge/*.cjs | sort > /tmp/rebuilt.sha256
          if ! diff /tmp/committed.sha256 /tmp/rebuilt.sha256; then
            echo "::error::Pre-built bundles do not match source rebuild!"
            echo "Committed checksums:"
            cat /tmp/committed.sha256
            echo "Rebuilt checksums:"
            cat /tmp/rebuilt.sha256
            exit 1
          fi
          echo "Bundle verification passed — checksums match."
```

### 2.3 npm Package Pinning

**Problem:** The GitHub repo is `oh-my-claudecode` but the npm package is `oh-my-claude-sisyphus`. This creates typosquatting risk.

**Mitigations:**

| Action | Details |
|--------|---------|
| Pin exact version in `package.json` | Use `"oh-my-claude-sisyphus": "4.4.1"` (no caret/tilde range) |
| Verify package provenance | Run `npm audit signatures` to check registry signatures |
| Use lockfile integrity | Ensure `package-lock.json` is committed with `integrity` hashes |
| Add `.npmrc` to enforce strict mode | `save-exact=true` and `package-lock=true` |
| Monitor for typosquats | Periodically check npm for packages named `oh-my-claudecode`, `oh-my-claude`, `ohmyclaudecode` |

**File: `.npmrc` (add to repo root)**
```ini
save-exact=true
package-lock=true
engine-strict=true
```

### 2.4 Dependency Audit

Run periodic dependency audits since oh-my-claudecode pulls in its own dependency tree:

```bash
# Check for known vulnerabilities
npm audit --production

# Check for outdated packages with known CVEs
npx npm-check-updates --target patch
```

Add to CI:
```yaml
      - name: Security audit
        run: npm audit --production --audit-level=high
```

---

## 3. Layer 2 — Configuration Hardening

**Addresses:** Issue #1 (hook interception), Issue #3 (CLAUDE.md overwrite), Issue #10 (keyword hijacking)

### 3.1 Hook Scope Reduction

The plugin registers hooks on **every** Claude Code lifecycle event. While all hooks remain active, you can control their behavior through configuration.

**Current hook registrations (from `hooks/hooks.json`):**

| Event | Hooks | Risk Level | Recommendation |
|-------|-------|------------|----------------|
| UserPromptSubmit | keyword-detector, skill-injector | HIGH | Restrict keyword detection to explicit prefixes |
| SessionStart | session-start, project-memory-session | LOW | Keep — initialization only |
| SessionStart (init) | setup-init | MEDIUM | Prevent CLAUDE.md overwrite (see 3.2) |
| SessionStart (maintenance) | setup-maintenance | LOW | Keep — cleanup only |
| PreToolUse | pre-tool-enforcer, context-safety | MEDIUM | Audit enforcer rules, keep safety checks |
| PermissionRequest | permission-handler | HIGH | Tighten allowlist (see Layer 3) |
| PostToolUse | post-tool-verifier, project-memory-posttool | LOW | Keep — verification and memory |
| PostToolUseFailure | post-tool-use-failure | LOW | Keep — error handling |
| SubagentStart/Stop | subagent-tracker, verify-deliverables | LOW | Keep — tracking only |
| PreCompact | pre-compact, project-memory-precompact | LOW | Keep — context preservation |
| Stop | context-guard-stop, persistent-mode, code-simplifier | CRITICAL | Add guardrails (see Layer 3) |
| SessionEnd | session-end | LOW | Keep — cleanup |

**Fork-specific configuration** (`~/.config/claude-omc/config.jsonc`):

```jsonc
{
  // Set to false to disable individual hooks
  "hooks": {
    "keyword-detector": true,
    "skill-injector": true,
    "permission-handler": true,
    "persistent-mode": true,
    "learner": false
  },

  "features": {
    "parallelExecution": true,
    "lspTools": true,
    "astTools": true,
    "continuationEnforcement": true,
    "autoContextInjection": true,
    "learnedSkillsEnabled": false,
    "pythonReplEnabled": false
  }
}
```

### 3.2 CLAUDE.md Overwrite Protection

The installer at `src/installer/index.ts` (lines 316-383) merges OMC content into `~/.claude/CLAUDE.md` using `<!-- OMC:START -->` / `<!-- OMC:END -->` markers.

**Mitigations:**

| Mitigation | Implementation |
|------------|---------------|
| **Review before merge** | Read `docs/CLAUDE.md` (17KB) and audit the 28-agent protocol before allowing installation |
| **Prevent auto-overwrite** | Set `OMC_SKIP_CLAUDE_MD=1` environment variable during setup |
| **Use project-level instead** | Place OMC instructions in project `.claude/CLAUDE.md` (not global `~/.claude/CLAUDE.md`) to limit blast radius |
| **Pin content hash** | After reviewing and approving the CLAUDE.md content, record its sha256 hash. Alert if it changes on update |
| **Watch file changes** | Use `inotifywait` or a git pre-commit hook to detect modifications to `~/.claude/CLAUDE.md` |

**Environment variable to prevent overwrite:**
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
export OMC_SKIP_CLAUDE_MD=1
```

**File watcher script (`scripts/watch-claude-md.sh`):**
```bash
#!/bin/bash
EXPECTED_HASH="<sha256-of-approved-content>"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

CURRENT_HASH=$(sha256sum "$CLAUDE_MD" 2>/dev/null | cut -d' ' -f1)
if [ "$CURRENT_HASH" != "$EXPECTED_HASH" ]; then
  echo "WARNING: ~/.claude/CLAUDE.md has been modified!"
  echo "Expected: $EXPECTED_HASH"
  echo "Current:  $CURRENT_HASH"
  exit 1
fi
```

### 3.3 Keyword Hijacking Prevention

The keyword detector at `src/hooks/keyword-detector/index.ts` matches bare words like "team", "autopilot", "ralph" in natural conversation.

**Current keywords and their risk:**

| Keyword | Bare Word Match | Risk | Mitigation |
|---------|-----------------|------|------------|
| `ralph` | Yes | HIGH — uncommon but still a name | Require `/ralph` prefix |
| `autopilot` | Yes | HIGH — common metaphor | Require `/autopilot` prefix |
| `team` | Partial (negative lookahead) | MEDIUM — extremely common word | Require `/team` prefix |
| `ultrawork` / `ulw` | Yes | LOW — uncommon | Keep or require prefix |
| `swarm` | Yes | MEDIUM — used in technical discussions | Require `/swarm` prefix |
| `tdd` / `test first` | Yes | MEDIUM — common dev term | Require `/tdd` prefix |
| `deepsearch` | Yes | LOW — uncommon | Keep as-is |
| `cancelomc` / `stopomc` | Yes | LOW — clearly intentional | Keep as-is |

**Recommended fork change:** Modify `src/hooks/keyword-detector/index.ts` to require an explicit `/` prefix for all mode-activating keywords:

```typescript
// BEFORE (dangerous — bare word matching):
// Pattern: /\bralph\b/i
// Pattern: /\bautopilot\b/i

// AFTER (safe — explicit command prefix):
// Pattern: /^\/ralph\b/i    (only matches "/ralph" at start of message)
// Pattern: /^\/autopilot\b/i
// Pattern: /^\/team\b/i
// Pattern: /^\/swarm\b/i
// Pattern: /^\/tdd\b/i
```

**Configuration override** (`config.jsonc`):
```jsonc
{
  "magicKeywords": {
    "ultrawork": ["/ultrawork", "/ulw"],
    "search": ["/deepsearch"],
    "analyze": ["/deep-analyze"],
    "ultrathink": ["/ultrathink"]
  },
  "keywordDetection": {
    "requireSlashPrefix": true
  }
}
```

---

## 4. Layer 3 — Runtime Guardrails

**Addresses:** Issue #2 (stop-blocking), Issue #4 (auto-approval), Issue #7 (Python REPL), Issue #8 (persistent state)

### 4.1 Stop-Blocking Guardrails

The `persistent-mode.mjs` Stop hook returns `{"decision": "block"}` to prevent Claude from stopping during autonomous modes. This is the single most dangerous behavior in the plugin.

**Current behavior:**
- Ralph: Blocks stop until iteration limit reached (default 10, auto-extends by +10)
- Ultrawork: Blocks until all todos cleared
- Autopilot: Blocks until all phases complete
- Team: Blocks respecting team phase transitions

**Proposed guardrails:**

| Guardrail | Implementation | Addresses |
|-----------|---------------|-----------|
| **Hard iteration cap** | Set non-overridable maximum (e.g., 20 iterations) that cannot be auto-extended | Ralph auto-extending to infinity |
| **Wall-clock timeout** | Kill autonomous mode after N minutes regardless of iteration count | Runaway sessions |
| **Confirmation gate** | Require user confirmation before blocking the first stop attempt | Unexpected stop-blocking |
| **Grace period** | After N stop attempts in M seconds, force-allow stop | User clearly wants to stop |
| **Cost tracking** | Log estimated API cost per iteration; alert at threshold | Unexpected cost accumulation |
| **Emergency kill** | `DISABLE_OMC=1` or `touch .omc/KILLSWITCH` immediately halts all modes | Last resort override |

**Fork changes to `src/hooks/persistent-mode/index.ts`:**

```typescript
// Add at top of checkRalphLoop():
const HARD_MAX_ITERATIONS = 20;  // Non-overridable cap
const WALL_CLOCK_TIMEOUT_MS = 30 * 60 * 1000;  // 30 minutes
const MAX_STOP_ATTEMPTS = 3;
const STOP_ATTEMPT_WINDOW_MS = 60 * 1000;  // 1 minute

// Check hard limits before blocking
if (state.iteration >= HARD_MAX_ITERATIONS) {
  return { shouldBlock: false, reason: 'Hard iteration cap reached' };
}

const elapsed = Date.now() - state.startedAt;
if (elapsed > WALL_CLOCK_TIMEOUT_MS) {
  return { shouldBlock: false, reason: 'Wall-clock timeout reached' };
}

// Check for repeated stop attempts (user clearly wants to stop)
const recentStops = state.stopAttempts?.filter(
  t => Date.now() - t < STOP_ATTEMPT_WINDOW_MS
) ?? [];
if (recentStops.length >= MAX_STOP_ATTEMPTS) {
  return { shouldBlock: false, reason: 'User stop override (3 attempts in 60s)' };
}
```

**Configuration for guardrails** (`config.jsonc`):
```jsonc
{
  "guardrails": {
    "ralph": {
      "hardMaxIterations": 20,
      "wallClockTimeoutMinutes": 30,
      "maxStopAttempts": 3,
      "stopAttemptWindowSeconds": 60,
      "requireConfirmationOnFirstBlock": true
    },
    "autopilot": {
      "wallClockTimeoutMinutes": 60,
      "maxStopAttempts": 3
    },
    "ultrawork": {
      "wallClockTimeoutMinutes": 45,
      "maxStopAttempts": 3
    }
  }
}
```

### 4.2 Auto-Approval Scope Reduction

The permission handler at `src/hooks/permission-handler/index.ts` auto-approves commands matching a safe pattern list during autonomous modes.

**Current safe patterns and risk assessment:**

| Pattern | Risk | Recommendation |
|---------|------|----------------|
| `git status/diff/log/branch/show/fetch` | LOW | Keep — read-only git operations |
| `npm/pnpm/yarn test/lint/build/check` | LOW | Keep — standard dev commands |
| `tsc` | LOW | Keep — type checking |
| `eslint` | LOW | Keep — linting |
| `prettier` | LOW | Keep — formatting |
| `cargo test/check/clippy/build` | LOW | Keep — Rust dev commands |
| `pytest` / `python -m pytest` | LOW | Keep — test runners |
| `ls` | LOW | Keep — directory listing |
| Heredoc exceptions for `git commit/tag` | MEDIUM | **Remove** — commit operations should require confirmation |

**Recommended changes:**

1. **Remove heredoc exceptions entirely** — git commits during autonomous mode should require human confirmation.

2. **Add audit logging for every auto-approval:**
   ```typescript
   function logAutoApproval(command: string, mode: string): void {
     const entry = {
       timestamp: new Date().toISOString(),
       command,
       mode,
       approved: true,
       reason: 'safe_pattern_match'
     };
     appendFileSync('.omc/state/auto-approval-audit.jsonl',
       JSON.stringify(entry) + '\n', { mode: 0o600 });
   }
   ```

3. **Add deny-list for sensitive commands** that should never be auto-approved regardless of pattern matching:
   ```typescript
   const NEVER_AUTO_APPROVE = [
     /\brm\b/,
     /\bgit\s+(push|reset|rebase|merge|cherry-pick|revert)/,
     /\bnpm\s+(publish|unpublish)/,
     /\bcurl\b/,
     /\bwget\b/,
     /\bsudo\b/,
     /\bchmod\b/,
     /\bchown\b/,
     /\bdd\b/,
     /\bmkfs\b/,
   ];
   ```

### 4.3 Python REPL Sandboxing

The Python REPL at `bridge/gyoshu_bridge.py` runs arbitrary Python code with the user's full permissions via a Unix socket MCP server.

**Mitigation options (ranked by security):**

| Option | Security Level | Effort | Trade-off |
|--------|---------------|--------|-----------|
| **Disable entirely** | Highest | Trivial | Lose Python execution capability |
| **Sandbox with firejail** | High | Medium | Some packages may not work in sandbox |
| **Sandbox with nsjail** | High | Medium | Requires nsjail binary |
| **Read-only filesystem overlay** | Medium | Medium | Can run code but not write to filesystem |
| **Network isolation** | Medium | Low | Block network access from REPL |
| **Allowlist imports** | Low | High | Constant maintenance burden |

**Recommended: Disable by default, enable per-project with sandbox**

1. **Disable globally** in MCP config (`.mcp.json`):
   ```json
   {
     "mcpServers": {
       "gyoshu": {
         "enabled": false
       }
     }
   }
   ```

2. **When needed, enable with firejail sandboxing:**
   ```bash
   # Wrapper script: scripts/sandboxed-python-repl.sh
   #!/bin/bash
   firejail --noprofile \
     --net=none \
     --noroot \
     --private-tmp \
     --read-only=/home \
     --whitelist="$(pwd)" \
     python3 bridge/gyoshu_bridge.py "$@"
   ```

3. **Per-project enablement** (`.claude/omc.jsonc`):
   ```jsonc
   {
     "features": {
       "pythonReplEnabled": true,
       "pythonReplSandbox": "firejail"
     }
   }
   ```

### 4.4 Persistent State Validation

State files in `.omc/state/` auto-restore autonomous modes across sessions. A malicious `.omc/` directory in a cloned repo could auto-activate modes.

**Mitigations:**

| Mitigation | Implementation |
|------------|---------------|
| **Session ID validation** | Reject state files whose `session_id` doesn't match current session |
| **Timestamp expiry** | Reject state files older than 24 hours |
| **Origin verification** | Store machine hostname/user in state; reject foreign origins |
| **Repo hash binding** | Bind state to repo remote URL hash; reject if repo changes |
| **User confirmation** | Prompt before restoring any persisted autonomous mode |

**Fork changes to state loading:**

```typescript
function validateStateFile(filepath: string, currentSessionId: string): boolean {
  const state = JSON.parse(readFileSync(filepath, 'utf-8'));

  // Reject stale state (older than 24 hours)
  const age = Date.now() - new Date(state.updatedAt).getTime();
  if (age > 24 * 60 * 60 * 1000) {
    unlinkSync(filepath);
    return false;
  }

  // Reject foreign machine origin
  if (state.machineId && state.machineId !== getMachineId()) {
    unlinkSync(filepath);
    return false;
  }

  // Reject if repo remote URL hash doesn't match
  if (state.repoHash && state.repoHash !== getRepoRemoteHash()) {
    unlinkSync(filepath);
    return false;
  }

  return true;
}
```

---

## 5. Layer 4 — Environmental Controls

**Addresses:** Issue #5 (external channels), Issue #8 (persistent state), Issue #9 (learned skills injection)

### 5.1 Repository Hygiene — `.gitignore` Rules

Prevent `.omc/` directories from being committed to repos, which eliminates the repo-poisoning attack vector (Issue #8) and skill injection via commits (Issue #9).

**Add to `.gitignore`:**
```gitignore
# oh-my-claudecode state and skills — never commit these
.omc/state/
.omc/skills/
.omc/logs/
.omc/*.json
.omc/*.marker
.omc/*.pid
```

### 5.2 Git Pre-Commit Hook

Block any attempt to commit `.omc/` state or skill files:

**File: `.githooks/pre-commit`**
```bash
#!/bin/bash
# Prevent committing oh-my-claudecode state/skill files

FORBIDDEN_PATTERNS=(
  ".omc/state/"
  ".omc/skills/"
  ".omc/config"
  ".omc/.*\.marker"
)

STAGED_FILES=$(git diff --cached --name-only)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  MATCHES=$(echo "$STAGED_FILES" | grep -E "$pattern" || true)
  if [ -n "$MATCHES" ]; then
    echo "ERROR: Attempting to commit oh-my-claudecode runtime files:"
    echo "$MATCHES"
    echo ""
    echo "These files should never be committed. They may contain:"
    echo "  - Autonomous mode state (security risk: auto-activation)"
    echo "  - Learned skills (security risk: prompt injection)"
    echo "  - Configuration with credentials (security risk: secret leak)"
    echo ""
    echo "Remove them from staging with: git reset HEAD <file>"
    exit 1
  fi
done
```

**Enable the hook:**
```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

### 5.3 File Permission Enforcement

Sensitive OMC files should have restrictive permissions. Add a periodic check:

**Files requiring 0600 (owner read/write only):**

| File/Directory | Contains |
|----------------|----------|
| `~/.omc/config.json` | Notification credentials (Discord/Telegram tokens) |
| `.omc/state/*.json` | Session state, mode activation data |
| `.omc/skills/*.md` | Learned skills (prompt injection risk) |
| Reply listener state files | Bot tokens, session data |
| Reply listener log files | Message content, user interactions |

**Permission enforcement script (`scripts/enforce-permissions.sh`):**
```bash
#!/bin/bash
# Enforce restrictive permissions on OMC sensitive files

fix_perms() {
  local path="$1"
  if [ -e "$path" ]; then
    chmod 600 "$path"
    echo "Fixed: $path -> 600"
  fi
}

fix_dir_perms() {
  local dir="$1"
  if [ -d "$dir" ]; then
    chmod 700 "$dir"
    find "$dir" -type f -name '*.json' -o -name '*.md' -o -name '*.jsonl' | \
      xargs -r chmod 600
    echo "Fixed: $dir -> 700 (dir), 600 (files)"
  fi
}

# Global config
fix_perms "$HOME/.omc/config.json"
fix_dir_perms "$HOME/.omc/skills"

# Project-local state
fix_dir_perms ".omc/state"
fix_dir_perms ".omc/skills"
fix_dir_perms ".omc/logs"
```

### 5.4 Notification Channel Hardening

Since you're actively using Discord/Telegram/Slack notifications AND the bidirectional reply listener, these channels need additional hardening.

**Outbound notification security:**

| Control | Implementation |
|---------|---------------|
| **Credential rotation** | Rotate Discord/Telegram bot tokens every 90 days |
| **Minimal permissions** | Discord bot: only `Send Messages` permission, no `Read Message History` unless reply listener is used |
| **Dedicated channels** | Use dedicated notification channels, not shared team channels |
| **Content filtering** | Strip file paths, code snippets, and secrets from notification payloads before sending |
| **Rate limiting** | Enforce notification cooldown (already exists: `sessionIdleSeconds: 60`) |

**Bidirectional reply listener hardening:**

| Control | Implementation |
|---------|---------------|
| **User allowlist** | Strictly limit Discord user IDs / Telegram chat IDs that can inject replies |
| **Message signing** | Require a shared secret prefix on all injected messages (e.g., `!omc:secret:message`) |
| **Content validation** | Reject messages containing shell metacharacters or suspicious patterns |
| **Injection audit log** | Log every injected reply with timestamp, source, content, and target session |
| **Max message length** | Cap injected messages at 500 characters to prevent prompt stuffing |
| **Cooldown per user** | Max 1 injected reply per 30 seconds per user to prevent spam |
| **Pane verification** | Already exists — verify tmux pane content before injection |

**Recommended `config.json` additions for notification hardening:**
```json
{
  "notifications": {
    "contentFilter": {
      "stripFilePaths": true,
      "stripCodeBlocks": true,
      "maxPayloadLength": 1000
    },
    "replyListener": {
      "enabled": true,
      "requireMessagePrefix": "!omc:",
      "maxMessageLength": 500,
      "cooldownPerUserSeconds": 30,
      "allowedDiscordUserIds": ["YOUR_DISCORD_USER_ID"],
      "allowedTelegramChatIds": ["YOUR_TELEGRAM_CHAT_ID"],
      "auditLog": true,
      "rejectShellMetachars": true
    }
  }
}
```

### 5.5 Learned Skills Protection

If you choose to keep learned skills enabled, add integrity controls:

| Control | Implementation |
|---------|---------------|
| **Read-only after creation** | Set skill files to 0400 (read-only) after writing |
| **Content hash manifest** | Maintain `skills-manifest.json` with sha256 of each skill file |
| **Periodic integrity check** | Compare skill files against manifest; alert on mismatch |
| **Content scanning** | Reject skills containing suspicious patterns (shell commands, URLs, `eval`, `subprocess`) |
| **Manual promotion only** | Disable auto-promotion from learned to project-level skills |

**Skill integrity manifest (`scripts/skill-integrity.sh`):**
```bash
#!/bin/bash
# Generate or verify skill file integrity manifest

SKILLS_DIR="${1:-$HOME/.omc/skills/omc-learned}"
MANIFEST="$SKILLS_DIR/.manifest.json"

generate() {
  echo "{" > "$MANIFEST"
  first=true
  for f in "$SKILLS_DIR"/*.md; do
    [ -f "$f" ] || continue
    hash=$(sha256sum "$f" | cut -d' ' -f1)
    name=$(basename "$f")
    if [ "$first" = true ]; then first=false; else echo "," >> "$MANIFEST"; fi
    printf '  "%s": "%s"' "$name" "$hash" >> "$MANIFEST"
  done
  echo "" >> "$MANIFEST"
  echo "}" >> "$MANIFEST"
  chmod 600 "$MANIFEST"
  echo "Manifest generated: $MANIFEST"
}

verify() {
  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: No manifest found. Run with 'generate' first."
    exit 1
  fi

  violations=0
  for f in "$SKILLS_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    expected=$(python3 -c "import json; m=json.load(open('$MANIFEST')); print(m.get('$name','MISSING'))")
    actual=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$expected" = "MISSING" ]; then
      echo "NEW (untracked): $name"
      violations=$((violations + 1))
    elif [ "$expected" != "$actual" ]; then
      echo "MODIFIED: $name (expected: ${expected:0:16}... actual: ${actual:0:16}...)"
      violations=$((violations + 1))
    fi
  done

  if [ $violations -gt 0 ]; then
    echo "ALERT: $violations skill file(s) have integrity violations!"
    exit 1
  else
    echo "All skill files match manifest."
  fi
}

case "${2:-verify}" in
  generate) generate ;;
  verify) verify ;;
  *) echo "Usage: $0 <skills-dir> [generate|verify]" ;;
esac
```

---

## 6. Layer 5 — Monitoring & Alerting

**Cross-cutting observability to detect and respond to security events.**

### 6.1 Audit Log

Create a centralized audit log for all security-relevant events:

**Events to log:**

| Event Category | Specific Events | Log Level |
|----------------|-----------------|-----------|
| **Mode activation** | ralph/autopilot/ultrawork/team start and stop | WARN |
| **Stop blocking** | Every time persistent-mode blocks a stop attempt | ERROR |
| **Auto-approval** | Every command auto-approved by permission handler | INFO |
| **Keyword detection** | Every keyword match, including false positives | INFO |
| **External notification** | Every outbound notification sent | INFO |
| **Reply injection** | Every message injected from external channel | WARN |
| **Skill injection** | Every learned skill injected into context | INFO |
| **State file operations** | Create/read/delete of `.omc/state/` files | INFO |
| **CLAUDE.md modification** | Any change to `~/.claude/CLAUDE.md` | ERROR |
| **Permission denial** | Commands rejected by permission handler | WARN |

**Log format (`.omc/logs/security-audit.jsonl`):**
```json
{
  "timestamp": "2026-02-23T14:30:00.000Z",
  "sessionId": "abc123",
  "event": "stop_blocked",
  "category": "mode_activation",
  "level": "ERROR",
  "details": {
    "mode": "ralph",
    "iteration": 5,
    "maxIterations": 20,
    "elapsedMinutes": 12
  }
}
```

**Log rotation:** Already implemented at 1MB max. Ensure retention of at least 7 days of logs for forensic review.

### 6.2 Anomaly Detection Rules

Define rules that trigger alerts when unusual patterns are detected:

| Rule | Condition | Alert Action |
|------|-----------|--------------|
| **Runaway mode** | Any mode active > 30 minutes | Desktop notification + Discord alert |
| **Rapid stop attempts** | 3+ stop blocks in 60 seconds | Force-allow stop, log as incident |
| **Unexpected mode activation** | Mode activated without explicit `/` command | Log as WARNING, review keyword match |
| **Foreign state file** | State file with mismatched session/machine ID | Delete file, log as ERROR |
| **Skill file tampering** | Manifest verification failure | Quarantine modified skill, log as ERROR |
| **High auto-approval rate** | 10+ auto-approvals in 5 minutes | Temporarily disable auto-approval |
| **Reply injection burst** | 5+ reply injections in 2 minutes | Pause reply listener for 5 minutes |
| **Large notification payload** | Outbound notification > 2KB | Strip content, log original |

### 6.3 Session Recording

For forensic review capability, enable session-level recording:

```jsonc
{
  "monitoring": {
    "auditLog": {
      "enabled": true,
      "path": ".omc/logs/security-audit.jsonl",
      "retentionDays": 7,
      "maxSizeMB": 10
    },
    "sessionRecording": {
      "enabled": true,
      "path": ".omc/logs/sessions/",
      "includeToolResults": false,
      "retentionDays": 3
    }
  }
}
```

### 6.4 Periodic Security Scan

A script to run periodically (cron or CI) that checks the health of all OMC security controls:

**File: `scripts/security-scan.sh`**
```bash
#!/bin/bash
# Periodic security health check for oh-my-claudecode

ISSUES=0
WARNINGS=0

check() {
  local severity="$1" desc="$2" condition="$3"
  if eval "$condition"; then
    echo "[$severity] $desc"
    if [ "$severity" = "FAIL" ]; then ISSUES=$((ISSUES + 1)); fi
    if [ "$severity" = "WARN" ]; then WARNINGS=$((WARNINGS + 1)); fi
  else
    echo "[PASS] $desc"
  fi
}

echo "=== oh-my-claudecode Security Scan ==="
echo "Date: $(date -Iseconds)"
echo ""

# Check for active autonomous modes
check "WARN" "Active autonomous mode state files" \
  "ls .omc/state/*-state.json 2>/dev/null | grep -q ."

# Check .gitignore includes .omc/
check "FAIL" ".omc/state/ not in .gitignore" \
  "! grep -q '.omc/state/' .gitignore 2>/dev/null"

# Check file permissions on config
check "FAIL" "~/.omc/config.json has loose permissions" \
  "[ -f ~/.omc/config.json ] && [ $(stat -c %a ~/.omc/config.json) != '600' ]"

# Check for .omc/ in staged git files
check "FAIL" ".omc/ files staged in git" \
  "git diff --cached --name-only 2>/dev/null | grep -q '.omc/'"

# Check CLAUDE.md hasn't been modified unexpectedly
check "WARN" "~/.claude/CLAUDE.md modified since last check" \
  "[ -f ~/.claude/.claude-md-hash ] && \
   [ $(sha256sum ~/.claude/CLAUDE.md 2>/dev/null | cut -d' ' -f1) != $(cat ~/.claude/.claude-md-hash 2>/dev/null) ]"

# Check bundle integrity (if checksums exist)
check "WARN" "Bridge bundle checksums not verified" \
  "[ ! -f bridge/checksums-verified.sha256 ]"

# Check pre-commit hook is installed
check "FAIL" "Pre-commit hook not installed" \
  "[ ! -x .githooks/pre-commit ] && [ ! -x .git/hooks/pre-commit ]"

# Check for learned skills with suspicious content
check "WARN" "Learned skills contain suspicious patterns" \
  "grep -rl 'subprocess\|curl\|wget' ~/.omc/skills/ 2>/dev/null | grep -q ."

echo ""
echo "=== Results: $ISSUES failures, $WARNINGS warnings ==="
[ $ISSUES -gt 0 ] && exit 1
exit 0
```

---

## 7. Implementation Roadmap

Phased rollout prioritized by risk reduction per unit of effort.

### Phase 1: Immediate (Day 1)

These mitigations can be applied in under an hour and address the highest-risk issues.

| Action | Addresses | Effort | Command/File |
|--------|-----------|--------|--------------|
| Add `.omc/` to `.gitignore` | #8, #9 | 5 min | Edit `.gitignore` |
| Install pre-commit hook | #8, #9 | 10 min | Create `.githooks/pre-commit` |
| Set `OMC_SKIP_CLAUDE_MD=1` | #3 | 2 min | Add to shell profile |
| Run `chmod 600` on sensitive files | #5, #9 | 5 min | Run `scripts/enforce-permissions.sh` |
| Verify bundle checksums | #6 | 30 min | Run rebuild + diff procedure from Section 2.1 |
| Set `DISABLE_OMC=1` in sensitive repos | All | 2 min | Per-project `.envrc` or shell alias |

### Phase 2: Short-term (Week 1)

Configuration and code changes to your fork.

| Action | Addresses | Effort | Details |
|--------|-----------|--------|---------|
| Fork keyword detector to require `/` prefix | #10 | 1-2 hrs | Modify `src/hooks/keyword-detector/index.ts` |
| Add hard iteration caps to persistent-mode | #2 | 2-3 hrs | Modify `src/hooks/persistent-mode/index.ts` |
| Remove heredoc auto-approval exception | #4 | 30 min | Modify `src/hooks/permission-handler/index.ts` |
| Add auto-approval audit logging | #4 | 1 hr | Add logging to permission handler |
| Add deny-list for dangerous commands | #4 | 1 hr | Add `NEVER_AUTO_APPROVE` patterns |
| Create hardened `config.jsonc` template | #1, #10 | 1 hr | Create `config/hardened.jsonc` |
| Add CI bundle verification workflow | #6 | 1 hr | Create `.github/workflows/verify-bundles.yml` |
| Disable Python REPL by default | #7 | 15 min | Modify `.mcp.json` |
| Add state file validation | #8 | 2 hrs | Modify state loading code |

### Phase 3: Ongoing (Monthly)

| Action | Addresses | Frequency | Details |
|--------|-----------|-----------|---------|
| Run security scan script | All | Weekly | `scripts/security-scan.sh` |
| Verify skill file integrity | #9 | Weekly | `scripts/skill-integrity.sh` |
| Rotate notification credentials | #5 | Every 90 days | Discord/Telegram bot tokens |
| Review audit logs | All | Weekly | Check `.omc/logs/security-audit.jsonl` |
| Sync fork with upstream | All | Monthly | `git fetch upstream && git diff upstream/main` — review changes |
| Run `npm audit` | #11 | Monthly | `npm audit --production` |
| Re-verify bundle checksums after updates | #6 | On every upstream merge | Rebuild and compare |

---

## 8. Proposed Code & Configuration Changes

Concrete changes to implement in your fork. Each change is self-contained and can be applied independently.

### 8.1 Hardened Configuration Template

**File: `config/hardened.jsonc`**
```jsonc
{
  // oh-my-claudecode hardened configuration for professional codebases
  // Copy to: ~/.config/claude-omc/config.jsonc

  "features": {
    "parallelExecution": true,
    "lspTools": true,
    "astTools": true,
    "continuationEnforcement": true,
    "autoContextInjection": true,
    "learnedSkillsEnabled": false,
    "pythonReplEnabled": false
  },

  "permissions": {
    "allowBash": true,
    "allowEdit": true,
    "allowWrite": true,
    "maxBackgroundTasks": 3
  },

  "guardrails": {
    "ralph": {
      "hardMaxIterations": 20,
      "wallClockTimeoutMinutes": 30,
      "maxStopAttempts": 3,
      "stopAttemptWindowSeconds": 60,
      "requireConfirmationOnFirstBlock": true
    },
    "autopilot": {
      "wallClockTimeoutMinutes": 60,
      "maxStopAttempts": 3
    },
    "ultrawork": {
      "wallClockTimeoutMinutes": 45,
      "maxStopAttempts": 3
    }
  },

  "keywordDetection": {
    "requireSlashPrefix": true
  },

  "notifications": {
    "contentFilter": {
      "stripFilePaths": true,
      "stripCodeBlocks": true,
      "maxPayloadLength": 1000
    },
    "replyListener": {
      "enabled": true,
      "requireMessagePrefix": "!omc:",
      "maxMessageLength": 500,
      "cooldownPerUserSeconds": 30,
      "auditLog": true,
      "rejectShellMetachars": true
    }
  },

  "monitoring": {
    "auditLog": {
      "enabled": true,
      "retentionDays": 7,
      "maxSizeMB": 10
    }
  }
}
```

### 8.2 `.gitignore` Additions

```gitignore
# oh-my-claudecode runtime files — never commit
.omc/state/
.omc/skills/
.omc/logs/
.omc/config.json
.omc/*.marker
.omc/*.pid
```

### 8.3 Pre-Commit Hook

See Section 5.2 for the full script. Install with:
```bash
mkdir -p .githooks
# <create .githooks/pre-commit with content from Section 5.2>
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

### 8.4 CI Bundle Verification

See Section 2.2 for the full GitHub Actions workflow. Save to `.github/workflows/verify-bundles.yml`.

### 8.5 `.npmrc` for Supply Chain Safety

```ini
save-exact=true
package-lock=true
engine-strict=true
```

### 8.6 Emergency Kill Switch

For immediate halt of all OMC autonomous behavior:

```bash
# Option 1: Environment variable (current session)
export DISABLE_OMC=1

# Option 2: File-based kill switch (all sessions in this project)
touch .omc/KILLSWITCH

# Option 3: Cancel command (within Claude session)
# Type: /oh-my-claudecode:cancel

# Option 4: Nuclear option — remove all OMC hooks temporarily
mv ~/.claude/settings.json ~/.claude/settings.json.bak
```

### 8.7 Summary of All Proposed File Changes

| File | Action | Purpose |
|------|--------|---------|
| `.gitignore` | Edit | Add `.omc/` exclusion rules |
| `.githooks/pre-commit` | Create | Block `.omc/` files from being committed |
| `.github/workflows/verify-bundles.yml` | Create | CI bundle verification |
| `.npmrc` | Create | npm supply chain safety |
| `config/hardened.jsonc` | Create | Hardened configuration template |
| `scripts/enforce-permissions.sh` | Create | File permission enforcement |
| `scripts/security-scan.sh` | Create | Periodic security health check |
| `scripts/skill-integrity.sh` | Create | Learned skills integrity verification |
| `scripts/watch-claude-md.sh` | Create | CLAUDE.md change detection |
| `scripts/sandboxed-python-repl.sh` | Create | Firejail wrapper for Python REPL |
| `src/hooks/keyword-detector/index.ts` | Modify | Require `/` prefix for keywords |
| `src/hooks/persistent-mode/index.ts` | Modify | Add hard caps, timeouts, grace periods |
| `src/hooks/permission-handler/index.ts` | Modify | Remove heredoc exception, add deny-list, add audit log |
| `.mcp.json` | Modify | Disable Python REPL by default |

---

## Appendix A: Quick Reference — Emergency Procedures

| Scenario | Action |
|----------|--------|
| Claude won't stop (stop-blocking) | Press Ctrl+C 3 times rapidly, or `export DISABLE_OMC=1` in another terminal |
| Unexpected autonomous mode activated | Type `cancelomc` or `stopomc` in the Claude session |
| Suspicious command auto-approved | Check `.omc/logs/security-audit.jsonl` for details |
| CLAUDE.md was overwritten | Restore from backup: `cp ~/.claude/CLAUDE.md.bak.* ~/.claude/CLAUDE.md` |
| Reply injection from unknown source | Check reply listener logs, verify user allowlist, rotate bot tokens |
| Skill file tampered with | Run `scripts/skill-integrity.sh verify`, quarantine modified files |
| All else fails | `export DISABLE_OMC=1 && mv ~/.claude/settings.json ~/.claude/settings.json.bak` |

## Appendix B: Residual Risks & Accepted Trade-offs

Even with all mitigations applied, these residual risks remain:

| Residual Risk | Why It Remains | Acceptance Rationale |
|---------------|---------------|---------------------|
| Hook interception still active | Disabling hooks entirely defeats the plugin's purpose | Mitigated by audit logging and scoped controls |
| Reply injection fundamentally trusts external services | Bidirectional communication requires some trust | Mitigated by allowlists, signing, rate limiting |
| Auto-approval still exists for safe patterns | Completely disabling would break autonomous workflow | Patterns are genuinely read-only; deny-list catches dangerous commands |
| Plugin authors have code execution via hooks | This is inherent to any Claude Code plugin | Mitigated by supply chain verification and bundle auditing |
| Context injection modifies Claude behavior | Core plugin functionality | Mitigated by CLAUDE.md protection and keyword prefix requirements |
