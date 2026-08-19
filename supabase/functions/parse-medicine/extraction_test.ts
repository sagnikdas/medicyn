import { assertEquals } from "@std/assert";
import { isClockTime, sanitiseExtraction } from "./extraction.ts";

// The tool's input_schema bounds these fields, but a schema is guidance to
// the model rather than a validator the API enforces — so before this, the
// model's output was returned verbatim to a device that arms medication
// alarms from it. The OCR half of the input is whatever was in front of the
// camera, which makes it attacker-influenceable.

Deno.test("isClockTime accepts real times", () => {
  assertEquals(isClockTime("09:05"), true);
  assertEquals(isClockTime("9:05"), true);
  assertEquals(isClockTime("00:00"), true);
  assertEquals(isClockTime("23:59"), true);
});

Deno.test("isClockTime rejects what the schema pattern would have let through", () => {
  // ^[0-2][0-9]:[0-5][0-9]$ admits both of these.
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

Deno.test("sanitiseExtraction keeps a well-formed extraction intact", () => {
  const out = sanitiseExtraction({
    drugName: "Metformin",
    frequencyType: "specific_days",
    times: ["08:00", "20:00"],
    daysOfWeek: [1, 3, 5],
    confidence: 0.9,
  });
  assertEquals(out.times, ["08:00", "20:00"]);
  assertEquals(out.daysOfWeek, [1, 3, 5]);
  assertEquals(out.frequencyType, "specific_days");
  assertEquals(out.confidence, 0.9);
});

Deno.test("sanitiseExtraction drops a day the client cannot schedule", () => {
  // daysOfWeek [9] was one of the two values that left a phone with no
  // medication alarms at all.
  const out = sanitiseExtraction({ daysOfWeek: [1, 9, 5] });
  assertEquals(out.daysOfWeek, [1, 5]);
});

Deno.test("sanitiseExtraction sorts and deduplicates days", () => {
  const out = sanitiseExtraction({ daysOfWeek: [5, 1, 5] });
  assertEquals(out.daysOfWeek, [1, 5]);
});

Deno.test("sanitiseExtraction drops a malformed time but keeps the good ones", () => {
  const out = sanitiseExtraction({ times: ["08:00", "9am", "29:00", "20:30"] });
  assertEquals(out.times, ["08:00", "20:30"]);
});

Deno.test("sanitiseExtraction discards an out-of-range interval rather than passing it on", () => {
  // intervalHours 0 was the other value; it never advances the walk that
  // finds the next dose.
  assertEquals(sanitiseExtraction({ intervalHours: 0 }).intervalHours, undefined);
  assertEquals(sanitiseExtraction({ intervalHours: -4 }).intervalHours, undefined);
  assertEquals(sanitiseExtraction({ intervalHours: 999 }).intervalHours, undefined);
  assertEquals(sanitiseExtraction({ intervalHours: 2.5 }).intervalHours, undefined);
  assertEquals(sanitiseExtraction({ intervalHours: 8 }).intervalHours, 8);
});

Deno.test("sanitiseExtraction falls back to daily for a frequency it does not know", () => {
  assertEquals(sanitiseExtraction({ frequencyType: "hourly" }).frequencyType, "daily");
  assertEquals(sanitiseExtraction({ frequencyType: 7 }).frequencyType, "daily");
  assertEquals(sanitiseExtraction({}).frequencyType, "daily");
  assertEquals(sanitiseExtraction({ frequencyType: "as_needed" }).frequencyType, "as_needed");
});

Deno.test("sanitiseExtraction clamps a confidence the model made up", () => {
  assertEquals(sanitiseExtraction({ confidence: 1.5 }).confidence, 0);
  assertEquals(sanitiseExtraction({ confidence: -1 }).confidence, 0);
  assertEquals(sanitiseExtraction({ confidence: "high" }).confidence, 0);
});

Deno.test("sanitiseExtraction survives fields of entirely the wrong shape", () => {
  // A response this malformed used to reach the client and throw there.
  const out = sanitiseExtraction({ times: "08:00", daysOfWeek: 3 });
  assertEquals(out.times, []);
  assertEquals(out.daysOfWeek, []);
});

Deno.test("sanitiseExtraction leaves the free-text fields alone", () => {
  // They are shown to the user for confirmation, never used as a loop bound,
  // so there is nothing here to validate against.
  const out = sanitiseExtraction({ drugName: "Metformin", notes: "take with food" });
  assertEquals(out.drugName, "Metformin");
  assertEquals(out.notes, "take with food");
});
