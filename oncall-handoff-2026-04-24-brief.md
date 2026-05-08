# On-Call Handoff Task Brief — 2026-04-24

## The Ask
Matt forgot to do the on-call handoff for his shift on **Friday 2026-04-24, 06:00–18:00 PT**. Walk through the standard IDLMP on-call handoff procedure for that day and produce:
1. A detailed triage doc saved to the vault at:
   `~/vaults/vault-one/3-resources/on-call-triage/triages/2026-04-24_oncall-handoff-summary.md`
2. A Slack-ready summary message to post in `#ci-idlm-oncall-handoff`.

## Context — Where Things Are

### Authoritative procedure (READ FIRST)
- `~/vaults/vault-one/3-resources/on-call-triage/idlmp-oncall-handoff-process.md`
  - Step-by-step process: PagerDuty Insights → Slack → Wavefront → Splunk → write & post
  - Includes "what NOT to include" rules, tone guidance, and investigation rigor

### Reference handoffs (style examples — match this tone)
- `~/vaults/vault-one/3-resources/on-call-triage/triages/2026-02-17_oncall-handoff-summary.md` — busy shift with 1 incident
- `~/vaults/vault-one/3-resources/on-call-triage/triages/2026-02-16_oncall-handoff-summary.md` — quiet shift with HPA scaling notes
- The "Slack-Formatted Summary (Ready to Post)" sections at the bottom of each show exactly the format Matt actually posts

### Prior session transcript
- `/Users/mpetters/code/nowplaying.nvim/handoffconvo.md` — the previous attempt; got blocked at data-collection because no live auth. Already identified procedure and references.

## Key URLs (must scrape these)
1. **PagerDuty Insights — Responder Report** (PRIMARY source of truth):
   `https://intuit.pagerduty.com/analytics/insights/responder-report/drilldown/y305udxKX8JTIhfWrrzfgw`
   - Filter date range to **2026-04-24**
   - Page through all rows; capture: time, title, service, TTA, response effort, resolution
2. **Slack web** (NOT desktop app — agent can't scrape desktop):
   `https://intuit-teams.slack.com`
   - Activity tab → filter to 6 AM – 6 PM PT on 4/24
   - Check channels: `#iip-metric`, `#iip-authz-metrics`, `#ci-idlm-oncall-handoff`, `#identity-support`, `#tmp-identity-api-onboarding-requests`
3. **IDLM On-Call Dashboards Google Doc** (per-service Wavefront/Splunk links):
   `https://docs.google.com/document/d/19tSjvVZ1fxFKgKtymXJo9PX8TrtC2E4BSBEV-Yrwy8g/edit?tab=t.0#heading=h.peo6fwtww9l0`
4. **Wavefront** (only if HPA/pod alerts surfaced):
   `https://intuit.wavefront.com/alerts`
5. **Splunk ASAA Season Dashboard**:
   `https://ip.adhoc.splunk.intuit.com/en-US/app/ilm_account/asaa_season_dashboard`

## Tools to use
- **Chrome DevTools MCP** for browser scraping (NOT claude-in-chrome). Matt must already be authenticated — confirm before scraping.
- **splunk-cli** for production log queries: `splunk-cli --config ~/.config/splunk-cli/config.json run --spl '<query>' --earliest -16h --limit 50`
  - Account service prod index: `ilm_account_prd`

## Order of operations
1. Open PagerDuty Insights Responder Report first — confirm Matt's auth, then collect ALL rows for 2026-04-24.
2. Open Slack web — Activity feed for the day, then check the alert + handoff channels.
3. Only open Wavefront pages for specific HPA/pod alerts you found in steps 1–2.
4. Splunk only if you need to verify a claim (don't fish).
5. Write the vault doc following the structure of the 2/17 reference.
6. Produce the Slack-ready post (terse — 1-line per alert, no shift times, no roster, no editorializing).

## Style rules (from procedure doc — IMPORTANT)
- **Title**: `IDLMP On-Call Handoff: Fri 4/24`
- **Overall**: one-liner ("Quiet shift", "8 PRD alerts, 1 incident", etc.)
- One line per alert: timestamp + name + value + threshold + outcome
- PRD and e2e in scope; **PRF out of scope** unless truly unusual
- Don't claim root cause without data — state what you observed
- Don't pad. Quiet shifts can be 1-2 lines total.
- For incidents: include the two CRs as inline links; skip RCA/PRB numbers in the Slack post

## Constraints
- **Do NOT delete or overwrite anything in the vault without asking Matt.**
- **Do NOT post to Slack** — produce the message text, let Matt post.
- If auth fails on any site, tell Matt immediately rather than retrying.

## Today's date
2026-04-25 (so "yesterday" = 2026-04-24, Friday)

## First step
Confirm Matt is authenticated in Chrome to PagerDuty + Slack web, then begin step 1 (PagerDuty Insights Responder Report).
