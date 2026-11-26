package com.aleksandarsabev.rosterforge;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Asserts the outcome of the migrations (the schema exists as V1 defines it), not merely
 * that Flyway ran: contextLoads passes even when no migration is applied.
 */
@Import(TestcontainersConfiguration.class)
@SpringBootTest
class EventStoreMigrationTests {

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void v1IsRecordedAsSuccessfullyApplied() {
        Boolean success = jdbc.queryForObject(
                "SELECT success FROM flyway_schema_history WHERE version = '1'", Boolean.class);

        assertThat(success).isTrue();
    }

    @Test
    void eventsTableHasTheColumnsV1Defines() {
        Map<String, String> columns = jdbc.queryForList("""
                        SELECT column_name, data_type
                        FROM information_schema.columns
                        WHERE table_schema = 'event_store' AND table_name = 'events'
                        """)
                .stream()
                .collect(Collectors.toMap(
                        row -> (String) row.get("column_name"),
                        row -> (String) row.get("data_type")));

        assertThat(columns).containsOnly(
                Map.entry("id", "bigint"),
                Map.entry("aggregate_id", "uuid"),
                Map.entry("version", "bigint"),
                Map.entry("event_type", "text"),
                Map.entry("payload", "jsonb"),
                Map.entry("created_at", "timestamp with time zone"));
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
}
