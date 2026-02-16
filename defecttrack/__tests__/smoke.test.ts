import { describe, it, expect } from 'vitest'

describe('smoke test', () => {
  it('should verify test framework works', () => {
    expect(1 + 1).toBe(2)
  })

  it('should have jsdom environment', () => {
    expect(typeof document).toBe('object')
  })
})
