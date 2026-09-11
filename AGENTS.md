# AGENTS.md

## Project
RosterForge — event-sourced crew scheduling platform (portfolio project, Java/Spring Boot).
Not a tutorial-follow project — built for depth and to demonstrate independent engineering.

## Setup
- Java 21 required (Temurin recommended). Maven wrapper included — use `./mvnw` or `mvnw.cmd`.
- Local infra runs via Docker/Podman Compose: `docker/docker-compose.yaml` defines
  Postgres (port 5434), Kafka (port 9094), Vault (port 8200) — all non-default ports to
  avoid clashing with other local services on this machine.

## Build
mvnw clean install

## Run
1. Start infra first
docker compose -f docker/docker-compose.yaml up -d # or: podman compose -f docker/docker-compose.yaml up -d

2. Then run the app (from IDE, or:)
mvnw spring-boot:run

## Test
mvnw test

Integration tests use Testcontainers with real Postgres/Kafka — Docker/Podman must be
running. Tests should never rely on mocked infra for anything covering event store,
projections, or Kafka behavior.

## Verify before considering any task done
mvnw clean install

must pass with no failing tests before a change is considered complete.

## Code conventions
- Java 21, records for events/DTOs where possible, no Lombok.
- Events: past-tense immutable facts (`CrewAssigned`, not `UpdateCrew`). No setters.
- Command handlers write only to the event store — never directly to projection tables.
- Projections must be correct when rebuilt from a full event replay, not just patched
  incrementally.
- Spring Boot 4.x naming: `spring-boot-starter-webmvc` (not deprecated `-web`), per-feature
  test starters (not one monolithic `spring-boot-starter-test`) — these are correct for
  this Boot version, do not "fix" them to older names.
- Testcontainers dependencies: groupId `org.testcontainers`, no per-dependency `<version>` —
  version comes from the `testcontainers-bom` import in `dependencyManagement`.
- All real or placeholder-sensitive config goes through Vault or `${VAR:default}`
  placeholders — never hardcoded secrets, even trivial local ones, once Vault is wired.
- Known CVEs in transitive dependencies: fix via explicit `<dependencyManagement>`
  version override, not by ignoring the finding.

## Architecture (read before touching core logic)
Event-sourced + CQRS. Write path: command → validate against legality rules → append
event → publish to Kafka. Read path: projector consumes asynchronously → updates
projection tables → query handlers read only from projections. The gap between write
and read is real eventual consistency, not a bug to "fix" by making things synchronous.
Sagas (crew swaps) coordinate multi-step confirm/compensate flows separately from the
simple command/query loop. The rostering solver is self-built (greedy baseline, then
real search) — do not introduce OptaPlanner or OR-Tools as the core solver.

## Build order — do not skip ahead
1. Event core → 2. Legality rules → 3. Sagas → 4. Solver → 5. Resilience → 6. API → 7. Dashboard

## PR/commit expectations
- Small, single-purpose commits mapped to GitHub Issues under the relevant Phase milestone.
- Don't mix phases in one commit (e.g., saga logic changes alongside event-core changes).

## What agents should NOT do here
- Don't write full implementations of core domain logic (event handlers, saga state
  machines, solver algorithms) unless explicitly asked — this repo's owner is building
  it themselves to learn; default to explaining/reviewing, not generating the solution.
- Don't silently change an existing event type's shape once events of that type exist.
- Don't add dependencies without checking for CVEs and pinning versions via
  dependencyManagement where needed.
