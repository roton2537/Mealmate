/**
 * Pure financial primitives for multi-team shared expenses.
 * All monetary calculations use integer minor units (e.g. halalas for SAR).
 * This module has no Supabase or browser dependency and is safe to test offline.
 */
export type SplitMethod = 'equal' | 'fixed' | 'percentage'
export type AllocationInput = {
  memberIds: string[]
  method: SplitMethod
  totalMinor: number
  fixedShares?: Record<string, number>
  percentages?: Record<string, number>
}

export type Allocation = { memberId: string; shareMinor: number }

function assertPositiveInteger(value: number, label: string) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${label} must be a positive safe integer`)
  }
}

function distributeRemainder(total: number, weights: number[]): number[] {
  const weightTotal = weights.reduce((sum, weight) => sum + weight, 0)
  if (!Number.isFinite(weightTotal) || weightTotal <= 0) throw new Error('Split weights must total more than zero')
  const raw = weights.map(weight => total * weight / weightTotal)
  const shares = raw.map(Math.floor)
  let remainder = total - shares.reduce((sum, value) => sum + value, 0)
  // Stable largest-remainder allocation; ties preserve memberIds order.
  const order = raw.map((value, index) => ({ index, fraction: value - Math.floor(value) }))
    .sort((a, b) => b.fraction - a.fraction || a.index - b.index)
  for (let i = 0; i < remainder; i += 1) shares[order[i].index] += 1
  return shares
}

export function allocateExpense(input: AllocationInput): Allocation[] {
  const { memberIds, method, totalMinor } = input
  assertPositiveInteger(totalMinor, 'Expense amount')
  if (!memberIds.length) throw new Error('At least one participant is required')
  if (new Set(memberIds).size !== memberIds.length) throw new Error('Participants must be unique')
  let shares: number[]
  if (method === 'equal') {
    shares = distributeRemainder(totalMinor, memberIds.map(() => 1))
  } else if (method === 'fixed') {
    const values = memberIds.map(id => input.fixedShares?.[id])
    if (values.some(value => !Number.isSafeInteger(value) || (value as number) < 0)) {
      throw new Error('Every participant needs a non-negative fixed share in minor units')
    }
    shares = values as number[]
    if (shares.reduce((sum, value) => sum + value, 0) !== totalMinor) {
      throw new Error('Fixed shares must add up exactly to the expense amount')
    }
  } else {
    const values = memberIds.map(id => input.percentages?.[id])
    if (values.some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
      throw new Error('Every participant needs a non-negative percentage')
    }
    const weights = values as number[]
    if (Math.abs(weights.reduce((sum, value) => sum + value, 0) - 100) > 1e-8) {
      throw new Error('Percentages must add up to 100')
    }
    shares = distributeRemainder(totalMinor, weights)
  }
  return memberIds.map((memberId, index) => ({ memberId, shareMinor: shares[index] }))
}

export function calculateNetBalances(
  allocations: Allocation[],
  payerMemberId: string,
  totalMinor: number,
): Record<string, number> {
  assertPositiveInteger(totalMinor, 'Expense amount')
  const allocated = allocations.reduce((sum, item) => sum + item.shareMinor, 0)
  if (allocated !== totalMinor) throw new Error('Allocations must equal the expense amount')
  if (allocations.some(item => !Number.isSafeInteger(item.shareMinor) || item.shareMinor < 0)) {
    throw new Error('Allocation shares must be non-negative integer minor units')
  }
  if (!allocations.some(item => item.memberId === payerMemberId)) {
    throw new Error('Payer must be included among expense participants')
  }
  const result: Record<string, number> = {}
  for (const item of allocations) result[item.memberId] = (result[item.memberId] ?? 0) - item.shareMinor
  result[payerMemberId] = (result[payerMemberId] ?? 0) + totalMinor
  return result
}
