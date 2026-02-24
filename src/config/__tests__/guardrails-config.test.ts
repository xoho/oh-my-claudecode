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
