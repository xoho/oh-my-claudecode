import { describe, it, expect, vi } from 'vitest';

// Mock the config loader to enable slash prefix
vi.mock('../../../config/loader.js', () => ({
  loadConfig: () => ({
    keywordDetection: {
      requireSlashPrefix: true,
    },
  }),
}));

// Must import AFTER mock is set up
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { detectKeywordsWithType, getAllKeywords } = await import('../index.js');

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
        const nonCancel = result.filter((r: { type: string }) => r.type !== 'cancel');
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
        expect(result.some((r: { type: string }) => r.type === type)).toBe(true);
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
