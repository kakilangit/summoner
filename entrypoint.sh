#!/bin/sh
set -eu

# Run migrations
echo "[Summoner] Running migrations..."
bin/summoner eval "Summoner.Release.migrate()"

# Seed admin user
echo "[Summoner] Seeding admin user..."
bin/summoner eval "Summoner.Release.seed_admin()"

# Start the application
echo "[Summoner] Starting application..."
exec bin/summoner "$@"
