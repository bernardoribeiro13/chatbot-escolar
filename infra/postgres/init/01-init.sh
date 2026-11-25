#!/usr/bin/env bash
# Bootstraps the database on first start (empty data volume only).
# - pgvector extension
# - schemas: escolar (API) and rag (RAG vectors)
# - application roles api_user and rag_user, each restricted to its own schema
# POSTGRES_USER is the migration role: it owns and creates all tables, and the
# default privileges below give the application roles DML access to them.
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -v api_pw="$API_DB_PASSWORD" \
  -v rag_pw="$RAG_DB_PASSWORD" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS vector;

CREATE SCHEMA escolar;
CREATE SCHEMA rag;

CREATE ROLE api_user LOGIN PASSWORD :'api_pw';
CREATE ROLE rag_user LOGIN PASSWORD :'rag_pw';

-- Nobody but the owner creates objects in public (already the default on PG15+).
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- api_user: DML only, schema escolar only.
GRANT USAGE ON SCHEMA escolar TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA escolar
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA escolar
  GRANT USAGE, SELECT ON SEQUENCES TO api_user;
ALTER ROLE api_user SET search_path = escolar;

-- rag_user: DML only, schema rag only; public stays in the path for the vector type.
GRANT USAGE ON SCHEMA rag TO rag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA rag
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rag_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA rag
  GRANT USAGE, SELECT ON SEQUENCES TO rag_user;
ALTER ROLE rag_user SET search_path = rag, public;
EOSQL
