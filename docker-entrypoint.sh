#!/bin/bash
set -euo pipefail

echo "Running database migrations..."
bundle exec rake db:migrate

exec "$@"
