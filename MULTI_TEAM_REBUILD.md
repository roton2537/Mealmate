# MealMate multi-team rebuild

This branch is the isolated development track for the general shared-expense product. The existing production branch and current Supabase schema are not modified.

## Product rules captured in this rebuild

- One email/password identity can own or join multiple teams.
- Team data is isolated; authorization is enforced by Postgres Row Level Security, not by frontend filters.
- Expenses are paid by a member and allocated to all or selected participants.
- Equal, fixed-amount, and percentage allocations are supported by the financial domain layer.
- Monetary calculations use integer minor units (halalas for SAR); persisted allocations are immutable snapshots.
- New members participate only from their effective joining date. Leaving a team ends future participation but preserves past ledger records.
- A settlement changes balances only after both payer and recipient confirm it.
- Team owner/admin/member roles are scoped to a team.

## Current safety boundary

The migration in this branch is a draft and is NOT applied to the connected Supabase project. The Supabase project currently has no free development branch; creating one requested a cost confirmation. Do not apply this schema to the existing project until an isolated, zero-cost validation route is available.

No paid Supabase resources, paid Vercel features, production deployments, or production database changes are authorized by this work.

## Development checks

Run `npm test`, `npm run lint`, and `npm run build` after installing dependencies. The finance module is pure TypeScript and can be tested without a Supabase connection.
