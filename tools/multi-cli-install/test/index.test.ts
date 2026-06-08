import { describe, it, expect } from 'vitest';
import { VERSION } from '../src/index.js';

describe('multi-cli-install', () => {
  it('exports a version string', () => {
    expect(VERSION).toBe('0.0.3');
  });
});
