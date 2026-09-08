# 3.3 — International transfers and Transfer Impact Assessment

**Date:** 20 August 2026.
**Status:** Documented. Safeguards are **not** fully executed (see
[DPA.md](DPA.md)). The database has **not** been moved to an EU/UK region.

`PRIVACY.md` already tells the user that transfers happen and that we are
not inventing SCCs or DPF certification we have not put in place. This
file is the internal TIA.

## Transfer map

| Personal data | Exporter | Importer | Country | Adequacy? | Intended safeguard |
|---|---|---|---|---|---|
| Account, medicines, schedules, dose logs, contests, consents, profiles, care links, alerts, tokens | Doezly (India) / the user's device | Supabase | Singapore `ap-southeast-1` | No | Supabase DPA + EU SCCs (module controller-to-processor) + UK IDTA addendum |
| OCR text + transcript | The user's device | Anthropic | United States | No (unless DPF applies to that entity) | Anthropic DPA; DPF if the contracting entity is certified; else SCCs |
| FCM token + notification body | Supabase edge (`notify-care`) | Google FCM | United States | DPF for Google LLC if used | Cloud DPA; DPF |
| Google account email / name / id | The user's device | Google Sign-In | United States | DPF | Independent controller — Google's own transfers |
| Voice audio | The user's device | Google speech | United States | DPF | Independent controller — consent, not our SCCs |

India is the controller's establishment. EEA/UK users still get GDPR/UK
GDPR rights against this controller. Transfers *from* the EEA/UK are the
Art. 44 problem; transfers from India to Singapore/US are a disclosure we
still describe because EEA users' data ends up there.

## Option A — Recreate Supabase in an EU or UK region (preferred)

A region change is not a setting. It means a **new** project, new URL, new
anon key, new migrations, new edge functions, new Auth Google client
config, and a one-time cutover of any existing accounts.

Do this before launch if EEA/UK distribution is real. It removes the
Singapore transfer entirely. Google and Anthropic remain US transfers.

## Option B — Keep Singapore and paper the transfer

1. Execute the Supabase DPA (SCCs attached).
2. Complete this TIA (below) and keep it.
3. Do the same for Anthropic and Google Cloud.

This is slower to launch-honestly than Option A is to do while the dataset
is still tiny.

## Transfer Impact Assessment (working)

### Law and practice in the destination

- **Singapore.** PDPA, not EU adequacy. Government access exists under
  Singapore law. Supabase's DPA/SCCs are the contractual layer; they do
  not rewrite Singapore statute. Residual: lawful access to a hosted
  Postgres in Singapore cannot be ruled out.
- **United States.** FISA 702 / EO 12333 risk for data at US CSPs.
  Google is on the EU-US Data Privacy Framework. Anthropic: confirm the
  contracting entity's DPF status at execution; do not assume.

### Supplementary measures already in the product

- Encryption in transit (TLS). Cleartext forbidden by network security
  config.
- Encryption at rest on the phone (Keystore + sqlite3mc).
- Encryption at rest on Supabase is whatever the platform provides —
  confirm in their DPA/security page when executing.
- RLS so another account cannot read the row.
- Consents off by default so many users never send health data off-device.
- No analytics SDK, so there is no extra US advertising transfer.

### What supplementary measures we are *not* claiming

- We do not have customer-managed keys on the hosted Postgres that would
  make a lawful-access request return ciphertext we cannot decrypt for
  them. The operator can read the database with the password in
  `.secrets/db_password.txt`.
- Certificate pinning is not done (4.3f).
- We have not split the project so EU users land in an EU region.

### Decision

Until Option A is done or Option B's DPAs are executed, **do not market
Medicyn as having "GDPR-compliant transfers."** Tell the truth that
`PRIVACY.md` already tells. The residual risk is accepted in
[DPIA.md](DPIA.md) R7 for pre-launch work; it is not accepted as a
finished Art. 46 story.
