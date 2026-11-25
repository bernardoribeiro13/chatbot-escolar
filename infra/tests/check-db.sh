#!/usr/bin/env bash
# Smoke test for the local database environment (infra/docker-compose.yml).
#
# Turns the manual BD3 checks into automated ones: schemas, extension, roles,
# schema isolation, search_path, password authentication and Redis.
# Exits non-zero if ANY check does not produce the expected result, including
# when something that should be denied is allowed.
#
# Requires the stack to be up: `docker compose up -d --wait` in infra/.
# Credentials are read from infra/.env; nothing secret is hardcoded here.
set -euo pipefail

# Git Bash on Windows rewrites arguments that look like paths; disable it.
export MSYS_NO_PATHCONV=1

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$INFRA_DIR/.env"
cd "$INFRA_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "FAIL: $ENV_FILE not found (copy it from .env.example)" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${POSTGRES_DB:?POSTGRES_DB missing in .env}"
: "${POSTGRES_USER:?POSTGRES_USER missing in .env}"
: "${API_DB_PASSWORD:?API_DB_PASSWORD missing in .env}"
: "${RAG_DB_PASSWORD:?RAG_DB_PASSWORD missing in .env}"

readonly API_ROLE=api_user
readonly RAG_ROLE=rag_user

PG_CONTAINER="$(docker compose ps -q postgres)"
if [[ -z "$PG_CONTAINER" ]]; then
  echo "FAIL: postgres service is not running (run: docker compose up -d --wait)" >&2
  exit 1
fi
# Reuse the server image as the client and join the Compose network, so
# password checks connect from OUTSIDE the postgres container. Inside it,
# local and 127.0.0.1 connections use "trust" and never ask for a password.
PG_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$PG_CONTAINER")"
PG_NETWORK="$(docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}' "$PG_CONTAINER")"

failures=0
passes=0

ok() {
  passes=$((passes + 1))
  printf '  OK    %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf '  FAIL  %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '        %s\n' "$2"
  fi
}

# Run SQL inside the postgres container as <role> (trust auth, no password).
# Used for permission checks, which do not depend on how the role logged in.
sql_as() {
  local role="$1" sql="$2"
  docker compose exec -T postgres \
    psql -X -q -v ON_ERROR_STOP=1 -U "$role" -d "$POSTGRES_DB" -tA -c "$sql" 2>&1
}

# Run SQL from a throwaway container on the Compose network (password auth).
sql_over_network() {
  local role="$1" password="$2" sql="$3"
  PGPASSWORD="$password" docker run --rm --network "$PG_NETWORK" -e PGPASSWORD "$PG_IMAGE" \
    psql -X -q -v ON_ERROR_STOP=1 -h postgres -U "$role" -d "$POSTGRES_DB" -tA -c "$sql" 2>&1
}

# expect_value <description> <expected output> <command...>
expect_value() {
  local desc="$1" expected="$2" out
  shift 2
  if out="$("$@")" && [[ "$out" == "$expected" ]]; then
    ok "$desc"
  else
    fail "$desc" "expected '$expected', got: ${out//$'\n'/ | }"
  fi
}

# expect_denied <description> <error pattern> <command...>
# Passes only if the command fails AND the error matches the pattern, so an
# unrelated failure (e.g. a connection error) is not mistaken for a denial.
expect_denied() {
  local desc="$1" pattern="$2" out
  shift 2
  if out="$("$@")"; then
    fail "$desc" "expected an error matching '$pattern', but it succeeded"
  elif [[ "$out" == *"$pattern"* ]]; then
    ok "$desc"
  else
    fail "$desc" "failed for an unexpected reason: ${out//$'\n'/ | }"
  fi
}

# Drops the probe tables, plus any ci_denied table left behind if a
# "cannot create" check unexpectedly succeeded.
cleanup() {
  sql_as "$POSTGRES_USER" "DROP TABLE IF EXISTS escolar.ci_probe, rag.ci_probe,
    escolar.ci_denied, rag.ci_denied, public.ci_denied;" >/dev/null || true
}
trap cleanup EXIT

echo "== Structure"
for schema in escolar rag; do
  expect_value "schema '$schema' exists" 1 \
    sql_as "$POSTGRES_USER" "SELECT count(*) FROM pg_namespace WHERE nspname = '$schema';"
done
expect_value "extension 'vector' exists" 1 \
  sql_as "$POSTGRES_USER" "SELECT count(*) FROM pg_extension WHERE extname = 'vector';"
for role in "$POSTGRES_USER" "$API_ROLE" "$RAG_ROLE"; do
  expect_value "role '$role' exists" 1 \
    sql_as "$POSTGRES_USER" "SELECT count(*) FROM pg_roles WHERE rolname = '$role';"
done

echo "== Probe tables (created by the migration role)"
cleanup
expect_value "$POSTGRES_USER creates escolar.ci_probe and rag.ci_probe" "" \
  sql_as "$POSTGRES_USER" "CREATE TABLE escolar.ci_probe (id int); CREATE TABLE rag.ci_probe (id int, embedding vector(3));"

echo "== Isolation"
for schema in rag escolar public; do
  expect_denied "$API_ROLE cannot create a table in '$schema'" "permission denied for schema $schema" \
    sql_as "$API_ROLE" "CREATE TABLE $schema.ci_denied (id int);"
done
expect_denied "$API_ROLE cannot read rag.ci_probe" "permission denied for schema rag" \
  sql_as "$API_ROLE" "SELECT * FROM rag.ci_probe;"
expect_denied "$RAG_ROLE cannot read escolar.ci_probe" "permission denied for schema escolar" \
  sql_as "$RAG_ROLE" "SELECT * FROM escolar.ci_probe;"

echo "== Application access through search_path (no schema prefix)"
expect_value "$API_ROLE inserts and selects ci_probe" 1 \
  sql_as "$API_ROLE" "INSERT INTO ci_probe VALUES (1); SELECT id FROM ci_probe;"
expect_value "$RAG_ROLE inserts and selects ci_probe with vector(3)" "1|[1,2,3]" \
  sql_as "$RAG_ROLE" "INSERT INTO ci_probe VALUES (1, '[1,2,3]'); SELECT id, embedding FROM ci_probe;"

echo "== Password authentication (from outside the postgres container)"
expect_value "$API_ROLE logs in with the correct password" "$API_ROLE" \
  sql_over_network "$API_ROLE" "$API_DB_PASSWORD" "SELECT current_user;"
expect_denied "$API_ROLE is rejected with a wrong password" "password authentication failed" \
  sql_over_network "$API_ROLE" "${API_DB_PASSWORD}_wrong" "SELECT 1;"

echo "== Redis"
expect_value "redis answers PING" PONG \
  docker compose exec -T redis redis-cli ping

echo
if ((failures > 0)); then
  echo "RESULT: $failures check(s) FAILED, $passes passed"
  exit 1
fi
echo "RESULT: all $passes checks passed"
