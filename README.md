### [Practice BR](https://github.com/DaisyOli/Practice-BR)

[![English](https://img.shields.io/badge/English-0969DA)](README.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-8B949E)](README.fr.md)

[![CI](https://github.com/DaisyOli/practice-br/actions/workflows/ci.yml/badge.svg)](https://github.com/DaisyOli/practice-br/actions/workflows/ci.yml)

An AI-powered platform where Portuguese language teachers create interactive exercises and students practice with instant, personalized feedback. Built for the professional-training market too: learners funded through France's OPCO / CPF schemes get tracked practice hours and printable training attestations.

Live in private beta at [app.practicebr.com](https://app.practicebr.com), with real teachers and students testing it. Built and shipped solo — from first commit to production on Heroku — as my first Rails project after the Le Wagon bootcamp, and evolved well beyond it since.

---

## What it does

**For teachers:**
- Create activities in minutes — or let AI do the heavy lifting:
  - **Generate a full activity from a text prompt** (statement, explanation and questions), powered by Claude — runs as a background job with a friendly animated wait screen, so the teacher is never stuck on a blocked request
  - **Generate an activity from a YouTube video**: the transcript is fetched and turned into comprehension questions
- Six exercise types: multiple choice, fill-in-the-blank, open-ended, sentence ordering, paragraph ordering and column matching
- Review AI-generated drafts before publishing — the AI proposes, the teacher decides
- Invite students by email — each student is scoped to their teacher
- Dashboard with per-level (CEFR A1–C1) and per-competency breakdowns, pending corrections and student activity

**For students:**
- Practice activities filtered by level and competency — listening (CO), reading (CE) and writing (EE)
- Instant scoring with per-question feedback; multiple-choice alternatives are shuffled on every attempt to avoid position bias
- **Open-ended answers graded by AI**, with constructive feedback written in Portuguese — grading rigor scales with CEFR level, from lenient at A1 to demanding at C1
- **Answer by voice**: audio recordings are transcribed with Whisper
- Progress dashboard with competency tracking, search and activity ratings
- Installable as a PWA, with web push notifications for new activities

**For professionally-funded learners (OPCO / eCPF):**
- In France, language training is often paid for by professional-training funds — the employer's OPCO or the learner's personal training account (CPF). Funders require proof that the training actually happened, and being able to produce it is what lets a teacher take on funded students at all
- Teachers tag a student as OPCO or eCPF right on the invitation email; a dedicated badge then follows the student across the teacher's dashboard and the student's own profile
- One click generates a **printable training attestation** per student, with hours computed from tracked practice time — from opening an activity to submitting it — rather than self-reported

**Under the hood:**
- Trial-to-subscription onboarding with Stripe (checkout + webhooks)
- Weekly reminder emails (Resend + GoodJob cron), and a daily curation agent that proposes one activity theme for the teacher to review
- **Portuguese-only interface, by design** — immersion while practising. The learner's own language (FR / EN / PT) is reserved for everything that happens *outside* the app: emails, the privacy policy, end-of-trial and billing. Those are the moments where understanding must not depend on effort

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Backend | Ruby 3.3.5, Rails 7.1 |
| Database | PostgreSQL |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS + DaisyUI |
| AI | Anthropic Claude — Opus for activity generation, Haiku for grading; OpenAI Whisper (speech-to-text) |
| Background jobs | GoodJob (Postgres-backed, async mode) |
| Auth | Devise + Devise Invitable |
| Payments | Stripe subscriptions + webhooks |
| Media & email | Cloudinary, Unsplash, YouTube Data API, Resend |
| Tests & CI | RSpec, FactoryBot, SimpleCov, GitHub Actions |
| Deploy | Heroku (with PWA + web push in production) |
| Monitoring | Sentry (EU region, errors only — no tracing, no logs) |

---

## Architecture notes

- **Service objects** keep controllers thin: quiz submission and AI grading, activity generation (prompt- and video-based), transcription, push notifications and analytics each live in their own service under `app/services`.
- **Both AI pipelines run in background jobs** (GoodJob, backed by Postgres — no Redis): activity generation and answer grading are queued instead of blocking the request, with retry + graceful degradation when the AI is unavailable, and the UI updates itself via a polling Stimulus controller instead of a page refresh.
- **Cost-aware model selection**: Claude Opus generates activities — low volume, quality-critical, guided by a grading rubric baked into the system prompt — while Claude Haiku grades student answers, which run at much higher volume. Same pipeline, different model for the economics of each job.
- **A curation agent, not a prompt wrapper**: the daily suggestion agent runs a real tool-use loop — it queries the activity catalogue, student ratings and quiz performance *before* proposing a theme, instead of inventing one in a vacuum. The research tools are allowed to answer *"not enough data yet"*, and the system prompt requires the agent to accept that rather than force a conclusion. The loop is capped, refusals are handled, and the answer arrives through a terminal `propose_suggestion` tool instead of being parsed out of prose. Nothing it proposes reaches a student: it writes a `pending` suggestion for the teacher to approve, and refuses to produce a second one while the first is unreviewed.
- **Server-rendered UI with Hotwire** — no SPA, no API layer to maintain; Turbo handles interactivity.
- **Role-based access** (admin / teacher / student / trial) enforced at controller level, with students scoped to the teacher who invited them.
- **Graceful degradation**: AI, YouTube and Unsplash integrations are optional — the platform works without their API keys.
- **Privacy engineering across two legal regimes (GDPR + LGPD)**: no third-party CDNs — fonts, icons and libraries are self-hosted, so no visitor IP reaches an outside company before consent, which is also what removes the need for a cookie banner; personal data is kept out of production logs; AI grading receives only the answer text, never a name or an email. The privacy policy is selected server-side from `Accept-Language` in three versions that are *not* translations of each other: FR and EN follow the GDPR, PT follows Brazil's LGPD, and the two diverge on response deadlines, the list of data subject rights, the right to human review of an automated decision, and the age at which someone counts as a minor. The decisions, the rules that keep them from regressing, and the still-open items — data export, one-click account deletion, retention policy — are tracked in [`docs/PROTECAO_DE_DADOS.md`](docs/PROTECAO_DE_DADOS.md). No new subprocessor reaches production before it is written into three places: the policy tables, the Article 30 record ([`docs/REGISTRE_DES_TRAITEMENTS.md`](docs/REGISTRE_DES_TRAITEMENTS.md)) and the DPA table — and a test fails if it is missing from any of them, because a compliance document that goes stale doesn't break anything, it just quietly starts lying.
- **Error reporting that doesn't undo the privacy work**: production errors go to Sentry, pinned to its **EU region** so error data is stored inside the Union. The integration is inert unless `SENTRY_DSN` is set — development and test never phone home, and production can be switched off without a deploy. Personal data is stripped in three layers: default PII off (no IP, no cookies, no request body), the app's existing log parameter filters reused rather than a second list for someone to forget, and a final pass over the exception *text*, where an email can sit inside a sentence beyond the reach of any parameter filter. Performance tracing is deliberately off, and `traces_sample_rate` is `nil` rather than `0.0` — `0.0` is a *valid* rate, so the SDK still registers every Rails instrumentation subscriber and patches `ActiveSupport::Notifications` before discarding 100% of the samples: the full cost for none of the data, on a dyno whose 512 MB are already shared with the job runner.

## Technical roadmap

Things I know need work, in priority order:

- [x] Move AI grading calls out of the request cycle into background jobs (GoodJob + async UI updates)
- [x] Move AI activity generation out of the request cycle too (background job + async UI updates)
- [x] Finish migrating the remaining Bootstrap views to Tailwind/DaisyUI
- [x] Consolidate the repetitive `clear_*` controller actions into a single parameterized action
- [ ] Raise request-spec coverage on the billing and quiz-submission flows
- [ ] Extract multiple-choice and fill-in-the-blank into their own models — right now they're fields on `Question`, unlike the other four exercise types, which each have their own model. Deliberately deferred: the quiz flow is the app's most critical path, so this waits for a dedicated, carefully planned sprint

---

## Running locally

**Prerequisites:** Ruby 3.3.5, PostgreSQL, Bundler, Yarn

```bash
git clone https://github.com/DaisyOli/practice-br.git
cd practice-br

bundle install
yarn install

# Set up the database
bin/rails db:create db:migrate db:seed

# Start the server + Tailwind watcher
bin/dev
```

Open `http://localhost:3000` in your browser.

**Environment variables** — create a `.env` file at the project root:

```
DB_USERNAME=your_postgres_username
DB_PASSWORD=your_postgres_password
```

Optional keys unlock the integrations: `ANTHROPIC_API_KEY` (AI generation and grading), `OPENAI_API_KEY` (voice answers), `STRIPE_SECRET_KEY`, `YOUTUBE_API_KEY`, `UNSPLASH_ACCESS_KEY`.

## Running tests

```bash
bundle exec rspec
```

The suite also runs on every push via GitHub Actions.
