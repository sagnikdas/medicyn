# Dosely — Monetization plan

How this app makes money, and in what order. Written for a product with
**zero customers and zero awareness**. That fact is the plan: pricing is
not the first problem. Being used by even twenty real families is.

**Last updated:** 2026-08-20 · assumes `PLAN.md` (Care Link, Android-only,
one caregiver per parent) and `COMPLIANCE.md` (HIPAA does not apply;
GDPR / FTC / Play Health do).

---

## The one-sentence strategy

Ship a free, trustworthy reminder that a parent will actually keep on
their phone. Charge the adult child in another city for the peace of
mind of being linked to it. Do not charge anyone until a few dozen
families have used that link for weeks without being asked to pay.

---

## Locked decisions

These are settled for the same reason the Care Link decisions in
`PLAN.md` are settled: reversing them later is expensive, and most of
the tempting alternatives are traps.

| Decision | Choice | Why |
|---|---|---|
| Who pays | **The caregiver.** Never the parent. | The child has the card, the anxiety, and the job of installing the app. A paywall on an elderly phone is how the pair never forms. |
| What is free forever | **Local reminders.** Scan, speak, save, alarm. Offline. No account required. | This is how the parent keeps the app. If the reminder is the paid bit, they uninstall, and the care link has nothing to attach to. |
| What is paid | **The care pair** — missed-dose alerts, setup health, remote edit, call-from-alert. | That is the product a working adult will open their wallet for. Scanning a label is a five-minute convenience; knowing Amma missed her 9am pill is the ongoing job. |
| Ads / data | **Never.** No ad SDK, no sale of health data, no "sponsored" pharmacy. | `PRIVACY.md` already promises this, Play Health and GDPR punish it, and one leak ends the trust the care link is made of. |
| Clinics / payers | **Not now.** Consumer families only. | A B2B deal with a clinic, home-health agency, or insurer makes Dosely a HIPAA Business Associate (`COMPLIANCE.md`). That is a different company. |
| When to charge | **After evidence, not at launch.** First public version is free. | There is no one to convert. A price on day one is a hypothesis you cannot test, and it will suppress the only signal that matters: do pairs form and stay. |
| Currency of the first paid plan | **Annual, caregiver-paid, one pair.** | Monthly is churn theatre for a product used in the background. Annual matches "I am responsible for my parent this year." |
| Early users | **Grandfathered free for at least a year** after paid launches. | The first fifty families are the sales force. Taxing them for the privilege is how word of mouth dies. |

Revisit these deliberately, not because a competitor has a free trial
banner.

---

## Who the customer is

Two people, one purchase.

**The user** is the parent. They photograph a strip, say "one in the
morning and one at night," tap Taken. They will not search Play for
this. They will not enter a card. They will abandon anything that
looks like a bill, a login maze, or a lecture.

**The customer** is the adult child in another city — often the same
person `PLAN.md` already says the Play listing should be written to.
They discovered the app, they installed it on both phones, they typed
the invite code. They are the one who lies awake. They will pay ₹999
or $49 a year to stop wondering.

That split is the whole business. Medisafe, CareZone, and every
"medication tracker" that put the paywall on the patient's phone
learned this the hard way: the person who needs the reminder is the
person least willing and least able to subscribe.

A third person exists and is not a customer yet: a sibling. The
product forbids that on purpose (one caregiver per parent). When
sibling sharing ships, it is a family plan, still paid by one adult,
not a second subscription stacked on the parent.

---

## What not to sell

Each of these looks like revenue. Each one either breaks the product
or pulls you under a statute you are not staffed for.

- **Ads.** Health inventory is cheap because nobody reputable wants
  it, and the reputable ones will not sit next to a missed-dose
  alert. An SDK that fingerprints the device also contradicts the
  "no advertising identifiers" line in `PRIVACY.md`.
- **Lead-gen to pharmacies or insurers.** That is selling health data
  with extra steps. Washington MHMD and the FTC Health Breach rule
  treat unauthorised disclosure as a breach. Do not.
- **Locking the AI scan behind a paywall.** The scan is how setup
  succeeds. Setup failure is how the parent never uses the app. The
  40-parses-per-day cap in `parse-medicine` is a cost fuse, not a
  pricing page. Leave it that way. A paying caregiver does not need
  more scans; they need the link to work.
- **Locking reminders or history.** Same reason. The free tier has
  to be a complete pill reminder, or the parent will use the clock
  app and the care link has no feed.
- **Selling into clinics, hospitals, or "RPM reimbursement."** That
  is the HIPAA tripwire. It also means sales cycles, BAAs, and a
  security questionnaire you will fail until Phase 4 of
  `COMPLIANCE.md` is done. Skip it until a consumer business exists.
- **Lifetime licences at a fire-sale price.** You will regret the
  support load and you cannot raise the price on the people who
  actually like you.
- **In-app coins, streaks-as-premium, extra "themes."** This is a
  care tool. Gimmicks tell the caregiver you are not serious.

---

## The product that can be charged for

Map every paid feature to a job the caregiver already has. If a
feature only delights the person building it, it stays free or it
stays unbuilt.

| Caregiver job | Free | Paid (Care+) |
|---|---|---|
| Get the parent onto a reminder | Full local app, including AI scan | — |
| See that a dose was taken | — | Shared feed (already the Care Link) |
| Know a dose was missed in time to act | — | Push alert to the child's phone |
| Trust the parent's phone is even ringing | — | Setup-health panel (`PLAN.md` Phase 2) |
| Change a schedule without flying home | — | Caregiver-side edit + silent re-arm |
| Call when an alert lands | — | One-tap call from the missed-dose alert (`PLAN.md` Phase 3) |
| Not confuse "no alert" with "all well" | — | Silent-device detection (`PLAN.md` Phase 3) |
| Not run out of tablets | Optional later, still useful free | Refill warning as a Care+ extra once it exists |
| Share with a sibling | Impossible today | Family plan, later — one household, extra seats |

The free app is a complete reminder. Care+ is the remote. That is
the sentence on the Play listing and on the paywall, when there is
one.

Do not charge for Google sign-in, cloud backup of the parent's own
data, or the invite/confirm flow itself. Charging to *form* the pair
means the pair never forms. Charge to *keep* the remote features
after a trial.

---

## Price

Set in the child's currency, not the parent's. Two SKUs, same
product. Launch with one of them if billing is painful; keep the
other in reserve.

| Market | Monthly (discouraged) | Annual (default) | Who it is for |
|---|---|---|---|
| India | ₹99 | **₹999 / year** | Child in a metro, parent in the same country |
| US / UK / EU / Gulf (diaspora) | $4.99 | **$39–49 / year** | Child abroad, parent in India — the wedge |

Why those numbers:

- Cheap enough to be a "stop arguing with myself" purchase, not a
  family meeting.
- Expensive enough that you are not training people to expect a
  utility for free once the value is obvious.
- Annual is ~2 months free versus monthly, which is the only
  discount worth offering.
- Google Play Billing takes 15% on subscriptions after the first
  year (12% in some programmes). ₹999 net is about ₹850; $49 net is
  about $42. That has to cover Claude parses, Supabase, and you.

**Trial:** 30 days of Care+ the moment a pair is confirmed, no card
up front if Play lets you do that cleanly; otherwise a card-up-front
trial. The trial starts at *confirm*, not at install. Installing is
not the aha. The first missed-dose alert that reaches the child's
phone is.

**Who is billed:** the Google account that claimed the invite — the
caregiver. If they disconnect, Care+ seats go with them. The parent
never sees a restore-purchase sheet.

**Family plan (later):** one annual price, up to three caregivers on
one parent, still one payer. Do not invent this until sibling
sharing exists in the product. Selling a seat the app cannot honour
is fraud.

**Do not localise the India price upward to match USD.** A
Bengaluru software engineer and a Dallas software engineer can both
pay $49; a Pune accountant paying for a parent in Siliguri cannot.
Two SKUs, store-detected, is enough.

---

## Unit economics (so you know when the price is wrong)

Costs that actually move, at today's architecture:

| Cost | Shape | Notes |
|---|---|---|
| Claude via `parse-medicine` | Per scan, bursty at setup | Real setup is a handful of scans. The 40 / 24h cap is already the worst-case fuse. A typical pair should cost cents per month in AI after week one. |
| Supabase | Nearly flat until you have thousands of pairs | Auth + Postgres + edge functions. Stay on the free/pro tier until it hurts. Do not "scale the database" as a reason to raise prices. |
| FCM | Free | Do not build a second push vendor to save money you are not spending. |
| Play Billing | 15% (ongoing subs) | Price gross; think net. |
| Support | Your time, linear in confused caregivers | This will exceed cloud spend until ~1,000 pairs. Write the setup-health panel before you hire anyone. |
| Compliance | Step-function | GDPR / Play work in `COMPLIANCE.md` is the cost of *being allowed to charge in the EU*. Budget it as a launch cost, not a COGS line. |

A Care+ pair at ₹999 or $49 / year is wildly positive on infrastructure
as long as you do not: (a) let the parse quota become a botnet, which
you already prevented, or (b) put a human in the loop for every
missed dose. Dosely is a signal, not a call centre. The moment you
offer "we will phone your mother for you," the unit economics die
and you have become a home-health agency.

If AI cost per pair-month ever exceeds ~10% of revenue, cut model
spend (smaller model, cache, on-device for repeats) — do not raise
the price. The price is set by the child's anxiety, not by tokens.

---

## The real problem: nobody knows this exists

A monetization plan that starts with Stripe is a plan for a product
people already want. You do not have that. Sequence:

### 0. Be allowed to exist

`PLAN.md` Phase 4 is the gate. No Play listing, no privacy URL, no
closed testing, no customers. Closed testing is calendar time, so
start it the moment the build is sound and let it run while Care
Link work continues. The listing copy is written to the child, in
their language, with the job in the first line: *Know if they missed
a dose, even if you are in another city.*

Do not spend a rupee on ads before the listing is live and the pair
flow survives a stranger's two phones.

### 1. Twenty families you can telephone

Before public launch, the customers are people who will tell you the
truth.

- Your own relatives, then theirs.
- Two WhatsApp groups of adult children (college batch, housing
  society, "NRI parents" groups). Personal ask, not a blast.
- One rule: you watch them install. You do not send an APK and hope.
  The failure mode is always setup (Play permissions, OEM battery
  killers, the parent tapping the wrong Google account). `PLAN.md`
  already names this. Your first "sales" motion is sitting on a
  video call until both alarms fire.

Success looks like: **10 confirmed pairs that still exist after 14
days**, and at least a few missed-dose alerts that the child says
were useful rather than noisy. If you cannot get to ten, the
product is not ready to be priced. If you can, you have a script
for everyone else.

### 2. The wedge: the child who does not live in the same house

Do not market "a better pill reminder." Those apps are a graveyard
and the parent already has a box on the fridge. Market the
specific situation the Care Link was designed for:

- Adult child in Bengaluru / Mumbai / Delhi, parent in a smaller
  city.
- Adult child in the US / UK / UAE, parent in India. WhatsApp is
  how they already care; Dosely is the one thing WhatsApp cannot
  do — a missed 9am tablet at 9:31.

Channels that match that, in order of cost (all near-zero at first):

1. **WhatsApp.** You, then the twenty families, then a short clip
   of the child's phone lighting up. No growth hack. A forwarded
   note from a real son beats a landing page.
2. **Play Store SEO.** Title and first line must contain the job
   ("medicine reminder for parents" / "missed dose alert for
   family"), not the brand story.
3. **One explainer page.** Host the privacy policy there anyway
   (Play requires a URL). Add three screenshots and an install
   link. That is the site. Do not build a marketing app.
4. **Communities with the job already.** Local "parents of aging
   parents" groups, NRI forums, resident-welfare associations,
   diabetes/hypertension support groups — as a *person recommending
   a tool*, not as a brand account. Health groups will ban anything
   that smells like an ad; that is a feature.
5. **iOS, later.** Many caregivers have iPhones while the parent
   has Android. A caregiver-only iOS client (feed + alerts + edit,
   no local alarms required) unlocks pairs you currently lose at
   "I don't have an Android." It is a distribution feature more
   than a product one. Do it after the Android pair is proven,
   not before.

Paid ads (Play, Meta, Google) wait until you can state a number:
cost to get a *confirmed pair that lasts 14 days*. Installs are a
vanity metric here. Unpaid installs by parents who never link are
a cost, not a funnel.

### 3. What you measure instead of revenue, until there is revenue

If you only watch downloads you will optimize the wrong app.

| Metric | Why it is the business |
|---|---|
| Confirmed pairs / week | The only install that can ever pay. |
| Pair survival at day 14 and day 60 | Did the parent keep the app, and did the child still care. |
| Time from invite to confirm | Friction in the only flow that matters. |
| Missed-dose alerts per pair per week, and **useful** vs **cry-wolf** (ask) | Too many and they mute you; too few and they churn. |
| Setup-health failures (exact alarm denied, battery killing the app) | Silent failure looks like "the app doesn't work." |
| Caregiver returning to the feed without an alert | Habit, not just panic. |
| Support questions per new pair | Your real COGS. |

Instrument these as soon as the first twenty families exist, even
if it is a spreadsheet you update by hand. Do not add an analytics
SDK that identifies the parent in order to learn this. Counts and
funnels, not dossiers. `PRIVACY.md` has to stay true.

---

## When money actually starts

Three phases. Do not skip, and do not rename Phase A as "launch."

### Phase A — Free, on purpose (now → first ~50 pairs)

- Public Play listing, still ₹0.
- Care Link fully free, including push.
- You are buying learning with your Anthropic bill and your time.
- Grandfather every account created in this phase as *Founding
  family* — Care+ for free for 12 months after Phase C, no card.
- Goal: 50 confirmed pairs or 90 days of public listing, whichever
  is later. Exit only if pair survival at day 14 is something you
  would show a stranger.

Work that makes Phase C possible, and that you should do anyway:
caregiver-side edit, setup-health panel, call button, silent-device
detection. Those are the paid features. Shipping them free first is
how you find out which ones people notice.

### Phase B — Soft ask (the next ~100–200 pairs)

- Still free.
- In the caregiver's feed, after they have received a real missed
  dose alert: a single, dismissible note that a paid plan is coming,
  that they will be grandfathered, and that you want to know what
  they would pay. A Google Form is enough.
- No banner on the parent's phone. Ever.
- Goal: ten written replies that mention a number. If everyone says
  they would not pay, believe them and stay free longer — the
  product is not yet the remote they hoped for.

### Phase C — Care+ exists

- Play Billing subscription, annual default, prices as above.
- New pairs: 30 days of Care+ at confirm, then the remote features
  need a subscription. The parent's reminder **does not change**
  when the child lets the trial lapse. The feed on the child's
  phone stops updating live; the alarms on the parent's phone keep
  firing. That is the only honest downgrade. Punishing the parent
  for the child's lapsed card is how you get a one-star review from
  the person who cannot leave.
- Founding families remain free through their grandfather window.
- You now have a number: paid conversions / confirmed pairs, and
  60-day retention of payers.

A rough picture, not a forecast — you have no conversion data, so
treat this as scale, not a promise:

| Confirmed pairs | If 10% pay (early, harsh) | If 25% pay (product is loved) |
|---|---|---|
| 200 | ~20 × $40 ≈ $800 / year | ~50 × $40 ≈ $2,000 / year |
| 1,000 | ~$4,000 / year | ~$10,000 / year |
| 10,000 | ~$40,000 / year | ~$100,000 / year |

Those are "pays the cloud and some of your time" numbers until the
top row is no longer imaginary. They are also why this is a
bootstrap business, not a venture one, until sibling sharing, iOS,
and a second geography exist. That is fine. A durable ₹999
subscription used by people who mean it is a better company than a
growth story that has to sell clinic seats.

---

## Distribution offers that are not ads

Once Phase C exists, these are legitimate. Before that they are a
distraction.

- **Gift Care+.** The child in Dallas buys a year for the sibling
  in Pune who is the one actually on the ground. Same SKU, Play's
  gift / code path if you can stand up codes; otherwise a
  redemption string you issue by email. This matches how Indian
  families already pay for each other's Netflix.
- **Doctor or chemist as *recommender*, not customer.** A GP who
  says "put this on her phone" is distribution. A clinic that wants
  a dashboard of fifty patients is HIPAA. Give the GP a one-pager
  and a Play link. Do not give them a login.
- **Employer EAP / NRI benefits, much later.** Only after you can
  invoice a company without becoming a medical device. A "parent
  care" perk at an IT employer is plausible; it is also how you
  accidentally sign a BAA. Lawyers before logos.

---

## What "good" looks like in twelve months

Not a valuation. A state of the product.

- Closed testing finished; public listing live; privacy URL and
  account-deletion URL both work.
- At least fifty confirmed pairs you did not personally babysit
  through install.
- Day-14 pair survival you would defend.
- Setup-health visible to the caregiver, so "no alert" is no longer
  a lie.
- A written price, even if it is not charged yet, that ten
  caregivers did not laugh at.
- No ad SDK, no clinic contract, no HIPAA programme pretending to
  be a GTM motion.
- You still know the names of the first twenty families.

If those are true, Care+ is an implementation task (Play Billing,
entitlements on `care_links`, the honest downgrade). If they are
not, charging will not fix them.

---

## Open questions

Answer these when Phase C is close, not in the abstract.

- **Play Billing vs a web checkout.** Play will force IAP for
  digital features inside the app. Use it. A website that sells the
  same subscription is extra surface (tax, VAT, chargebacks) you
  do not need at fifty payers.
- **Whether a lapsed Care+ child can still *see* yesterday's feed.**
  Read-only history is generous and probably right; live alerts are
  the paid nerve. Decide before the first expiry.
- **India GST and Play's price template.** Set the India SKU so the
  parent-facing number is the one in this document, tax-inclusive.
- **A caregiver who is also a parent in a different pair.** The
  product forbids this today. If that changes, entitlements are
  per pair, not per Google account, or one subscription would cover
  two households by accident.
- **Whether refill tracking is free.** It helps the parent as much
  as the child. Default free; promote it inside Care+ if it is what
  people quote when they pay.

---

## Conventions worth keeping

- The parent's phone is not a checkout. If a screen has a price on
  it, you are looking at the wrong phone.
- Free is complete. Paid is remote. Repeat that until the Play
  listing writes itself.
- The first fifty families are not a cohort to convert. They are
  the reason anyone else hears of this.
- A clinic that wants a demo is a compliance event, not a pipeline
  event. Read `COMPLIANCE.md` before you say yes.
- Do not add a pricing page to the app during Phase A. It will
  leak into screenshots and you will spend the year explaining a
  price you are not charging.
