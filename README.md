# MealMate

A bilingual (English/Bangla) shared household meal-expense tracker for four members. Currency: Saudi Riyal (SAR). Every expense is divided equally between all four members. MealMate does not track meals consumed or individual consumption.

## Agreed group
- MD ROTON MIAH
- AJIBUR RAHMAN
- ROBIUL ISLAM
- HINDI

## Current implementation
- React + Vite frontend connected to the MealMate Supabase project.
- Email magic-link sign-in for existing, pre-approved member accounts; public account creation is disabled in the app.
- Shared expense persistence in Supabase Postgres.
- Add, edit, and delete expense records.
- Equal-share balances, payer totals, SAR formatting, and English/Bangla UI.
- Local-calendar date defaults and mobile-responsive expense controls.
- Row Level Security restricts access to members whose Auth account is linked to a household member record.
- Four household member records are seeded. Only MD ROTON MIAH is currently linked to a verified Auth account; the other accounts require verified email addresses and explicit administrator linking.

## Supabase project
- Project ref: `ebtxkomgbzhdujuhgtdm`
- Region: Mumbai (`ap-south-1`)
- URL: `https://ebtxkomgbzhdujuhgtdm.supabase.co`
- Browser uses only the Supabase publishable key. Never add a service-role or secret key to frontend code.

## Development
1. Install Node.js 22.12+ and npm.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
4. Run `npm run dev`.
5. Run `npm test`, `npm run lint`, and `npm run build` before release.

## Security and onboarding
- Sign-in uses email magic links and does not create new accounts from the public app.
- A newly authenticated user sees no household data until their Auth user ID is explicitly linked to one of the four approved member rows.
- Do not link accounts based only on display names; verify each email address with the member first.
- Keep local environment files uncommitted. Never expose a Supabase service-role or secret key in frontend code.
- Supabase's built-in email sender has a low sending limit. Configure a genuinely free custom SMTP provider before inviting all members; do not disable email confirmation or pay for a service without approval.
- Production deployment and external invitations require explicit approval.

## Deployment policy
- The Vercel production branch remains `main`.
- Development validation must use Preview deployments from `rebuild/phase-1-foundation`.
- Do not merge this branch into `main`, promote a deployment, or create a production release without separate explicit approval.
- Keep all infrastructure on free tiers; stop and ask before any action that could incur a charge.
