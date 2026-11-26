# ADR-0002: Event envelope and event-type naming contract

**Status:** Accepted

**Date:** 2026-11-26

## Context

ADR-0001 created `event_store.events` and noted that `event_type` becomes a permanent
contract: once rows exist, a stored value can never change, so it must not depend on what a
Java class is called today. No naming rule existed yet.

Three more gaps had to be closed before the first event is stored, because every one of
them ends up in rows that can never be edited (EC-1):

- The event-sourcing conventions say every event carries an **aggregate type**, but the V1
  migration has no such column. The schema and the conventions disagreed.
- Nothing said which metadata every event carries. The spec requires every fact to be
  attributable to an actor (SEC-2), and later phases need to link facts across crew members
  (swaps, SW-3).
- Nothing said what an event stores about the duty it refers to. Duties are flights *and*
  trainings, and they change after crew are assigned (a flight is retimed, a training is
  moved).

The last point has a regulatory side. EASA ORO.FTL.245 requires operators to keep, per crew
member and for 24 months, records of duty and flight duty periods, rest periods and days off,
and EASA guidance requires both planned and achieved rosters to be kept. A record that only
points at a duty whose times are later overwritten cannot reproduce the planned roster.

The same history must always rebuild the same state (EC-4), so all four decisions below are
judged first by whether they keep replay deterministic.

## Decision

### 1. Event-type naming

`event_type` is a fixed string declared explicitly for each event type. It is never derived
from a Java class name or package, so renaming or moving a class changes nothing in storage.

Names are past-tense facts in PascalCase, in the planners' vocabulary, without a prefix (the
kind of history is carried by `aggregate_type`, see 3). The first two are `DutyAssigned` and
`DutyUnassigned`. "Duty" covers flights and trainings alike, so one event type serves both.

### 2. Evolving an event's shape

Changes to an existing event type are additive only: a new field is optional, and code
reading an older row that lacks it supplies a defined default. A change that cannot be
expressed that way (a removed, renamed or re-typed field, or changed meaning) becomes a new
event type, for example `DutyAssignedV2`, and the old type stays readable forever.

Upcasting (converting old rows to a newer shape on read) is deferred. There are no stored
events yet and no breaking change is planned, so it would be machinery with nothing to do.
It is revisited the first time a breaking change is needed.

### 3. Aggregate type

Every row records the kind of history it belongs to in an `aggregate_type` column, so
histories of different kinds (crew members now, possibly swaps in Phase 3) can be told apart,
filtered and rebuilt per kind without inferring it from `event_type`. Values follow the same
rule as event types: fixed, explicitly declared strings, the first being `CrewMember`.

This resolves the disagreement in favour of the conventions. The schema changes, through a
new migration (V1 is never edited).

`aggregate_id` stays a permanent, meaningless UUID. A crew member's crew code (call sign,
for example `ANA`) is data about the crew member, not an identifier: it is unique among
active crew but can change, and history must survive that change.

### 4. Envelope and payload

The **envelope** is the metadata every event has, each in its own typed column:

| Field | Meaning |
|---|---|
| `id` | Global, cross-aggregate order (existing, ADR-0001) |
| `aggregate_id` | Which history: the crew member's permanent UUID (existing) |
| `aggregate_type` | Which kind of history, e.g. `CrewMember` (new) |
| `version` | Position in that history, for optimistic concurrency (existing) |
| `event_type` | Which fact, e.g. `DutyAssigned` (existing) |
| `occurred_at` | When it happens or happened in the real world (new) |
| `created_at` | When the system recorded it (existing) |
| `actor_type` | Whether a person or a system component caused it (new) |
| `actor_id` | Which user or which component, by a permanent identifier, not a login name (new) |
| `actor_role` | The role the actor acted in at that moment (new) |
| `correlation_id` | Groups facts that belong to one multi-step flow, such as one swap (new) |
| `causation_id` | The fact or command this fact was caused by (new) |

The **payload** is the data specific to one event type. It carries a link to anything it
refers to **and a copy of the values the decision depended on, as they were at that moment**.
A recorded fact must mean the same thing forever, so it may refer to other data but must
never depend on data that can change. For `DutyAssigned` that means the `duty_id` plus the
duty's kind (flight or training), start, end and the assigned role. The exact payload of each
event type is defined with the event types themselves (TICKET-007, #9).

Fields that could go either way:

- **`occurred_at` in the envelope:** every fact happens at some real-world time, and it is
  distinct from `created_at` (a sick call made at 05:00 may be entered at 07:30). Legality
  rules and the ORO.FTL.245 records depend on the real-world time, not the recording time.
- **Actor in the envelope:** SEC-2 requires attribution for every fact, not only some types.
- **`actor_role` as a copy:** roles change over time; an audit must show the role at the time.
- **Duty times in the payload, not the envelope:** only duty-related events have them.

Which envelope columns may be empty (for example `causation_id` for a planner's direct
command, or `actor_role` for a system actor), and the column types, are settled in the
migration ticket (TICKET-011, #17).

### Deferred, with reasons

- **A retimed duty.** How a schedule change reaches the histories of the crew assigned to it
  is a disruption-mode question that needs the legality rules of Phase 2 (TICKET-014, #20).
- **Planned versus actual duty times.** ORO.FTL.245 records rely on actual times; the spec
  does not yet say whether v1 models them (TICKET-013, #19).
- **How a crew member comes to exist.** Phase 1 only needs an existing crew ID; the first
  rule that needs crew data (qualification match, LR-3) does (TICKET-012, #18).
- **Idempotency keys.** Phase 5 (RS-1); they are likely a property of commands, not facts.

## Alternatives considered

- **Event type from the Java class name** (`com.….RestPeriodRecorded` or its simple name).
  Rejected: renaming or moving the class orphans every stored row, and stored rows cannot be
  changed.
- **Namespaced event types** (`crew.DutyAssigned`). Rejected for now: `aggregate_type` already
  says which kind of history a row belongs to.
- **A `schema_version` column, or upcasting from day one.** Rejected: both add machinery while
  no stored events and no breaking change exist. Additive changes need neither.
- **No `aggregate_type` column; infer the kind from `event_type`.** Rejected: implicit, cannot be
  filtered or indexed, and depends on every event type mapping to exactly one kind forever.
- **The crew code as `aggregate_id`.** Rejected: unique is not the same as permanent. A code
  derived from a name changes when the name does, and history keyed by it would point to
  nobody.
- **One `metadata` JSONB column for the envelope.** Rejected: untyped, no NOT NULL, harder to
  index (`correlation_id` will need an index in Phase 3). Accepted cost of separate columns:
  every future envelope field is a migration.
- **Payload holds only `duty_id`, linking to a duty record that is updated in place.**
  Rejected: when the duty changes, replaying old facts silently gives them new meaning. An
  assignment that was legal when made would replay as illegal, and the planned roster that
  ORO.FTL.245 requires could not be reproduced. Re-validating crew on every duty change keeps
  *current* legality but does not fix the history.
- **Payload links to an immutable, versioned duty (`duty_id` + `duty_version`).** Valid, but
  rejected for v1: it turns duties into a second append-only history with its own versioning
  and replay, for no current benefit. It remains an option if duty history needs to be
  queried directly; a read view can provide that too.

## Consequences

- Class names, packages and the Java event model can be refactored freely; storage is
  unaffected.
- Every event type name is a permanent commitment. Choosing a name now needs the same care
  as a database column name.
- Each crew member's history is self-contained: rebuilding a crew member needs no other
  table, which keeps the rules component free of its own data fetching (spec §5) and replay
  deterministic.
- Duty data is duplicated across the facts of every crew member on that duty. With 4–6 crew
  per flight this is negligible.
- Copied values are frozen on purpose. A later correction to a duty does not change old facts;
  it must be recorded as a new fact, which is what the audit trail needs anyway.
- Old events of every type stay readable forever; code must tolerate missing optional fields.
- The envelope needs a V2 migration before events are appended (TICKET-011, #17), which blocks the
  append and load tickets until it lands.
- Correlation and causation exist from the first event, so Phase 3 swaps do not require
  migrating stored history.

## Related

- Ticket: #7 (TICKET-005: Decide the event envelope and event-type naming contract)
- Follow-ups: TICKET-011 (#17, envelope migration), TICKET-012 (#18, crew existence),
  TICKET-013 (#19, planned vs actual times), TICKET-014 (#20, retimed duties)
- Related ADRs: ADR-0001 (event table schema)
- Spec: EC-1, EC-4, EC-7, SEC-2, SW-3, LR-3, RS-1
- [EASA ORO.FTL.245, records of flight times, duty and rest periods](https://regulatorylibrary.caa.co.uk/965-2012/Content/Regs/05210_ORO.FTL.245_Records_of_home_base_flight_times_duty_and_rest_periods.htm)
- [EASA FAQ: planned or actual values in ORO.FTL.245 records](https://www.easa.europa.eu/en/faq/47615)
