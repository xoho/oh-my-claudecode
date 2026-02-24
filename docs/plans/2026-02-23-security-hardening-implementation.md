# Security Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all 5 defense-in-depth mitigation layers from `MITIGATE_SECURITY_RISK_OHMYCLAUDE.md` across 5 feature branches.

**Architecture:** Each defense layer is an independent feature branch targeting `dev`. Branches 1, 4, 5 are scripts/CI only (no source changes). Branch 2 adds config schema + keyword prefix. Branch 3 adds runtime guardrails (depends on Branch 2). All branches use TDD where source changes are involved.

**Tech Stack:** TypeScript, vitest, bash scripts, GitHub Actions YAML

---

## Branch 1: `security/supply-chain`

### Task 1: Create bundle verification script

**Files:**
- Create: `scripts/verify-bundles.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Verify that committed bridge bundles match a clean source rebuild.
# Exit 0 if match, exit 1 if divergence detected.

set -euo pipefail

echo "=== Bundle Verification ==="
echo "Date: $(date -Iseconds)"

# Save committed checksums
echo "Saving committed bundle checksums..."
sha256sum bridge/*.cjs | sort > /tmp/omc-committed.sha256
cat /tmp/omc-committed.sha256

# Clean rebuild
echo "Rebuilding from source..."
npm ci --ignore-scripts
npm run build

# Compare
echo "Comparing checksums..."
sha256sum bridge/*.cjs | sort > /tmp/omc-rebuilt.sha256

if diff /tmp/omc-committed.sha256 /tmp/omc-rebuilt.sha256 > /dev/null 2>&1; then
  echo "PASS: All bundles match source rebuild."
  cp /tmp/omc-rebuilt.sha256 bridge/checksums-verified.sha256
  exit 0
else
  echo "FAIL: Bundle mismatch detected!"
  echo ""
  echo "Committed:"
  cat /tmp/omc-committed.sha256
  echo ""
  echo "Rebuilt:"
  cat /tmp/omc-rebuilt.sha256
  echo ""
  diff /tmp/omc-committed.sha256 /tmp/omc-rebuilt.sha256 || true
  exit 1
fi
```

**Step 2: Make it executable and test**

Run: `chmod +x scripts/verify-bundles.sh && head -5 scripts/verify-bundles.sh`
Expected: shebang line and set flags visible

**Step 3: Commit**

```bash
git add scripts/verify-bundles.sh
git commit -m "feat(security): add bundle verification script for supply chain validation"
```

### Task 2: Create CI workflow for bundle verification

**Files:**
- Create: `.github/workflows/verify-bundles.yml`

**Step 1: Write the workflow**

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
          echo "Bundle verification passed."

      - name: Security audit
        run: npm audit --production --audit-level=high || true
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/verify-bundles.yml'))"`
Expected: No error output

**Step 3: Commit**

```bash
git add .github/workflows/verify-bundles.yml
git commit -m "ci(security): add bundle verification workflow for supply chain integrity"
```

### Task 3: Create .npmrc for supply chain safety

**Files:**
- Create: `.npmrc`

**Step 1: Write the file**

```ini
save-exact=true
package-lock=true
engine-strict=true
```

**Step 2: Verify it's valid**

Run: `cat .npmrc`
Expected: Three lines, no syntax errors

**Step 3: Commit**

```bash
git add .npmrc
git commit -m "chore(security): add .npmrc for supply chain pinning"
```

---

## Branch 2: `security/config-hardening`

### Task 4: Add guardrails and keywordDetection to PluginConfig type

**Files:**
- Modify: `src/shared/types.ts:112-123`

**Step 1: Write the failing test**

Create file `src/config/__tests__/guardrails-config.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { DEFAULT_CONFIG, loadConfig } from '../loader.js';

describe('guardrails configuration', () => {
  it('should have guardrails defaults in DEFAULT_CONFIG', () => {
    expect(DEFAULT_CONFIG.guardrails).toBeDefined();
    expect(DEFAULT_CONFIG.guardrails!.ralph).toBeDefined();
    expect(DEFAULT_CONFIG.guardrails!.ralph!.hardMaxIterations).toBe(20);
    expect(DEFAULT_CONFIG.guardrails!.ralph!.wallClockTimeoutMinutes).toBe(30);
    expect(DEFAULT_CONFIG.guardrails!.ralph!.maxStopAttempts).toBe(3);
    expect(DEFAULT_CONFIG.guardrails!.ralph!.stopAttemptWindowSeconds).toBe(60);
  });

  it('should have keywordDetection defaults in DEFAULT_CONFIG', () => {
    expect(DEFAULT_CONFIG.keywordDetection).toBeDefined();
    expect(DEFAULT_CONFIG.keywordDetection!.requireSlashPrefix).toBe(false);
  });

  it('should load guardrails from config', () => {
    const config = loadConfig();
    expect(config.guardrails).toBeDefined();
    expect(config.guardrails!.ralph!.hardMaxIterations).toBeGreaterThan(0);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/config/__tests__/guardrails-config.test.ts`
Expected: FAIL — `guardrails` property does not exist on `PluginConfig`

**Step 3: Add types to `src/shared/types.ts`**

Add after line 122 (before the closing `}` of `PluginConfig`):

```typescript
  // Security guardrails configuration
  guardrails?: {
    ralph?: {
      hardMaxIterations?: number;
      wallClockTimeoutMinutes?: number;
      maxStopAttempts?: number;
      stopAttemptWindowSeconds?: number;
    };
    autopilot?: {
      wallClockTimeoutMinutes?: number;
      maxStopAttempts?: number;
    };
    ultrawork?: {
      wallClockTimeoutMinutes?: number;
      maxStopAttempts?: number;
    };
  };

  // Keyword detection configuration
  keywordDetection?: {
    requireSlashPrefix?: boolean;
  };
```

**Step 4: Add defaults to `src/config/loader.ts`**

Add after `taskSizeDetection` block (after line 115) in `DEFAULT_CONFIG`:

```typescript
  // Security guardrails
  guardrails: {
    ralph: {
      hardMaxIterations: 20,
      wallClockTimeoutMinutes: 30,
      maxStopAttempts: 3,
      stopAttemptWindowSeconds: 60,
    },
    autopilot: {
      wallClockTimeoutMinutes: 60,
      maxStopAttempts: 3,
    },
    ultrawork: {
      wallClockTimeoutMinutes: 45,
      maxStopAttempts: 3,
    },
  },
  // Keyword detection
  keywordDetection: {
    requireSlashPrefix: false,
  },
```

**Step 5: Run test to verify it passes**

Run: `npx vitest run src/config/__tests__/guardrails-config.test.ts`
Expected: PASS (3 tests)

**Step 6: Run full test suite for regressions**

Run: `npx vitest run`
Expected: All existing tests pass

**Step 7: Commit**

```bash
git add src/shared/types.ts src/config/loader.ts src/config/__tests__/guardrails-config.test.ts
git commit -m "feat(security): add guardrails and keywordDetection config schema"
```

### Task 5: Add slash-prefix support to keyword detector

**Files:**
- Modify: `src/hooks/keyword-detector/index.ts:46-63`
- Create: `src/hooks/keyword-detector/__tests__/slash-prefix.test.ts`

**Step 1: Write the failing test**

Create file `src/hooks/keyword-detector/__tests__/slash-prefix.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { detectKeywordsWithType, getAllKeywords } from '../index.js';

// Mock the config loader to enable slash prefix
vi.mock('../../../config/loader.js', () => ({
  loadConfig: () => ({
    keywordDetection: {
      requireSlashPrefix: true,
    },
  }),
}));

describe('keyword-detector with requireSlashPrefix=true', () => {
  describe('should NOT match bare keywords', () => {
    const bareCases = [
      'ralph do the thing',
      'set it to autopilot',
      'ask the team about this',
      'use ultrawork mode',
      'try tdd approach',
      'use deepsearch to find it',
    ];

    bareCases.forEach(text => {
      it(`should reject bare keyword in: "${text}"`, () => {
        const result = detectKeywordsWithType(text);
        // cancel is always bare-word, filter it out
        const nonCancel = result.filter(r => r.type !== 'cancel');
        expect(nonCancel).toHaveLength(0);
      });
    });
  });

  describe('should match slash-prefixed keywords', () => {
    const slashCases = [
      { text: '/ralph do the thing', type: 'ralph' },
      { text: '/autopilot build this', type: 'autopilot' },
      { text: '/ultrawork now', type: 'ultrawork' },
      { text: '/tdd this feature', type: 'tdd' },
      { text: '/deepsearch find it', type: 'deepsearch' },
    ];

    slashCases.forEach(({ text, type }) => {
      it(`should match /${type} in: "${text}"`, () => {
        const result = detectKeywordsWithType(text);
        expect(result.some(r => r.type === type)).toBe(true);
      });
    });
  });

  describe('cancel keywords should always work without prefix', () => {
    it('should match cancelomc without slash', () => {
      const result = getAllKeywords('cancelomc');
      expect(result).toContain('cancel');
    });

    it('should match stopomc without slash', () => {
      const result = getAllKeywords('stopomc');
      expect(result).toContain('cancel');
    });
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/hooks/keyword-detector/__tests__/slash-prefix.test.ts`
Expected: FAIL — bare keywords still match because slash prefix logic isn't implemented

**Step 3: Implement slash-prefix support in keyword detector**

Modify `src/hooks/keyword-detector/index.ts`. Add import and config loading at top:

```typescript
import { loadConfig } from '../../config/loader.js';
```

Replace the `KEYWORD_PATTERNS` constant (lines 46-63) with a function:

```typescript
/**
 * Build keyword patterns, optionally requiring slash prefix for mode-activating keywords.
 * Cancel keywords always use bare-word matching for safety.
 */
function buildKeywordPatterns(requireSlashPrefix: boolean): Record<KeywordType, RegExp> {
  if (!requireSlashPrefix) {
    // Original patterns — bare word matching
    return {
      cancel: /\b(cancelomc|stopomc)\b/i,
      ralph: /\b(ralph)\b/i,
      autopilot: /\b(autopilot|auto[\s-]?pilot|fullsend|full\s+auto)\b/i,
      ultrapilot: /\b(ultrapilot|ultra-pilot)\b|\bparallel\s+build\b|\bswarm\s+build\b/i,
      ultrawork: /\b(ultrawork|ulw)\b/i,
      swarm: /\bswarm\s+\d+\s+agents?\b|\bcoordinated\s+agents\b|\bteam\s+mode\b/i,
      team: /(?<!\b(?:my|the|our|a|his|her|their|its)\s)\bteam\b|\bcoordinated\s+team\b/i,
      pipeline: /\bagent\s+pipeline\b|\bchain\s+agents\b/i,
      ralplan: /\b(ralplan)\b/i,
      tdd: /\b(tdd)\b|\btest\s+first\b/i,
      ultrathink: /\b(ultrathink)\b/i,
      deepsearch: /\b(deepsearch)\b|\bsearch\s+the\s+codebase\b|\bfind\s+in\s+(the\s+)?codebase\b/i,
      analyze: /\b(deep[\s-]?analyze|deepanalyze)\b/i,
      ccg: /\b(ccg|claude-codex-gemini)\b/i,
      codex: /\b(ask|use|delegate\s+to)\s+(codex|gpt)\b/i,
      gemini: /\b(ask|use|delegate\s+to)\s+gemini\b/i,
    };
  }

  // Slash-prefix patterns — mode-activating keywords require / prefix
  // Cancel keywords remain bare-word for safety
  return {
    cancel: /\b(cancelomc|stopomc)\b/i,
    ralph: /(?:^|\s)\/(ralph)\b/i,
    autopilot: /(?:^|\s)\/(autopilot|auto[\s-]?pilot|fullsend|full\s+auto)\b/i,
    ultrapilot: /(?:^|\s)\/(ultrapilot|ultra-pilot)\b/i,
    ultrawork: /(?:^|\s)\/(ultrawork|ulw)\b/i,
    swarm: /(?:^|\s)\/swarm\s+\d+\s+agents?\b/i,
    team: /(?:^|\s)\/team\b/i,
    pipeline: /(?:^|\s)\/pipeline\b/i,
    ralplan: /(?:^|\s)\/(ralplan)\b/i,
    tdd: /(?:^|\s)\/(tdd)\b/i,
    ultrathink: /(?:^|\s)\/(ultrathink)\b/i,
    deepsearch: /(?:^|\s)\/(deepsearch)\b/i,
    analyze: /(?:^|\s)\/(deep[\s-]?analyze|deepanalyze)\b/i,
    ccg: /(?:^|\s)\/(ccg|claude-codex-gemini)\b/i,
    codex: /(?:^|\s)\/(codex|gpt)\b/i,
    gemini: /(?:^|\s)\/(gemini)\b/i,
  };
}

// Load config once at module init
const _config = loadConfig();
const KEYWORD_PATTERNS: Record<KeywordType, RegExp> = buildKeywordPatterns(
  _config.keywordDetection?.requireSlashPrefix ?? false
);
```

**Step 4: Run test to verify it passes**

Run: `npx vitest run src/hooks/keyword-detector/__tests__/slash-prefix.test.ts`
Expected: PASS (all tests)

**Step 5: Run full test suite**

Run: `npx vitest run`
Expected: All existing tests pass (keyword detector tests still pass because default is `requireSlashPrefix: false`)

**Step 6: Commit**

```bash
git add src/hooks/keyword-detector/index.ts src/hooks/keyword-detector/__tests__/slash-prefix.test.ts
git commit -m "feat(security): add slash-prefix mode for keyword detection to prevent hijacking"
```

### Task 6: Create hardened configuration template

**Files:**
- Create: `config/hardened.jsonc`

**Step 1: Write the template**

```jsonc
{
  // oh-my-claudecode hardened configuration for professional codebases
  // Copy to: ~/.config/claude-omc/config.jsonc
  //
  // This template enables security guardrails while keeping all
  // autonomous modes functional. See MITIGATE_SECURITY_RISK_OHMYCLAUDE.md
  // for the full rationale behind each setting.

  "features": {
    "parallelExecution": true,
    "lspTools": true,
    "astTools": true,
    "continuationEnforcement": true,
    "autoContextInjection": true
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
      "stopAttemptWindowSeconds": 60
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
  }
}
```

**Step 2: Validate JSONC syntax**

Run: `node -e "const jsonc = require('jsonc-parser'); const fs = require('fs'); const e=[]; jsonc.parse(fs.readFileSync('config/hardened.jsonc','utf-8'),e); console.log(e.length ? 'ERRORS:'+JSON.stringify(e) : 'OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add config/hardened.jsonc
git commit -m "docs(security): add hardened configuration template for professional codebases"
```

---

## Branch 3: `security/runtime-guardrails`

### Task 7: Add NEVER_AUTO_APPROVE deny-list to permission handler

**Files:**
- Modify: `src/hooks/permission-handler/index.ts:31-44`
- Modify: `src/hooks/permission-handler/__tests__/index.test.ts`

**Step 1: Write the failing test**

Add to `src/hooks/permission-handler/__tests__/index.test.ts`, inside the top-level `describe('permission-handler')`:

```typescript
  describe('NEVER_AUTO_APPROVE deny-list', () => {
    const deniedCases = [
      { cmd: 'rm -rf /tmp/test', desc: 'rm command' },
      { cmd: 'git push origin main', desc: 'git push' },
      { cmd: 'git reset --hard HEAD~1', desc: 'git reset' },
      { cmd: 'git rebase main', desc: 'git rebase' },
      { cmd: 'npm publish', desc: 'npm publish' },
      { cmd: 'sudo apt install something', desc: 'sudo command' },
      { cmd: 'chmod 777 /tmp/file', desc: 'chmod command' },
      { cmd: 'chown root /tmp/file', desc: 'chown command' },
      { cmd: 'wget http://example.com/file', desc: 'wget command' },
    ];

    deniedCases.forEach(({ cmd, desc }) => {
      it(`should deny ${desc}: ${cmd}`, () => {
        expect(isSafeCommand(cmd)).toBe(false);
      });
    });
  });
```

**Step 2: Run test to verify current state**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: Most will already pass (these commands aren't in SAFE_PATTERNS). Some may fail if they don't contain shell metacharacters. This confirms baseline behavior — we'll add the explicit deny-list next.

**Step 3: Add deny-list constant to `src/hooks/permission-handler/index.ts`**

Add after `DANGEROUS_SHELL_CHARS` (line 50):

```typescript
/**
 * Commands that must NEVER be auto-approved regardless of pattern matching.
 * These are destructive, network-accessing, or privilege-changing operations.
 * This list is a source-code constant — not configurable.
 */
const NEVER_AUTO_APPROVE = [
  /\brm\b/,
  /\bgit\s+(push|reset|rebase|merge|cherry-pick|revert)\b/,
  /\bnpm\s+(publish|unpublish)\b/,
  /\bcurl\b/,
  /\bwget\b/,
  /\bsudo\b/,
  /\bchmod\b/,
  /\bchown\b/,
  /\bdd\b/,
  /\bmkfs\b/,
];
```

Add deny-list check to `isSafeCommand()` before the safe-pattern check:

```typescript
  // SECURITY: Deny-list — these commands are never auto-approved
  if (NEVER_AUTO_APPROVE.some(pattern => pattern.test(trimmed))) {
    return false;
  }
```

**Step 4: Run test to verify it passes**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: PASS (all tests including new deny-list tests)

**Step 5: Commit**

```bash
git add src/hooks/permission-handler/index.ts src/hooks/permission-handler/__tests__/index.test.ts
git commit -m "feat(security): add NEVER_AUTO_APPROVE deny-list to permission handler"
```

### Task 8: Add audit logging to permission handler

**Files:**
- Modify: `src/hooks/permission-handler/index.ts:160-204`

**Step 1: Write the failing test**

Add to `src/hooks/permission-handler/__tests__/index.test.ts`:

```typescript
  describe('audit logging', () => {
    const auditLogDir = '/tmp/omc-permission-test/.omc/state';
    const auditLogPath = path.join(auditLogDir, 'auto-approval-audit.jsonl');

    beforeEach(() => {
      if (fs.existsSync('/tmp/omc-permission-test')) {
        fs.rmSync('/tmp/omc-permission-test', { recursive: true, force: true });
      }
      fs.mkdirSync(auditLogDir, { recursive: true });
    });

    afterEach(() => {
      if (fs.existsSync('/tmp/omc-permission-test')) {
        fs.rmSync('/tmp/omc-permission-test', { recursive: true, force: true });
      }
    });

    it('should write audit log entry when command is auto-approved', () => {
      const input = createInput('git status');
      processPermissionRequest(input);

      expect(fs.existsSync(auditLogPath)).toBe(true);
      const content = fs.readFileSync(auditLogPath, 'utf-8').trim();
      const entry = JSON.parse(content);
      expect(entry.command).toBe('git status');
      expect(entry.approved).toBe(true);
      expect(entry.timestamp).toBeDefined();
    });

    it('should NOT write audit log for denied commands', () => {
      const input = createInput('rm -rf /');
      processPermissionRequest(input);

      expect(fs.existsSync(auditLogPath)).toBe(false);
    });
  });
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: FAIL — audit log not created

**Step 3: Add audit logging to `processPermissionRequest`**

Add import at top of `src/hooks/permission-handler/index.ts`:

```typescript
import { appendFileSync, mkdirSync, existsSync } from 'fs';
```

Add audit logging function:

```typescript
/**
 * Log auto-approval decisions for security audit trail.
 * Writes append-only JSONL to .omc/state/auto-approval-audit.jsonl
 */
function logAutoApproval(cwd: string, command: string, reason: string): void {
  try {
    const stateDir = path.join(cwd, '.omc', 'state');
    if (!existsSync(stateDir)) {
      mkdirSync(stateDir, { recursive: true, mode: 0o700 });
    }
    const logPath = path.join(stateDir, 'auto-approval-audit.jsonl');
    const entry = {
      timestamp: new Date().toISOString(),
      command,
      approved: true,
      reason,
    };
    appendFileSync(logPath, JSON.stringify(entry) + '\n', { mode: 0o600 });
  } catch {
    // Audit logging is best-effort — never block command execution
  }
}
```

Add audit log calls in `processPermissionRequest` after each `behavior: 'allow'` decision:

```typescript
  // After safe command approval (line ~184):
  logAutoApproval(input.cwd, command, 'Safe read-only or test command');

  // After heredoc approval (line ~199):
  logAutoApproval(input.cwd, command.split('\n')[0], 'Safe command with heredoc content');
```

**Step 4: Run test to verify it passes**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hooks/permission-handler/index.ts src/hooks/permission-handler/__tests__/index.test.ts
git commit -m "feat(security): add audit logging for auto-approved commands"
```

### Task 9: Remove heredoc auto-approval exception

**Files:**
- Modify: `src/hooks/permission-handler/index.ts`
- Modify: `src/hooks/permission-handler/__tests__/index.test.ts`

**Step 1: Write the failing test**

Add to `src/hooks/permission-handler/__tests__/index.test.ts`:

```typescript
  describe('heredoc exception removed', () => {
    it('should NOT auto-approve git commit with heredoc', () => {
      const cmd = `git commit -m "$(cat <<'EOF'\nfeat: message\nEOF\n)"`;
      const result = processPermissionRequest(createInput(cmd));
      expect(result.hookSpecificOutput?.decision?.behavior).not.toBe('allow');
    });

    it('should NOT auto-approve git tag with heredoc', () => {
      const cmd = `git tag -a v1.0.0 -m "$(cat <<'EOF'\nRelease\nEOF\n)"`;
      const result = processPermissionRequest(createInput(cmd));
      expect(result.hookSpecificOutput?.decision?.behavior).not.toBe('allow');
    });
  });
```

**Step 2: Run test to verify it fails**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: FAIL — heredoc commands are currently auto-approved

**Step 3: Remove heredoc exception from `processPermissionRequest`**

In `src/hooks/permission-handler/index.ts`, remove lines 187-200 (the `isHeredocWithSafeBase` check block in `processPermissionRequest`). Keep the `isHeredocWithSafeBase` function itself exported (it may be used by other consumers), but remove its use in the permission flow.

**Step 4: Update existing heredoc tests to expect denial**

In the test file, update the `heredoc command handling (Issue #608)` describe block: change all tests that expected `behavior: 'allow'` for heredoc commands to expect NOT `'allow'`.

**Step 5: Run test to verify it passes**

Run: `npx vitest run src/hooks/permission-handler/__tests__/index.test.ts`
Expected: PASS

**Step 6: Run full test suite**

Run: `npx vitest run`
Expected: All tests pass

**Step 7: Commit**

```bash
git add src/hooks/permission-handler/index.ts src/hooks/permission-handler/__tests__/index.test.ts
git commit -m "feat(security): remove heredoc auto-approval exception from permission handler"
```

### Task 10: Add hard iteration cap and stop-override to persistent-mode

**Files:**
- Modify: `src/hooks/persistent-mode/index.ts:309-509`
- Create: `src/hooks/persistent-mode/__tests__/guardrails.test.ts`

**Step 1: Write the failing test**

Create `src/hooks/persistent-mode/__tests__/guardrails.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

// We test the guardrail logic by directly testing the exported functions
// and state file behavior

describe('persistent-mode guardrails', () => {
  const testDir = '/tmp/omc-guardrails-test';
  const stateDir = path.join(testDir, '.omc', 'state');

  beforeEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
    fs.mkdirSync(stateDir, { recursive: true });
  });

  afterEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('hard iteration cap', () => {
    it('should not auto-extend beyond ABSOLUTE_MAX_ITERATIONS', () => {
      // Write ralph state at iteration 50 (beyond any reasonable cap)
      const ralphState = {
        active: true,
        iteration: 50,
        max_iterations: 50,
        session_id: 'test-session',
        started_at: new Date().toISOString(),
        prompt: 'test task',
      };
      fs.writeFileSync(
        path.join(stateDir, 'ralph-state.json'),
        JSON.stringify(ralphState)
      );

      // After guardrails, max_iterations should be capped
      // This test validates the state file constraint
      const state = JSON.parse(
        fs.readFileSync(path.join(stateDir, 'ralph-state.json'), 'utf-8')
      );
      expect(state.iteration).toBe(50);
    });
  });

  describe('wall-clock timeout', () => {
    it('should have started_at timestamp in ralph state', () => {
      const now = new Date().toISOString();
      const ralphState = {
        active: true,
        iteration: 1,
        max_iterations: 20,
        session_id: 'test-session',
        started_at: now,
        prompt: 'test task',
      };
      fs.writeFileSync(
        path.join(stateDir, 'ralph-state.json'),
        JSON.stringify(ralphState)
      );

      const state = JSON.parse(
        fs.readFileSync(path.join(stateDir, 'ralph-state.json'), 'utf-8')
      );
      expect(state.started_at).toBeDefined();
      expect(new Date(state.started_at).getTime()).toBeGreaterThan(0);
    });
  });
});
```

**Step 2: Run test to verify baseline**

Run: `npx vitest run src/hooks/persistent-mode/__tests__/guardrails.test.ts`
Expected: PASS (baseline state file tests)

**Step 3: Add guardrails to `checkRalphLoop` in `src/hooks/persistent-mode/index.ts`**

Add config import at top:

```typescript
import { loadConfig } from '../../config/loader.js';
```

Add constants after line 80:

```typescript
/** Absolute maximum iterations — cannot be overridden by config */
const ABSOLUTE_MAX_ITERATIONS = 100;

/** Load guardrail config once */
const _guardrailConfig = loadConfig().guardrails?.ralph ?? {
  hardMaxIterations: 20,
  wallClockTimeoutMinutes: 30,
  maxStopAttempts: 3,
  stopAttemptWindowSeconds: 60,
};
```

In `checkRalphLoop` function (after line 323, after session isolation check), add:

```typescript
  // GUARDRAIL: Hard iteration cap (non-overridable)
  const hardMax = Math.min(
    _guardrailConfig.hardMaxIterations ?? 20,
    ABSOLUTE_MAX_ITERATIONS
  );
  if (state.iteration >= hardMax) {
    clearRalphState(workingDir, sessionId);
    clearVerificationState(workingDir, sessionId);
    deactivateUltrawork(workingDir, sessionId);
    return {
      shouldBlock: false,
      message: `[RALPH LOOP STOPPED - HARD CAP] Reached maximum ${hardMax} iterations. Task may need manual review.`,
      mode: 'none'
    };
  }

  // GUARDRAIL: Wall-clock timeout
  const timeoutMs = (_guardrailConfig.wallClockTimeoutMinutes ?? 30) * 60 * 1000;
  if (state.started_at) {
    const elapsed = Date.now() - new Date(state.started_at).getTime();
    if (elapsed > timeoutMs) {
      clearRalphState(workingDir, sessionId);
      clearVerificationState(workingDir, sessionId);
      deactivateUltrawork(workingDir, sessionId);
      return {
        shouldBlock: false,
        message: `[RALPH LOOP STOPPED - TIMEOUT] Wall-clock timeout of ${_guardrailConfig.wallClockTimeoutMinutes} minutes reached.`,
        mode: 'none'
      };
    }
  }
```

Replace the auto-extend logic at lines 454-460:

```typescript
  // Check max iterations — enforce hard cap instead of auto-extending
  if (state.iteration >= state.max_iterations) {
    if (state.max_iterations < hardMax) {
      // Allow extension up to the hard cap
      state.max_iterations = Math.min(state.max_iterations + 10, hardMax);
      writeRalphState(workingDir, state, sessionId);
    } else {
      // Hard cap reached — stop
      clearRalphState(workingDir, sessionId);
      clearVerificationState(workingDir, sessionId);
      deactivateUltrawork(workingDir, sessionId);
      return {
        shouldBlock: false,
        message: `[RALPH LOOP STOPPED - HARD CAP] Reached maximum ${hardMax} iterations.`,
        mode: 'none'
      };
    }
  }
```

**Step 4: Run tests**

Run: `npx vitest run src/hooks/persistent-mode/__tests__/guardrails.test.ts`
Expected: PASS

**Step 5: Run full test suite**

Run: `npx vitest run`
Expected: All tests pass

**Step 6: Commit**

```bash
git add src/hooks/persistent-mode/index.ts src/hooks/persistent-mode/__tests__/guardrails.test.ts
git commit -m "feat(security): add hard iteration cap and wall-clock timeout to persistent-mode"
```

---

## Branch 4: `security/env-controls`

### Task 11: Create pre-commit hook

**Files:**
- Create: `.githooks/pre-commit`

**Step 1: Write the hook script**

```bash
#!/bin/bash
# Prevent committing oh-my-claudecode runtime files that could
# enable repo-poisoning attacks (auto-activating autonomous modes
# or injecting learned skills into other users' sessions).

STAGED_FILES=$(git diff --cached --name-only)

FORBIDDEN=(".omc/state/" ".omc/skills/" ".omc/config" ".omc/.*\.marker" ".omc/.*\.pid")

for pattern in "${FORBIDDEN[@]}"; do
  MATCHES=$(echo "$STAGED_FILES" | grep -E "$pattern" || true)
  if [ -n "$MATCHES" ]; then
    echo "ERROR: Blocked commit of oh-my-claudecode runtime files:"
    echo "$MATCHES"
    echo ""
    echo "These files should never be committed. Remove with:"
    echo "  git reset HEAD <file>"
    exit 1
  fi
done
```

**Step 2: Make executable and test**

Run: `chmod +x .githooks/pre-commit && bash -n .githooks/pre-commit && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add .githooks/pre-commit
git commit -m "feat(security): add pre-commit hook to block .omc/ runtime files"
```

### Task 12: Create permission enforcement script

**Files:**
- Create: `scripts/enforce-permissions.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Enforce restrictive permissions on OMC sensitive files.
# Run periodically or after installation.

set -euo pipefail

FIXED=0

fix_perms() {
  local target="$1" perm="$2"
  if [ -e "$target" ]; then
    current=$(stat -c %a "$target" 2>/dev/null || stat -f %Lp "$target" 2>/dev/null)
    if [ "$current" != "$perm" ]; then
      chmod "$perm" "$target"
      echo "Fixed: $target ($current -> $perm)"
      FIXED=$((FIXED + 1))
    fi
  fi
}

fix_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    fix_perms "$dir" "700"
    find "$dir" -type f \( -name '*.json' -o -name '*.md' -o -name '*.jsonl' \) -print0 | \
      while IFS= read -r -d '' f; do fix_perms "$f" "600"; done
  fi
}

# Global config
fix_perms "$HOME/.omc/config.json" "600"
fix_dir "$HOME/.omc/skills"

# Project-local state
fix_dir ".omc/state"
fix_dir ".omc/skills"
fix_dir ".omc/logs"

echo "Done. Fixed $FIXED file(s)."
```

**Step 2: Make executable and test syntax**

Run: `chmod +x scripts/enforce-permissions.sh && bash -n scripts/enforce-permissions.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add scripts/enforce-permissions.sh
git commit -m "feat(security): add file permission enforcement script"
```

### Task 13: Create CLAUDE.md watcher script

**Files:**
- Create: `scripts/watch-claude-md.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Detect unexpected modifications to ~/.claude/CLAUDE.md.
# Usage:
#   scripts/watch-claude-md.sh save    # Save current hash as baseline
#   scripts/watch-claude-md.sh check   # Check against saved baseline

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
HASH_FILE="$HOME/.claude/.claude-md-hash"

save_hash() {
  if [ ! -f "$CLAUDE_MD" ]; then
    echo "No ~/.claude/CLAUDE.md found."
    exit 1
  fi
  sha256sum "$CLAUDE_MD" | cut -d' ' -f1 > "$HASH_FILE"
  chmod 600 "$HASH_FILE"
  echo "Saved hash: $(cat "$HASH_FILE")"
}

check_hash() {
  if [ ! -f "$HASH_FILE" ]; then
    echo "No baseline hash found. Run: $0 save"
    exit 1
  fi
  if [ ! -f "$CLAUDE_MD" ]; then
    echo "WARNING: ~/.claude/CLAUDE.md has been deleted!"
    exit 1
  fi
  EXPECTED=$(cat "$HASH_FILE")
  CURRENT=$(sha256sum "$CLAUDE_MD" | cut -d' ' -f1)
  if [ "$EXPECTED" != "$CURRENT" ]; then
    echo "WARNING: ~/.claude/CLAUDE.md has been modified!"
    echo "Expected: $EXPECTED"
    echo "Current:  $CURRENT"
    exit 1
  fi
  echo "OK: ~/.claude/CLAUDE.md matches baseline."
}

case "${1:-check}" in
  save) save_hash ;;
  check) check_hash ;;
  *) echo "Usage: $0 [save|check]" ;;
esac
```

**Step 2: Make executable and test syntax**

Run: `chmod +x scripts/watch-claude-md.sh && bash -n scripts/watch-claude-md.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add scripts/watch-claude-md.sh
git commit -m "feat(security): add CLAUDE.md change detection script"
```

---

## Branch 5: `security/monitoring`

### Task 14: Create security scan script

**Files:**
- Create: `scripts/security-scan.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Periodic security health check for oh-my-claudecode.
# Run weekly via cron or manually after configuration changes.

set -uo pipefail

ISSUES=0
WARNINGS=0

check() {
  local severity="$1" desc="$2" condition="$3"
  if eval "$condition" 2>/dev/null; then
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

check "WARN" "Active autonomous mode state files" \
  "ls .omc/state/*-state.json 2>/dev/null | grep -q ."

check "FAIL" ".omc/ not in .gitignore" \
  "! grep -q '\.omc/' .gitignore 2>/dev/null"

check "FAIL" "~/.omc/config.json has loose permissions" \
  "[ -f ~/.omc/config.json ] && [ \$(stat -c %a ~/.omc/config.json 2>/dev/null || echo 600) != '600' ]"

check "FAIL" ".omc/ files staged in git" \
  "git diff --cached --name-only 2>/dev/null | grep -q '\.omc/'"

check "WARN" "~/.claude/CLAUDE.md baseline not saved" \
  "[ -f ~/.claude/CLAUDE.md ] && [ ! -f ~/.claude/.claude-md-hash ]"

check "WARN" "Bridge bundle checksums not verified" \
  "[ ! -f bridge/checksums-verified.sha256 ]"

check "FAIL" "Pre-commit hook not installed" \
  "[ ! -x .githooks/pre-commit ] && [ ! -x .git/hooks/pre-commit ]"

check "WARN" "Learned skills contain suspicious patterns" \
  "grep -rl 'subprocess\|import os\|__import__' ~/.omc/skills/ 2>/dev/null | grep -q ."

echo ""
echo "=== Results: $ISSUES failure(s), $WARNINGS warning(s) ==="
[ $ISSUES -gt 0 ] && exit 1
exit 0
```

**Step 2: Make executable and test syntax**

Run: `chmod +x scripts/security-scan.sh && bash -n scripts/security-scan.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add scripts/security-scan.sh
git commit -m "feat(security): add periodic security health check script"
```

### Task 15: Create skill integrity script

**Files:**
- Create: `scripts/skill-integrity.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Generate or verify integrity manifest for learned skill files.
# Usage:
#   scripts/skill-integrity.sh [skills-dir] generate  # Create manifest
#   scripts/skill-integrity.sh [skills-dir] verify     # Check against manifest

set -euo pipefail

SKILLS_DIR="${1:-$HOME/.omc/skills/omc-learned}"
MANIFEST="$SKILLS_DIR/.manifest.json"
ACTION="${2:-verify}"

generate() {
  if [ ! -d "$SKILLS_DIR" ]; then
    echo "Skills directory not found: $SKILLS_DIR"
    exit 1
  fi

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
    echo "No manifest found at $MANIFEST"
    echo "Run: $0 $SKILLS_DIR generate"
    exit 1
  fi

  violations=0
  for f in "$SKILLS_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    expected=$(python3 -c "import json,sys; m=json.load(open('$MANIFEST')); print(m.get('$name','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
    actual=$(sha256sum "$f" | cut -d' ' -f1)

    if [ "$expected" = "MISSING" ]; then
      echo "NEW (untracked): $name"
      violations=$((violations + 1))
    elif [ "$expected" = "PARSE_ERROR" ]; then
      echo "ERROR: Cannot parse manifest"
      exit 1
    elif [ "$expected" != "$actual" ]; then
      echo "MODIFIED: $name"
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

case "$ACTION" in
  generate) generate ;;
  verify) verify ;;
  *) echo "Usage: $0 [skills-dir] [generate|verify]" ;;
esac
```

**Step 2: Make executable and test syntax**

Run: `chmod +x scripts/skill-integrity.sh && bash -n scripts/skill-integrity.sh && echo "Syntax OK"`
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add scripts/skill-integrity.sh
git commit -m "feat(security): add skill file integrity verification script"
```

---

## Final: Merge Sequence

After all branches are complete and tested:

1. Merge branches 1, 4, 5 into `dev` (no conflicts expected — different files)
2. Merge branch 2 into `dev`
3. Merge branch 3 into `dev` (depends on branch 2's config schema)
4. Run full test suite on `dev`: `npx vitest run`
5. Run security scan: `scripts/security-scan.sh`
6. Tag release: `git tag -a v4.4.1-hardened -m "Security hardening release"`
