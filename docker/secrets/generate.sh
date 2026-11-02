#!/bin/sh
# Generates this machine's Postgres passwords on first start. Never overwrites: the
# passwords must stay in sync with the already-initialized pgdata volume.
set -eu
umask 077

generate() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40; }

for name in superuser_password app_password; do
  [ -s "/secrets/$name" ] || generate > "/secrets/$name"
done

# 999 is the postgres user in the official image; its init scripts read these files.
chown 999:999 /secrets/*
chmod 0400 /secrets/*
