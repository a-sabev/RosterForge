---
name: event-sourcing-conventions
description: Conventions for this project's event sourcing implementation — event naming, schema, and replay-safety rules. Use whenever writing or reviewing event types, the event store, or projections.
---

# Event Sourcing Conventions for RosterForge

- Events are named as past-tense facts: `CrewAssigned`, `SwapRequested`,
  `SwapConfirmed`, `SwapRolledBack` — never `UpdateCrew` or similar CRUD-style names.
- Events are immutable Java records. Never add mutable fields or setters.
- Every event carries: aggregate ID, aggregate type, a version number
  (monotonic per aggregate, used for optimistic concurrency), and a timestamp.
- Command handlers NEVER write directly to projection tables. Only the event
  store gets written to on the command path.
- Projections are rebuilt-from-replay, not incrementally patched by hand —
  if projection logic changes, it should still produce correct state when
  replayed from event zero.
- Any change to an event's shape is a compatibility concern — flag it, don't
  silently modify an existing event type once events of that type exist.