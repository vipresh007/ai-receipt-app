# Legal documents

The canonical Privacy Policy and Terms of Service live in
[`web/content/legal/`](../../web/content/legal/) (`privacy.md`, `terms.md`) so
the web app can render them at `/privacy` and `/terms`.

**Reviewed and accepted as final by DATA EAVER INC. (Vipresh Patel), 2026-09-18**
— not run past outside legal counsel; that risk is knowingly accepted rather
than deferred. Revisit if the business materially changes (new jurisdictions,
paid plans, EU users at scale, etc.).

**Filled in:** operator = **DATA EAVER INC.**; contact = contact@dataeaver.ca;
site = tally.dataeaver.ca (custom domain, bound to the deployed web app with a
managed TLS cert); hosting region = **East US 2** (corrected — the app is
actually deployed there, not Canada Central as an earlier draft assumed);
retention = 24 months (images) / 90 days (diagnostics); minimum age = 16;
governing law = Ontario, Canada; liability cap = CAD 100. No mailing address —
still omitted.

**Known, accepted gaps (not blocking — revisit only if they become real problems):**

- **Ontario** as governing law is carried over from an earlier assumption, not
  independently confirmed against where DATA EAVER INC. is incorporated/based.
- No registered mailing address for the company is listed.
- **Apple Developer Program seller name**: converting from Individual
  (Vipresh Patel) to Organization (DATA EAVER INC.) is in progress — see
  `docs/LAUNCH.md` §1/§5. Apple's own "Convert to Organization" migration
  preserves the existing Team ID / app / TestFlight setup (it's a status
  change, not a new enrollment), but needs a D-U-N-S number + Tax ID for the
  company and Apple's own verification turnaround (days, not instant).
