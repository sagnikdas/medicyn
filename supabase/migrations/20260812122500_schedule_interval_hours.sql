-- Interval, in hours, for "every X hours" schedules. NULL for other
-- frequency types. times[0] on the schedule row is the anchor/first-dose
-- time; the app computes subsequent occurrences by adding this interval.
alter table schedules add column interval_hours integer;
