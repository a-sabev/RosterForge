-- V1__init_events_table.sql

CREATE SCHEMA IF NOT EXISTS event_store;
CREATE SCHEMA IF NOT EXISTS read_model;

CREATE TABLE event_store.events (
    id            BIGSERIAL PRIMARY KEY,
    aggregate_id  UUID NOT NULL,
    version       BIGINT NOT NULL,
    event_type    TEXT NOT NULL,
    payload       JSONB NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_aggregate_version UNIQUE (aggregate_id, version)
);