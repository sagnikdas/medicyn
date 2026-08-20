import { assertEquals } from "@std/assert";

import { planDataChange } from "./data_change.ts";

const link = {
  id: "link-1",
  patient_id: "patient-1",
  caregiver_id: "caregiver-1",
};

Deno.test("a caregiver's edit is a silent re-arm of the parent", () => {
  assertEquals(planDataChange("caregiver-1", link), {
    send: true,
    recipientId: "patient-1",
    silent: true,
  });
});

Deno.test("a parent's edit is a visible ping to the caregiver", () => {
  assertEquals(planDataChange("patient-1", link), {
    send: true,
    recipientId: "caregiver-1",
    silent: false,
  });
});

Deno.test("a stranger is not told about a change", () => {
  assertEquals(planDataChange("stranger", link), {
    send: false,
    reason: "caller_not_on_link",
  });
});

Deno.test("a claimed link with no caregiver has nobody to ping", () => {
  assertEquals(
    planDataChange("patient-1", { ...link, caregiver_id: null }),
    { send: false, reason: "caller_not_on_link" },
  );
});
