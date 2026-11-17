# MealMate

A shared household meal-expense tracker for four members, with an equal 25% split per purchase, SAR currency, and full English/Bangla bilingual support. Built with React + TypeScript + Vite on the frontend and Supabase (Postgres + Auth + Row Level Security) on the backend.

See `docs/` for the full phase-by-phase build log:
- `01-PRD.md` — product requirements
- `02-design-system.md` — UI/UX design system
- `03-architecture.md` — technical architecture
- `12-test-report.md` — what was tested, how, and what's still pending a live Supabase project

## Prerequisites
- Node.js 18+ and npm
- A Supabase project (free tier is enough) — [supabase.com](https://supabase.com)

## 1. Install dependencies
```bash
npm install
```

## 2. Create your Supabase project and run the migrations
1. Create a new project at [supabase.com](https://supabase.com/dashboard).
2. In the SQL editor, run `supabase/migrations/0001_schema.sql`, then `supabase/migrations/0002_rls.sql`, in that order.
3. Follow the manual steps in `supabase/seed.sql` to invite the four members as Supabase Auth users and create the one `groups` row + four `group_members` rows linking them.

## 3. Configure environment variables
```bash
cp .env.example .env
```
Fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from your Supabase project's **Settings → API** page. Only the **anon/public** key goes here — never the `service_role` key.

## 4. Run locally
```bash
npm run dev
```

## 5. Run tests / type-check / lint
```bash
npm run test    # vitest — financial engine + validation unit tests
npx tsc -b      # type-check
npx oxlint      # lint
```

## 6. Build for production
```bash
npm run build   # outputs to dist/
npm run preview # serve the production build locally to sanity-check it
```

## 7. Deploy (e.g. to Vercel)
1. Push this repository to GitHub (see note below — not done automatically).
2. Import the repo into Vercel.
3. Framework preset: **Vite**. Build command: `npm run build`. Output directory: `dist`.
4. Add the same two environment variables (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) in the Vercel project's Environment Variables settings.
5. Deploy.

> **Nothing above was done automatically on your behalf.** Creating a GitHub repository, creating a Supabase project, running migrations against a live database, and deploying to Vercel are all irreversible or externally-visible actions, so per the project's own ground rules they need your explicit go-ahead and your own credentials. Everything up to that line (code, schema, tests, docs) is fully prepared and ready.

## Project structure
See `docs/03-architecture.md` for the full breakdown. Short version: `src/lib/money.ts` is the entire financial engine (pure, unit-tested), `src/features/*` are the five screens, `src/lib/supabaseClient.ts` is the only place the Supabase client is created, and `supabase/migrations/*.sql` is the entire database + security model.

## Security notes
- The frontend only ever holds the **anon** key. All access control is enforced by Postgres Row Level Security (`supabase/migrations/0002_rls.sql`) — a user can only ever see rows for their own group, and the `service_role` key is never used by this app.
- There is no public sign-up; the four accounts are provisioned manually (see step 2 above).
