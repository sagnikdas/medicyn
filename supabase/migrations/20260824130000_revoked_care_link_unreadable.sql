-- care_links_read_own let either party read a link forever, revoked or not
-- — revoke_care_link flips status but deliberately never clears patient_id
-- / caregiver_id (see its own comment), so a revoked caregiver's own uid
-- still matched `caregiver_id = auth.uid()` and the row, phone numbers
-- included, stayed fully readable.
--
-- No app code relies on reading a revoked row: CareService.currentLink()
-- already excludes status = 'revoked' itself ("history, not state"). This
-- makes the database enforce the same thing, rather than trusting every
-- future caller to remember the filter.
drop policy "care_links_read_own" on care_links;

create policy "care_links_read_own" on care_links
  for select using (
    status <> 'revoked'
    and (patient_id = (select auth.uid()) or caregiver_id = (select auth.uid()))
  );
