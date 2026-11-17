# MealMate multi-team application

This is the active development track for MealMate's multi-team shared-expense application.

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

## Active application and database

- `src/main.tsx` mounts `src/MultiTeamApp.tsx`.
- The active app reads and writes only the seven `mm_`-prefixed tables.
- Team data is protected by RLS. Security-definer implementations live in the non-exposed `private` schema; public RPC entry points are security-invoker wrappers.
- The old single-household UI and helper modules have been removed from active source.
- The old household tables, private tables, and household-only RPC functions have been dropped from the connected Supabase project.
- The seven `mm_` tables are empty after the approved database reset.

## Migration history

The earlier household SQL migrations are retained as historical migration records. They must remain in chronological order for existing Supabase migration-ledger consistency. The final migration `20261117162421_remove_legacy_household_system.sql` removes the legacy household objects, so a fresh replay finishes with the multi-team schema only.

## Deployment boundary

- Work is on `feature/multi-team-foundation`.
- Vercel deployment is a preview only.
- `main` has not been modified, and no production deployment was promoted.
- No paid Supabase branch or paid resource was created.

## Verification and remaining acceptance step

Earlier database smoke tests verified team creation, invitation redemption, expense allocation, two-party settlement completion, anonymous-account rejection, and RLS isolation. The new legacy-removal migration has been applied to the connected project.

Before production promotion, perform a fresh real-user acceptance test with two email/password accounts on separate devices: create a team, invite and join, add an expense, verify balances, and complete a two-party settlement. Confirm email delivery and password reset redirects in the actual account environment.
