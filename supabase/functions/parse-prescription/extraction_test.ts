import { assertEquals } from "@std/assert";
import { isClockTime, isIsoDate, sanitiseExtraction } from "./extraction.ts";

// The tool's input_schema bounds these fields, but a schema is guidance to
// the model rather than a validator the API enforces — so before this, the
// model's output was returned verbatim to a device that arms medication
// alarms from it. The input is attacker-influenceable: whatever was
// photographed or in the uploaded PDF.

Deno.test("isClockTime accepts real times", () => {
  assertEquals(isClockTime("09:05"), true);
  assertEquals(isClockTime("9:05"), true);
  assertEquals(isClockTime("00:00"), true);
  assertEquals(isClockTime("23:59"), true);
});

Deno.test("isClockTime rejects what the schema pattern would have let through", () => {
  assertEquals(isClockTime("29:00"), false);
  assertEquals(isClockTime("24:00"), false);
});

Deno.test("isClockTime rejects non-times", () => {
  assertEquals(isClockTime("9am"), false);
  assertEquals(isClockTime("0900"), false);
  assertEquals(isClockTime(""), false);
  assertEquals(isClockTime(9), false);
  assertEquals(isClockTime(null), false);
});

Deno.test("isIsoDate accepts real calendar dates", () => {
  assertEquals(isIsoDate("2026-09-09"), true);
  assertEquals(isIsoDate("2026-01-01"), true);
  assertEquals(isIsoDate("2026-12-31"), true);
  assertEquals(isIsoDate("2024-02-29"), true); // leap year
});

Deno.test("isIsoDate rejects out-of-range or malformed dates", () => {
  assertEquals(isIsoDate("2026-13-01"), false); // month 13
  assertEquals(isIsoDate("2026-02-30"), false); // Feb never has 30 days
  assertEquals(isIsoDate("2026-04-31"), false); // April has 30 days
  assertEquals(isIsoDate("2026-00-10"), false); // month 0
  assertEquals(isIsoDate("09/09/2026"), false);
  assertEquals(isIsoDate(""), false);
  assertEquals(isIsoDate(null), false);
  assertEquals(isIsoDate(20260909), false);
});

// --- medicines[] parity with parse-medicine's own suite -------------------

Deno.test("sanitiseExtraction keeps a well-formed medicine intact", () => {
  const out = sanitiseExtraction({
    medicines: [{
      drugName: "Metformin",
      frequencyType: "specific_days",
      times: ["08:00", "20:00"],
      daysOfWeek: [1, 3, 5],
      confidence: 0.9,
    }],
    careItems: [],
  });
  const medicines = out.medicines as Record<string, unknown>[];
  assertEquals(medicines.length, 1);
  assertEquals(medicines[0].times, ["08:00", "20:00"]);
  assertEquals(medicines[0].daysOfWeek, [1, 3, 5]);
  assertEquals(medicines[0].frequencyType, "specific_days");
  assertEquals(medicines[0].confidence, 0.9);
});

Deno.test("sanitiseExtraction drops a day a medicine could not schedule, sorted and deduplicated", () => {
  const out = sanitiseExtraction({ medicines: [{ daysOfWeek: [5, 9, 1, 5] }], careItems: [] });
  const medicines = out.medicines as Record<string, unknown>[];
  assertEquals(medicines[0].daysOfWeek, [1, 5]);
});

Deno.test("sanitiseExtraction discards an out-of-range interval on a medicine", () => {
  const out = sanitiseExtraction({ medicines: [{ intervalHours: 0 }, { intervalHours: 8 }], careItems: [] });
  const medicines = out.medicines as Record<string, unknown>[];
  assertEquals(medicines[0].intervalHours, undefined);
  assertEquals(medicines[1].intervalHours, 8);
});

Deno.test("sanitiseExtraction falls back to daily for an unrecognised frequency", () => {
  const out = sanitiseExtraction({ medicines: [{ frequencyType: "hourly" }, {}], careItems: [] });
  const medicines = out.medicines as Record<string, unknown>[];
  assertEquals(medicines[0].frequencyType, "daily");
  assertEquals(medicines[1].frequencyType, "daily");
});

Deno.test("sanitiseExtraction clamps a medicine confidence the model made up", () => {
  const out = sanitiseExtraction({
    medicines: [{ confidence: 1.5 }, { confidence: -1 }, { confidence: "high" }],
    careItems: [],
  });
  const medicines = out.medicines as Record<string, unknown>[];
  assertEquals(medicines.map((m) => m.confidence), [0, 0, 0]);
});

// --- careItems[] --------------------------------------------------------

Deno.test("sanitiseExtraction keeps a well-formed care item intact", () => {
  const out = sanitiseExtraction({
    medicines: [],
    careItems: [{
      title: "Physiotherapy",
      kind: "therapy",
      notes: "Bring prior scans",
      firstDate: "2026-09-17",
      recurrence: "weekly",
      intervalN: 1,
      occurrenceCount: 6,
      confidence: 0.85,
    }],
  });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items.length, 1);
  assertEquals(items[0], {
    title: "Physiotherapy",
    kind: "therapy",
    notes: "Bring prior scans",
    firstDate: "2026-09-17",
    recurrence: "weekly",
    intervalN: 1,
    occurrenceCount: 6,
    confidence: 0.85,
  });
});

Deno.test("sanitiseExtraction defaults an unknown kind to other, matching TodayCareKind.fromName", () => {
  const out = sanitiseExtraction({ medicines: [], careItems: [{ title: "Follow-up", kind: "surgery" }] });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items[0].kind, "other");
});

Deno.test("sanitiseExtraction defaults an unknown recurrence to none", () => {
  const out = sanitiseExtraction({ medicines: [], careItems: [{ title: "MRI", recurrence: "biweekly" }] });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items[0].recurrence, "none");
});

Deno.test("sanitiseExtraction blanks an unparseable firstDate rather than passing it on", () => {
  const out = sanitiseExtraction({ medicines: [], careItems: [{ title: "MRI", firstDate: "next Tuesday" }] });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items[0].firstDate, "");
});

Deno.test("sanitiseExtraction bounds intervalN to 1-365, defaulting out-of-range values to 1", () => {
  const out = sanitiseExtraction({
    medicines: [],
    careItems: [
      { title: "a", intervalN: 0 },
      { title: "b", intervalN: 400 },
      { title: "c", intervalN: 2.5 },
      { title: "d", intervalN: 90 },
    ],
  });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items.map((i) => i.intervalN), [1, 1, 1, 90]);
});

Deno.test("sanitiseExtraction bounds occurrenceCount to 1-52, defaulting out-of-range values to 1", () => {
  // A model-supplied 400 would otherwise ask the client to expand 400
  // individual reminders from one document.
  const out = sanitiseExtraction({
    medicines: [],
    careItems: [
      { title: "a", occurrenceCount: 0 },
      { title: "b", occurrenceCount: 400 },
      { title: "c", occurrenceCount: 6 },
    ],
  });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items.map((i) => i.occurrenceCount), [1, 1, 6]);
});

Deno.test("sanitiseExtraction clamps a care-item confidence the model made up", () => {
  const out = sanitiseExtraction({
    medicines: [],
    careItems: [{ title: "a", confidence: 2 }, { title: "b", confidence: -0.5 }],
  });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(items.map((i) => i.confidence), [0, 0]);
});

Deno.test("sanitiseExtraction truncates an unreasonably long title or notes rather than dropping the item", () => {
  const out = sanitiseExtraction({
    medicines: [],
    careItems: [{ title: "x".repeat(500), notes: "y".repeat(5_000) }],
  });
  const items = out.careItems as Record<string, unknown>[];
  assertEquals((items[0].title as string).length, 200);
  assertEquals((items[0].notes as string).length, 2_000);
});

// --- whole-document shape -------------------------------------------------

Deno.test("sanitiseExtraction survives missing or wrong-shaped arrays", () => {
  assertEquals(sanitiseExtraction({}), { medicines: [], careItems: [] });
  assertEquals(sanitiseExtraction({ medicines: "not an array", careItems: 3 }), {
    medicines: [],
    careItems: [],
  });
});

Deno.test("sanitiseExtraction drops non-object entries from either array rather than throwing", () => {
  const out = sanitiseExtraction({
    medicines: [null, "oops", { drugName: "Metformin" }],
    careItems: [42, { title: "MRI" }],
  });
  const medicines = out.medicines as Record<string, unknown>[];
  const items = out.careItems as Record<string, unknown>[];
  assertEquals(medicines.length, 1);
  assertEquals(medicines[0].drugName, "Metformin");
  assertEquals(items.length, 1);
  assertEquals(items[0].title, "MRI");
});

Deno.test("sanitiseExtraction handles a document with only care items", () => {
  const out = sanitiseExtraction({ medicines: [], careItems: [{ title: "Repeat scan", kind: "scan" }] });
  assertEquals((out.medicines as unknown[]).length, 0);
  assertEquals((out.careItems as unknown[]).length, 1);
});

Deno.test("sanitiseExtraction handles a document with only medicines", () => {
  const out = sanitiseExtraction({ medicines: [{ drugName: "Metformin" }], careItems: [] });
  assertEquals((out.medicines as unknown[]).length, 1);
  assertEquals((out.careItems as unknown[]).length, 0);
});
