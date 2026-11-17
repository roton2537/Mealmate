# MealMate

A bilingual (English/Bangla) shared household meal-expense tracker for four members. Currency: Saudi Riyal (SAR). Every expense is divided equally between all four members. MealMate does not track meals consumed or individual consumption.

## Agreed group
- MD ROTON MIAH
- AJIBUR RAHMAN
- ROBIUL ISLAM
- HINDI

## Current implementation
- React + Vite frontend connected to the MealMate Supabase project.
- Email magic-link sign-in for pre-created member accounts.
- Shared expense persistence in Supabase Postgres.
- Equal-share balances, payer totals, SAR formatting, and English/Bangla UI.
- Row Level Security restricts access to members whose Auth account is linked to a household member record.
- The four household member records are seeded. Their Auth accounts are intentionally not created or linked until each email identity is verified.

## Supabase project
- Project ref: `ebtxkomgbzhdujuhgtdm`
- Region: Mumbai (`ap-south-1`)
- URL: `https://ebtxkomgbzhdujuhgtdm.supabase.co`
- Browser uses only the Supabase publishable key. Never add a service-role or secret key to frontend code.

## Development
1. Install Node.js 22.12+ and npm.
2. Run `npm install`.
3. Optional: set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` in a local `.env.local` file.
4. Run `npm run dev`.
5. Run `npm test`, `npm run lint`, and `npm run build` before release.

## Security and onboarding
- Sign-in uses email magic links and permits account creation after email verification.
- A newly authenticated user sees no household data until their Auth user ID is explicitly linked to one of the four approved member rows.
- Do not link accounts based only on display names; verify each email address with the member first.
- Keep local environment files uncommitted. Never expose a Supabase service-role or secret key in frontend code.
- Production deployment and external invitations require explicit approval.
