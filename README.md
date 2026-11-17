# MealMate

A bilingual (English/Bangla) shared household meal-expense tracker for four members. Currency: Saudi Riyal (SAR). Every expense is divided equally between all four members. MealMate does not track meals consumed or individual consumption.

## Agreed group
- MD ROTON MIAH
- AJIBUR RAHMAN
- ROBIUL ISLAM
- HINDI

## Current implementation
The first UI foundation provides expense entry, expense history, equal-share summaries, payer totals, and English/Bangla switching. The current preview stores data in this browser's local storage only. It is not yet shared between devices and must not be treated as the production ledger.

## Development
1. Install Node.js 22.12+ and npm.
2. Run npm install.
3. Copy .env.example to .env only after a Supabase project is provisioned.
4. Run npm run dev.
5. Run npm test, npm run lint, and npm run build before release.

## Planned stages
1. UI and equal-share calculation foundation.
2. Supabase Auth, group/member records, expenses, and strict Row Level Security.
3. Shared realtime updates and cross-device persistence.
4. Automated tests, security review, and deployment preparation.

Never put a Supabase service-role or secret key in frontend code. Keep .env local and uncommitted. Production access must be protected by authentication and database RLS.
