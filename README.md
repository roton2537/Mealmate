# MealMate

MealMate is a multi-team shared-expense PWA for households, flatmates, and small groups.

## Product capabilities

- Email/password signup, sign-in, and password reset.
- A user can create and join multiple independent teams.
- Expiring, reusable invitation links/codes; optional email restriction.
- Team-scoped owner, admin, and member roles.
- Expense splitting: equal, fixed amounts, and percentages.
- Integer minor-unit money calculations (halalas for SAR) with immutable share snapshots.
- New members participate from their joining date; leaving members retain historical allocations.
- Settlement requests require both payer and recipient confirmation before balances change.
- Monthly totals, per-member balances, English/Bangla interface, and realtime updates.
- Android installation through an installable Progressive Web App (PWA).

## Current implementation

- Main application: `src/MultiTeamApp.tsx`; `src/main.tsx` mounts the multi-team app.
- Finance engine: `src/lib/finance.ts`; unit tests: `src/test/finance.test.ts`.
- Database migrations: `supabase/migrations/`. These migrations were applied additively to the connected Supabase project.
- The new schema uses `mm_`-prefixed tables. The old `households`, `members`, and `expenses` tables and their records remain intact.
- Security helpers are stored in the non-API `private` schema; team tables have RLS enabled and writes use validated RPC functions.
- PWA files: `public/manifest.webmanifest`, `public/sw.js`, and `public/meal-mate-icon.svg`.

## Environments and safety

- Production branch: `main` — not modified or promoted by this rebuild.
- Development branch: `feature/multi-team-foundation`.
- Supabase project: existing Free project; new tables and RPCs were added without changing legacy household tables.
- Vercel: branch preview only; no production promotion.
- No paid Supabase branch, paid plan, or billable resource was created.
- The browser uses only the Supabase publishable key. Never expose a service-role or secret key.

## Verification

- GitHub Actions: `npm ci`, `npm test`, `npm run lint`, and `npm run build` pass on the latest verified application commit.
- Database integration smoke test ran inside a transaction and rolled back: team creation, a reusable invitation redeemed by multiple users, three-person expense allocation, two-party settlement confirmation, and anonymous-account rejection.
- Database smoke test left no test rows behind. The live multi-team tables currently contain no team data.
- PWA manifest, service worker, app shell, and preview bundle return HTTP 200 and include the configured Supabase project.

A real-user acceptance test (sign in from two separate devices/accounts, invite, record an expense, and confirm a settlement) is still required before production promotion.
