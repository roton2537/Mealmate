# MealMate

MealMate is being rebuilt from a single-household meal-cost tracker into a general, multi-team shared-expense application.

## Product direction

- A personal email/password account can create multiple teams and join multiple teams.
- Team owners can appoint admins; members have team-scoped permissions.
- Invitations use expiring invite links/codes.
- Every team has isolated members, expenses, balances, settlements, and audit history.
- Expenses support equal, fixed-amount, and percentage splits across all or selected participants.
- New members participate only from their joining date. Departing members stop participating after their leaving date; historical allocations remain.
- Settlements affect balances only after both payer and recipient confirm receipt/payment.
- English and Bangla interfaces; Android support through an installable Progressive Web App (PWA) is the initial target.

## Repository status

- `main` remains the production branch and is not modified by this rebuild.
- `rebuild/phase-1-foundation` contains the previous household-only application.
- `feature/multi-team-foundation` is the isolated multi-team development branch.
- See [MULTI_TEAM_REBUILD.md](./MULTI_TEAM_REBUILD.md) for captured product rules and safety boundaries.
- The pure financial allocation engine is in `src/lib/finance.ts`, with tests in `src/test/finance.test.ts`.
- The draft multi-team database schema is in `supabase/migrations/20261117010000_multi_team_core.sql`.

## Important: not yet ready for live use

The new database migration is staged in GitHub only. It has **not** been applied to the connected Supabase project. The existing Supabase project has no free development branch; creating one required a cost confirmation, which is outside the zero-cost constraint.

The old household UI and authentication gate are not yet compatible with the new multi-team schema. Do not treat the current preview as the finished multi-team product. End-to-end use requires transactional RPCs, complete RLS policies, the multi-team UI/auth flow, and isolated database validation.

## Zero-cost and security policy

- Do not create paid Supabase branches, paid plans, or other billable resources.
- Do not apply the new schema to the existing Supabase project until an isolated zero-cost validation path is available.
- Do not modify or deploy to `main`; no production promotion is authorized.
- Never put Supabase service-role or secret keys in browser code. Use the publishable key with strict database RLS.
- Keep local environment files uncommitted.

## Development checks

Install dependencies with `npm install`, then run `npm test`, `npm run lint`, and `npm run build`. These checks have not yet been run in this remote-only editing session.
