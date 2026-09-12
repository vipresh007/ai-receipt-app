# Privacy Policy

_Last updated: set this to the date you publish. This is a first draft — have it
reviewed by a lawyer before you rely on it._

This policy explains what **Tally** ("we", "us"), an app developed and
operated by **Vipresh Patel**, collects when you use the Tally app and
website, why, and what choices you have. Questions: **vipresh1993@gmail.com**.

## What we collect

**You give us**

- **Account details** — your name and email address, received from your sign-in
  provider (Google, Apple, or an email/password login) via Auth0 when you
  create an account.
- **Receipts you add** — the photo you capture or upload, and the details
  pulled from it or that you enter (merchant, date, amount, tax, category,
  line items, notes).

**Created as you use Tally**

- **Usage and diagnostics** — app version, device type, crash reports, and
  performance/error data, through Azure Application Insights. Used to keep the
  service working; not used to track you across other apps or sites.
- **Anti-abuse data** — for people using the app without an account, a random
  device identifier and a per-device / per-IP count of AI scans, to enforce
  the free limit. It is not linked to an identity.

We do **not** collect precise location, contacts, advertising identifiers, or
health/financial-institution data, and we do not use tracking technologies for
advertising.

## How we use it

- Provide the core feature: read your receipt with AI and keep your expenses,
  dashboard, and month-to-month views.
- Sync your data across your devices and the web app when you are signed in.
- Keep the service secure and reliable (rate limiting, debugging, fraud
  prevention).
- Communicate with you about the service (e.g. security or account notices).

**Legal bases** (where GDPR/UK GDPR applies): performance of our contract with
you (providing the app), our legitimate interests (security, improving the
service), and your consent where required.

## AI processing

When you scan a receipt, the image and any on-device OCR text are sent to
**Azure OpenAI** (Microsoft) to extract the structured fields. Per Microsoft's
terms for the Azure OpenAI Service, your prompts and outputs are **not** used to
train the models and are not shared with OpenAI. The image is processed to
return the extracted data; we then store it as described below.

## Where your data is stored

Your account and receipts are stored in Microsoft Azure, in the **Canada
Central** region _(confirm this is where you'll actually host production)_:
PostgreSQL for records and Azure Blob Storage for receipt images. Some
processing by our providers (below) may occur in other regions.

## Sharing

We do not sell your personal data. We share it only with service providers who
process it on our behalf under contract:

| Provider | Purpose |
|---|---|
| Microsoft Azure (incl. Azure OpenAI, PostgreSQL, Blob Storage, Application Insights) | Hosting, database, image storage, AI extraction, diagnostics |
| Auth0 (Okta) | Sign-in and session management |
| Google / Apple | Only if you choose their sign-in button |

We may also disclose data if required by law, or to protect our rights, users,
or the public.

## Retention

- **Account data and receipts** are kept until you delete them or delete your
  account.
- **Receipt images** are additionally removed automatically after **24 months**.
- **Diagnostics** are retained by Application Insights for **90 days**.
- **Anti-abuse counters** age out within hours to days.

## Your choices and rights

- **Access / export** — email us and we will provide a copy of your account
  data.
- **Correct** — edit any receipt in the app; contact us to change account
  details.
- **Delete** — delete individual receipts in the app, or delete your entire
  account and its data from **Account → Delete account** (app and web). This is
  immediate and irreversible.
- Depending on where you live you may also have rights to restrict or object to
  processing, to data portability, and to lodge a complaint with your privacy
  regulator (in Canada, the Office of the Privacy Commissioner).

To exercise a right, email **vipresh1993@gmail.com**.

## Children

Tally is not directed to children under **16** and we do not knowingly collect
their data.

## Security

Data is encrypted in transit (HTTPS) and at rest by Azure. Access to production
systems is limited. No system is perfectly secure; please use a strong, unique
password or a trusted sign-in provider.

## Changes

We may update this policy; we will change the "Last updated" date and, for
material changes, notify you in the app or by email.

## Contact

**Vipresh Patel** — **vipresh1993@gmail.com**
