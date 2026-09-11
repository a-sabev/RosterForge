# RosterForge

Event-sourced crew scheduling platform. Portfolio project, ~6 months, built to demonstrate
Java backend depth for interview purposes — not a tutorial-follow project.

## Tech stack
- Java 21, Spring Boot 4.1.1, Maven
- Postgres (event store + read-model projections), real Kafka (event backbone)
- Spring Cloud Vault for secrets (dev-mode Vault container, root token locally)
- JUnit 5, Testcontainers (real Postgres/Kafka in tests, never mocked)
- Flyway for migrations

## Architecture
Event-sourced + CQRS, NOT layered/CRUD. Write side: command handler validates against
legality rules, appends immutable event, publishes to Kafka. Read side: projectors
consume events asynchronously and update projection tables; query handlers read only
from projections, never from the event log directly. There is a real, non-zero
eventual-consistency gap between write and read — this is intentional, not a bug.

Multi-step operations (crew swaps) run as sagas — separate from the simple command/query
loop, coordinating confirmation and compensation/rollback.

The rostering solver (Phase 4) is self-built — greedy baseline, then real search/
optimization. Deliberately NOT using OptaPlanner or OR-Tools for the core solver; that
would defeat the point. OR-Tools may be used later purely as an external benchmark.

## Phase plan (build in this order, do not skip ahead)
1. Event core — event log, replay-safe projections
2. Legality rules — EASA-style rest/duty-limit validators, append-time checks
3. Sagas — swap confirmation flow, compensation/rollback
4. Solver — greedy baseline, then real search
5. Resilience — idempotency keys, dead-letter handling
6. API layer — REST + WebSocket
7. Dashboard — thin React frontend (vibecoded, not a learning focus)

Track work as GitHub Issues under Phase milestones. Tickets should be small,
single-purpose, closeable independently.

## How I want to work with Claude Code here
- I am building this myself to learn — do NOT write full implementations of core domain
  logic (event handlers, saga logic, solver algorithms) unless I explicitly ask you to.
  Default to explaining, reviewing, and catching mistakes, not writing the solution.
- DO help freely with: boilerplate (DTOs, config wiring), debugging build/dependency
  errors, explaining Spring/Kafka/Postgres behavior, code review of what I've written.
- Flag it clearly if I'm about to skip a phase, take on tech debt, or design something
  that will bite me later (e.g., breaking replay determinism, weak legality validation).
- Never silently "fix" domain logic — explain the issue and let me decide the fix.
- Local dev only for now — Postgres on :5434, Kafka on :9094, Vault on :8200 (all via
  docker/docker-compose.yaml, isolated ports to avoid clashing with other
  local projects on this machine).