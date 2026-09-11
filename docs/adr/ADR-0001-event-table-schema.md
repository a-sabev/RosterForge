# ADR-0001: Event table schema design — id, version, and JSONB payload

**Status:** Accepted

**Date:** 2026-09-11

## Context

The events table needs to support: a database-enforced guarantee that two events
can never claim the same position in one aggregate's stream (optimistic
concurrency), correct replay ordering both within one aggregate and potentially
across the whole table, and storage of payloads whose shape varies per event type
without a schema migration for every new event type added.

## Decision

The table has three key fields beyond the basics: a database-assigned `id`
(bigserial) giving a global, cross-aggregate physical ordering; an
application-computed `version`, paired with `aggregate_id` under a `UNIQUE`
constraint, which is what makes the optimistic-concurrency check possible (the
application asserts an expected version; the database rejects a duplicate rather
than assigning the next one itself); and a `payload` column of type `JSONB` rather
than JSON or a fixed set of nullable columns.


## Consequences

The `UNIQUE(aggregate_id, version)` constraint means concurrent writes racing for
the same version are handled correctly by the database itself — one insert
succeeds, the other fails outright, with no ambiguous state possible. The separate
`id` column gives a global ordering that `version` alone cannot, since version only
orders events within one aggregate — needed for cross-aggregate queries like a
global recent-activity feed, or projections that need to catch up across the whole
event log rather than one aggregate at a time. JSONB avoids a schema migration every
time a new event type is introduced, and supports indexing into payload fields later
if needed, unlike plain JSON which just stores raw text. The trade-off is that
`event_type` (the string identifying which Java record a payload deserializes into)
becomes a permanent, versioned contract — renaming a Java class later does not
change what's already stored in old rows, so event-type names should be chosen
independently of current class names if they're expected to ever change.

## Related

- Ticket: #4 (TICKET-004: Design the Event table schema)
