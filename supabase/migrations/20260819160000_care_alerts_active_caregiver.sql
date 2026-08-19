-- A revoked caregiver must not keep reading care_alerts history.
--
-- The original `care_alerts_read_own_link` authorised a read if the caller
-- was the patient or the caregiver of the referenced link, with no status
-- filter. Revoked rows are kept on purpose — so "who could see my medicines,
-- and when" stays answerable — and they still carry `caregiver_id`, so that
-- policy left the ex-caregiver able to read every alert that had ever been
-- sent on the link.
--
-- The patient keeps a permanent record of what was said about them. That is
-- the symmetry promise, and it is why the rows themselves are never deleted.
-- The caregiver's right to read them is the live link, not the historical
-- row. Medicines, schedules and dose_logs already go through
-- `can_access_user_data`, which requires `status = 'active'`; this policy
-- now matches that for the caregiver side.
--
-- Kept as its own migration rather than by editing the one that added the
-- original policy, because that one has already been applied to the hosted
-- project. No insert, update or delete policy is added: writes stay with
-- the service role, as they always have.

drop policy "care_alerts_read_own_link" on care_alerts;

create policy "care_alerts_read_own_link" on care_alerts
  for select using (
    exists (
      select 1 from care_links
      where care_links.id = care_alerts.link_id
        and (
          care_links.patient_id = (select auth.uid())
          or (
            care_links.caregiver_id = (select auth.uid())
            and care_links.status = 'active'
          )
        )
    )
  );
