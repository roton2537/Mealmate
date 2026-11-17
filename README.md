# MealMate

MealMate is a multi-team shared-expense Progressive Web App (PWA) for households, flatmates, and small groups.

## Product capabilities

- Email/password signup, sign-in, and password reset.
- One user can create and join multiple independent teams.
- Expiring invitation links; optional email restriction.
- Team-scoped owner, admin, and member roles.
- Expense splitting: equal, fixed amounts, and percentages.
- Integer minor-unit money calculations (halalas for SAR) with immutable share snapshots.
- New members participate from their joining date; leaving members retain historical allocations.
- Settlement requests require both payer and recipient confirmation before balances change.
- Monthly totals, per-member balances, English/Bangla interface, and realtime updates.
- Android installation through an installable PWA.

## Active implementation

- Entry point: `src/main.tsx`, mounting `src/MultiTeamApp.tsx`.
- Finance engine: `src/lib/finance.ts`; tests: `src/test/finance.test.ts`.
- Database migrations: `supabase/migrations/`.
- All active application data uses the seven `mm_` tables.
- Security helpers and SECURITY DEFINER implementations are stored in the non-API `private` schema. Public RPC entry points are SECURITY INVOKER wrappers; team tables use RLS and writes use validated transactional functions.
- PWA files: `public/manifest.webmanifest`, `public/sw.js`, and `public/meal-mate-icon.svg`.

## Legacy household retirement

The old single-household frontend, auth gate, helper modules, and stale schema snapshot have been removed from the active source tree. The old household tables, private tables, and household-only RPC functions have been dropped from the connected Supabase project.

Older SQL migration files remain in `supabase/migrations/` as historical migration history so existing project migration records remain consistent. The final migration, `20261117200000_remove_legacy_household_system.sql`, removes the legacy objects after those historical migrations on a fresh setup. Do not remove or reorder historical migrations without reconciling the Supabase migration ledger.

## Environments and safety

- Production branch: `main` — not modified or promoted.
- Development branch: `feature/multi-team-foundation`.
- Supabase project: existing Free project; no paid resources created.
- Vercel: branch preview only; no production promotion.
- The browser uses only the Supabase publishable key. Never expose a service-role or secret key.

## Verification

- Earlier GitHub Actions runs passed dependency installation, unit tests, lint, and production build before the legacy-source cleanup.
- Database integration smoke tests previously verified team creation, invitations, expense allocation, two-party settlement confirmation, and RLS isolation.
- The live database was reset: the seven `mm_` tables are empty and ready for fresh acceptance testing.
- A new real-user acceptance test is still required: sign in, create a team, invite a second account, record an expense, verify balances, and complete a two-party settlement.
