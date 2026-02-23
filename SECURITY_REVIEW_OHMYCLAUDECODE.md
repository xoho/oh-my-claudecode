Security Review: oh-my-claudecode

  This is a Claude Code plugin that converts single-agent Claude Code into a multi-agent orchestration
  platform. It's popular (7k+ stars) but architecturally invasive.

  CRITICAL Issues

  1. Total hook interception — Registers hooks on every Claude Code lifecycle event (UserPromptSubmit,
  PreToolUse, PostToolUse, PermissionRequest, Stop, SessionStart, etc.). Every user prompt, every tool
  call, every tool result is intercepted and injected with behavioral directives via additionalContext.
  2. Stop-blocking — The persistent-mode.mjs hook returns {"decision": "block"} to prevent Claude from
  stopping, forcing continued autonomous execution in "ralph", "autopilot", and "ultrawork" modes. This
  subverts user control.
  3. CLAUDE.md overwrite — The setup skill downloads a CLAUDE.md from GitHub and installs it at
  ~/.claude/CLAUDE.md, effectively replacing Claude Code's system instructions with its own 28-agent
  orchestration protocol.

  HIGH Issues

  4. Auto-approval of bash commands — During autonomous modes, the permission handler auto-approves
  commands matching an allowlist without user confirmation. A previous version had a critical bug where
  all commands were auto-approved (patched, but the pattern remains risky).
  5. External data channels — Built-in notification dispatchers send session data to Discord, Telegram,
  Slack, and arbitrary webhooks. A bidirectional reply listener polls these services and injects external
  messages back into Claude sessions.
  6. Un-auditable pre-built bundles — bridge/mcp-server.cjs (805KB) and bridge/team-mcp.cjs (622KB) are
  committed as minified JavaScript. No guarantee they match the TypeScript source.
  7. Python REPL via MCP — Exposes arbitrary Python code execution through a JSON-RPC server over Unix
  sockets.
  8. Persistent autonomous state — .omc/state/ files auto-restore modes across sessions. A malicious .omc/
   directory in a cloned repo could auto-activate autonomous modes when you open the project.

  MEDIUM Issues

  9. Learned skills as injection vectors — Auto-extracts "skills" from sessions, persists them to
  .omc/skills/, then auto-injects them into future prompts. Writable skill files = persistent prompt
  injection.
  10. Keyword hijacking — Words like "team", "autopilot", "ralph" in natural conversation can
  unintentionally activate autonomous modes.
  11. npm name mismatch — GitHub repo is oh-my-claudecode, npm package is oh-my-claude-sisyphus —
  potential for typosquatting confusion.

  Positive Findings

  The project does show security awareness: shell metacharacter blocking, path traversal prevention,
  socket permissions set to 0600, ReDoS prevention, kill switches (DISABLE_OMC=1), and Zod schema
  validation on MCP inputs.

  Bottom Line

  This plugin is essentially a full behavioral takeover of Claude Code. It intercepts everything, injects
  instructions at every stage, can block you from stopping, auto-approves commands, and opens external
  communication channels. While it provides legitimate orchestration functionality, the security model
  requires you to fully trust the plugin authors and their supply chain — including opaque pre-built
  bundles that can't be easily audited. Use with caution, especially on sensitive codebases.
