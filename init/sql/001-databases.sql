DO $roles$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'hasura_metadata') THEN
    CREATE ROLE hasura_metadata LOGIN PASSWORD 'test';
  ELSE
    ALTER ROLE hasura_metadata WITH LOGIN PASSWORD 'test';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'hasura_app') THEN
    CREATE ROLE hasura_app LOGIN PASSWORD 'test';
  ELSE
    ALTER ROLE hasura_app WITH LOGIN PASSWORD 'test';
  END IF;
END
$roles$;

SELECT 'CREATE DATABASE hasura_metadata OWNER hasura_metadata'
WHERE NOT EXISTS (
  SELECT FROM pg_catalog.pg_database WHERE datname = 'hasura_metadata'
)
\gexec

SELECT 'CREATE DATABASE app OWNER hasura_app'
WHERE NOT EXISTS (
  SELECT FROM pg_catalog.pg_database WHERE datname = 'app'
)
\gexec

ALTER DATABASE hasura_metadata OWNER TO hasura_metadata;
ALTER DATABASE app OWNER TO hasura_app;
