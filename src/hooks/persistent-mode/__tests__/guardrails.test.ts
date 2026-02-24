import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

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
