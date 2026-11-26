-- V2__add_event_envelope.sql
-- Adds the envelope fields decided in ADR-0002 (docs/adr/ADR-0002-event-envelope.md).
--
-- NOT NULL columns are added without defaults. That only works because no events have been
-- stored yet. A later migration adding a required column to a table with rows must backfill
-- them first, in a separate step, or the ALTER fails.

ALTER TABLE event_store.events
    -- Which kind of history the row belongs to, e.g. 'CrewMember'. Every fact belongs to one.
    -- No CHECK on the values: a new kind (e.g. swaps in Phase 3) must not need a migration.
    ADD COLUMN aggregate_type TEXT NOT NULL,

    -- When the fact happens or happened in the real world. Every fact has such a time, and it
    -- differs from created_at (when it was recorded). No default: defaulting to now() would
    -- silently make it equal to the recording time instead of being supplied deliberately.
    ADD COLUMN occurred_at TIMESTAMPTZ NOT NULL,

    -- Whether a person or a system component caused the fact. A closed set, so it is checked.
    ADD COLUMN actor_type TEXT NOT NULL,

    -- Which user (their permanent UUID) or which component (e.g. 'roster-generator').
    -- TEXT, not UUID, because it has to hold both. Every fact is attributable (spec SEC-2).
    ADD COLUMN actor_id TEXT NOT NULL,

    -- The role the user acted in at that moment, e.g. 'CREW_CONTROLLER'. Empty only for
    -- system actors, which have no role.
    ADD COLUMN actor_role TEXT,

    -- Groups the facts of one flow, e.g. both crew members' facts of one swap. Always set:
    -- a fact from a single command forms a flow of one, so every fact can be traced.
    ADD COLUMN correlation_id UUID NOT NULL,

    -- The message (command, or a fact that triggered a command) that directly caused this
    -- fact. Empty when the fact comes straight from a person's or component's own action.
    ADD COLUMN causation_id UUID,

    ADD CONSTRAINT ck_events_actor_type CHECK (actor_type IN ('USER', 'SYSTEM')),
    ADD CONSTRAINT ck_events_user_has_role CHECK (actor_type <> 'USER' OR actor_role IS NOT NULL);

-- uq_aggregate_version (aggregate_id, version) from V1 stays as it is. aggregate_id is a UUID
-- and so unique across every kind of history; adding aggregate_type to the constraint would
-- only allow two histories of different kinds to share an id, which must never happen.
