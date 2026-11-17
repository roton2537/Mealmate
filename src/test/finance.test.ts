import { describe, expect, it } from 'vitest'
import { allocateExpense, calculateNetBalances } from '../lib/finance'

describe('multi-team expense allocation primitives', () => {
  it('splits equally and distributes remainder deterministically', () => {
    expect(allocateExpense({ memberIds: ['a','b','c'], method: 'equal', totalMinor: 1000 }))
      .toEqual([{memberId:'a',shareMinor:334},{memberId:'b',shareMinor:333},{memberId:'c',shareMinor:333}])
  })
  it('supports exact fixed amounts', () => {
    expect(allocateExpense({ memberIds:['a','b'], method:'fixed', totalMinor:1000, fixedShares:{a:725,b:275} }))
      .toEqual([{memberId:'a',shareMinor:725},{memberId:'b',shareMinor:275}])
  })
  it('supports percentage splits without losing a minor unit', () => {
    expect(allocateExpense({ memberIds:['a','b','c'], method:'percentage', totalMinor:1001, percentages:{a:50,b:25,c:25} })
      .reduce((sum, item) => sum + item.shareMinor, 0)).toBe(1001)
  })
  it('computes payer credit and other members debts', () => {
    const shares = allocateExpense({ memberIds:['a','b','c','d'], method:'equal', totalMinor:10000 })
    expect(calculateNetBalances(shares, 'a', 10000)).toEqual({a:7500,b:-2500,c:-2500,d:-2500})
  })
  it('rejects fixed shares that do not reconcile', () => {
    expect(() => allocateExpense({memberIds:['a','b'],method:'fixed',totalMinor:1000,fixedShares:{a:400,b:500}})).toThrow()
  })
  it('rejects duplicate participants and malformed percentages', () => {
    expect(() => allocateExpense({memberIds:['a','a'],method:'equal',totalMinor:100})).toThrow()
    expect(() => allocateExpense({memberIds:['a','b'],method:'percentage',totalMinor:100,percentages:{a:40,b:40}})).toThrow()
  })

  it('rejects duplicate member allocations in balance calculations', () => {
    expect(() => calculateNetBalances([
      { memberId: 'a', shareMinor: 50 },
      { memberId: 'a', shareMinor: 50 },
    ], 'a', 100)).toThrow('unique')
  })
  it('rejects zero and unsafe-integer expense amounts', () => {
    expect(() => allocateExpense({ memberIds: ['a'], method: 'equal', totalMinor: 0 })).toThrow()
    expect(() => allocateExpense({ memberIds: ['a'], method: 'equal', totalMinor: Number.MAX_SAFE_INTEGER + 1 })).toThrow()
  })
  it('supports a zero-share participant when percentages allocate the full total elsewhere', () => {
    expect(allocateExpense({
      memberIds: ['a', 'b'], method: 'percentage', totalMinor: 101,
      percentages: { a: 100, b: 0 },
    })).toEqual([{ memberId: 'a', shareMinor: 101 }, { memberId: 'b', shareMinor: 0 }])
  })
})
