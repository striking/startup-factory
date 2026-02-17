import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Defect } from '../app/defects/types';

function makeDefect(overrides: Partial<Defect> = {}): Defect {
  return {
    id: '1',
    photo: null,
    category: 'structural',
    location: 'Level 3, Unit 5',
    severity: 3,
    description: 'Crack in wall',
    createdAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

describe('storage helpers', () => {
  let store: Record<string, string>;

  beforeEach(() => {
    store = {};
    const mockLocalStorage = {
      getItem: vi.fn((key: string) => store[key] ?? null),
      setItem: vi.fn((key: string, value: string) => { store[key] = value; }),
      removeItem: vi.fn((key: string) => { delete store[key]; }),
      clear: vi.fn(() => { store = {}; }),
      length: 0,
      key: vi.fn(() => null),
    };
    vi.stubGlobal('localStorage', mockLocalStorage);
  });

  it('getDefects returns empty array when no data exists', async () => {
    const { getDefects } = await import('../app/defects/storage');
    expect(getDefects()).toEqual([]);
  });

  it('getDefects returns empty array for invalid JSON', async () => {
    store['defecttrack_defects'] = 'not-json';
    const { getDefects } = await import('../app/defects/storage');
    expect(getDefects()).toEqual([]);
  });

  it('saveDefect stores a defect and getDefects retrieves it', async () => {
    const { saveDefect, getDefects } = await import('../app/defects/storage');
    const defect = makeDefect();
    saveDefect(defect);
    expect(getDefects()).toEqual([defect]);
  });

  it('saveDefect appends to existing defects', async () => {
    const { saveDefect, getDefects } = await import('../app/defects/storage');
    const d1 = makeDefect({ id: '1' });
    const d2 = makeDefect({ id: '2', category: 'electrical' });
    saveDefect(d1);
    saveDefect(d2);
    const result = getDefects();
    expect(result).toHaveLength(2);
    expect(result[0].id).toBe('1');
    expect(result[1].id).toBe('2');
  });
});
