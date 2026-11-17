# MealMate multi-team rebuild

This is the development track for MealMate's multi-team shared-expense application. The legacy production UI and legacy household tables remain available and have not been deleted or rewritten.

## Product rules

- One email/password account can create and join multiple teams.
- Team data is isolated with Postgres Row Level Security.
- Owner, admin, and member roles are scoped to each team.
- Invitations are tokenized, expire, and may be reused by multiple people; an invitation can optionally be restricted to one email address.
- Expenses can be split equally, by fixed amount, or by percentage, among all active members by default or a selected subset.
- Money is stored as integer minor units (halalas for SAR).
- Expense shares are immutable snapshots. New members participate from their joining date; leaving a team preserves historical allocations.
- A settlement is pending until both payer and recipient confirm. Only then does it affect balances.
- The first Android release target is an installable PWA, avoiding native-store fees and paid infrastructure.

## Database state

The following migrations have been applied to the connected Supabase Free project. All new tables use the `mm_` prefix; legacy `households`, `members`, and `expenses` tables were not altered or deleted.

- Multi-team core tables and RLS.
- Transactional expense and settlement RPCs.
- Reusable invitations.
- Team role management and Realtime publication.
- Authorization hardening: anonymous Auth identities are rejected by multi-team membership checks; security-definer helper functions are kept in the non-API `private` schema.
- Historical membership periods and query indexes.

The database smoke test ran under the `authenticated` database role in a transaction and rolled back. It verified team creation, invitation redemption by multiple accounts, three-member expense allocation, two-party settlement completion, and RLS isolation (non-members saw zero team/expense rows). A separate check verified anonymous membership rejection. No test records were retained.

## Deployment boundary

- Work is on `feature/multi-team-foundation`.
- Vercel deployment is a preview only.
- `main` has not been modified, and no production deployment was promoted.
- No paid Supabase branch or paid resource was created.
- The existing Supabase project received additive schema changes only. Legacy household data remains unchanged.

## Verification and remaining acceptance step

GitHub Actions passes dependency installation, unit tests, lint, and production build. The preview's app shell, manifest, service worker, and Supabase configuration were fetched successfully.

Before production promotion, test with two real email/password accounts on separate devices: create a team, invite and join, add an expense, verify balances, and complete a two-party settlement. Confirm email delivery and password reset redirects in the actual account environment.
