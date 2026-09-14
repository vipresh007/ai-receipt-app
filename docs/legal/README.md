# Legal documents

The canonical Privacy Policy and Terms of Service live in
[`web/content/legal/`](../../web/content/legal/) (`privacy.md`, `terms.md`) so
the web app can render them at `/privacy` and `/terms`.

They are **first drafts** and still need a lawyer's review before launch
(`docs/LAUNCH.md` §5).

**Filled in:** operator = **DATA EAVER INC.**; contact = contact@dataeaver.ca;
site = tally.dataeaver.ca (custom domain, bound to the deployed web app with a
managed TLS cert); hosting region = **East US 2** (corrected — the app is
actually deployed there, not Canada Central as an earlier draft assumed);
retention = 24 months (images) / 90 days (diagnostics); minimum age = 16;
governing law = Ontario, Canada; liability cap = CAD 100. No mailing address —
still omitted.

**Still to resolve:**

- Confirm **Ontario** as governing law actually matches where DATA EAVER INC.
  is incorporated/based — carried over from an earlier assumption, not yet
  confirmed against the switch to a company operator.
- Set the **"Last updated" date** on each file when you publish.
- Registered mailing address for the company, if you want one listed.
- **Apple Developer Program mismatch**: your Apple account is enrolled as an
  **Individual** (Vipresh Patel), not an Organization. For an App Store
  listing under DATA EAVER INC., Apple's own seller name shown to users would
  still read "Vipresh Patel" unless you upgrade to an Organization account
  (needs a D-U-N-S number). Not a blocker for dev/testing or for these
  documents, but worth resolving before an actual App Store submission so the
  named operator and the App Store seller agree.
