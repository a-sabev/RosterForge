#!/bin/sh
# Runs once, when the pgdata volume is first initialized. The app gets its own
# non-superuser role: it owns the rosterforge database, so Flyway can create schemas,
# but it has no rights anywhere else in the cluster.
#
# No `set`/`exit` here: the postgres entrypoint sources this file if it isn't executable.
# \set with backticks reads the password inside psql, so it never appears in argv.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
\set app_password `cat /run/secrets/postgres/app_password`
CREATE ROLE rosterforge LOGIN PASSWORD :'app_password';
ALTER DATABASE rosterforge OWNER TO rosterforge;
REVOKE ALL ON DATABASE rosterforge FROM PUBLIC;
GRANT CONNECT ON DATABASE rosterforge TO rosterforge;
SQL
