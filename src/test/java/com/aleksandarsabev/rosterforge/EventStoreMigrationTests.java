package com.aleksandarsabev.rosterforge;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * Asserts the outcome of the migrations (the schema exists as ADR-0001 and ADR-0002 define
 * it), not merely that Flyway ran: contextLoads passes even when no migration is applied.
 */
@Import(TestcontainersConfiguration.class)
@SpringBootTest
class EventStoreMigrationTests {

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void everyMigrationIsRecordedAsSuccessfullyApplied() {
        List<Map<String, Object>> history = jdbc.queryForList(
                "SELECT version, success FROM flyway_schema_history WHERE version IS NOT NULL ORDER BY installed_rank");

        assertThat(history).extracting(row -> row.get("version")).containsExactly("1", "2");
        assertThat(history).allSatisfy(row -> assertThat(row.get("success")).isEqualTo(true));
    }

    @Test
    void eventsTableHasTheEnvelopeAdr0002Defines() {
        Map<String, String> columns = jdbc.queryForList("""
                        SELECT column_name, data_type, is_nullable
                        FROM information_schema.columns
                        WHERE table_schema = 'event_store' AND table_name = 'events'
                        """)
                .stream()
                .collect(Collectors.toMap(
                        row -> (String) row.get("column_name"),
                        row -> row.get("data_type") + ("YES".equals(row.get("is_nullable")) ? " null" : " not null")));

        assertThat(columns).containsOnly(
                Map.entry("id", "bigint not null"),
                Map.entry("aggregate_id", "uuid not null"),
                Map.entry("aggregate_type", "text not null"),
                Map.entry("version", "bigint not null"),
                Map.entry("event_type", "text not null"),
                Map.entry("payload", "jsonb not null"),
                Map.entry("occurred_at", "timestamp with time zone not null"),
                Map.entry("created_at", "timestamp with time zone not null"),
                Map.entry("actor_type", "text not null"),
                Map.entry("actor_id", "text not null"),
                Map.entry("actor_role", "text null"),
                Map.entry("correlation_id", "uuid not null"),
                Map.entry("causation_id", "uuid null"));
    }

    @Test
    void aggregateVersionIsUnique() {
        Integer constraints = jdbc.queryForObject("""
                        SELECT count(*)
                        FROM information_schema.table_constraints
                        WHERE table_schema = 'event_store' AND table_name = 'events'
                          AND constraint_name = 'uq_aggregate_version' AND constraint_type = 'UNIQUE'
                        """, Integer.class);

        assertThat(constraints).isEqualTo(1);
    }

    @Test
    @Transactional // rolls back, so no test row is left in the shared database
    void acceptsAUserAndASystemActor() {
        insert("USER", "3f2c9a1e-0000-4000-8000-000000000001", "CREW_CONTROLLER");
        insert("SYSTEM", "roster-generator", null);

        assertThat(jdbc.queryForObject("SELECT count(*) FROM event_store.events", Integer.class)).isEqualTo(2);
    }

    @Test
    @Transactional
    void rejectsAUserActorWithoutARole() {
        assertThatThrownBy(() -> insert("USER", "3f2c9a1e-0000-4000-8000-000000000001", null))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ck_events_user_has_role");
    }

    @Test
    @Transactional
    void rejectsAnUnknownActorType() {
        assertThatThrownBy(() -> insert("DEPARTMENT", "crew-operations", "CREW_PLANNER"))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("ck_events_actor_type");
    }

    private void insert(String actorType, String actorId, String actorRole) {
        jdbc.update("""
                        INSERT INTO event_store.events
                            (aggregate_id, aggregate_type, version, event_type, payload, occurred_at,
                             actor_type, actor_id, actor_role, correlation_id)
                        VALUES (gen_random_uuid(), 'CrewMember', 1, 'DutyAssigned', '{}'::jsonb, now(),
                                ?, ?, ?, gen_random_uuid())
                        """, actorType, actorId, actorRole);
    }
}
