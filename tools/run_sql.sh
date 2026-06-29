#!/bin/sh
set -eu

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

SQL_FILE="${1:?Usage: tools/run_sql.sh path/to/query.sql}"
CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://localhost:8123}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-analytics}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-analytics}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-analytics_password}"

QUERY_STRING="$(
  python3 - <<'PY'
import os
from urllib.parse import urlencode

params = {"database": os.getenv("CLICKHOUSE_DB", "analytics")}
env_to_param = {
    "INVESTIGATION_ID": "param_investigation_id",
    "USER_QUESTION": "param_user_question",
    "TIME_FROM": "param_time_from",
    "TIME_TO": "param_time_to",
    "LOGS_SOURCE_NAME": "param_source_name",
    "LOGS_INDEX_LIKE": "param_index_like",
}
for env_key, param_key in env_to_param.items():
    value = os.getenv(env_key)
    if value:
        params[param_key] = value
print(urlencode(params))
PY
)"

curl -fsS "$CLICKHOUSE_URL/?$QUERY_STRING" \
  -u "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" \
  --data-binary @"$SQL_FILE"
