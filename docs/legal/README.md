# Legal documents

The canonical Privacy Policy and Terms of Service live in
[`web/content/legal/`](../../web/content/legal/) (`privacy.md`, `terms.md`) so
the web app can render them at `/privacy` and `/terms`.

They are **first drafts** and still need a lawyer's review before launch
(`docs/LAUNCH.md` §5).

**Filled in:** operator = Vipresh Patel, publishing as an individual (no
company); hosting region = Canada Central; retention = 24 months (images) /
90 days (diagnostics); minimum age = 16; governing law = Ontario, Canada;
liability cap = CAD 100. No mailing address — omitted by choice, which is
common for an individual-published app.

**Still to resolve — genuinely blocking before you go live:**

- **`[CONTACT EMAIL]`** — every "how do I exercise my rights / contact you"
  line currently has no address behind it. This isn't just a nice-to-have:
  Apple requires a support contact in App Store Connect at submission, and a
  privacy policy with no way to reach you is close to meaningless. Doesn't need
  to be fancy — a personal address or a free one made just for this is fine;
  swap in the domain-based one later if you get one.
- Confirm **Ontario / Canada Central** actually match where you're based and
  where you'll host — both were carried over from an earlier assumption.
- Set the **"Last updated" date** on each file when you publish.
