-- Replace the placeholders with values from OpenBao; never commit real passwords.

-- dbt: read raw, own staging and marts.
CREATE USER IF NOT EXISTS dbt_user IDENTIFIED WITH sha256_password BY '__DBT_PASSWORD__';
GRANT SELECT ON raw.* TO dbt_user;
-- ALL on staging/marts is the PoC shortcut. dbt needs CREATE, DROP, INSERT,
-- SELECT, TRUNCATE, EXCHANGE and ALTER DELETE (the delete_insert strategy
-- uses a lightweight DELETE). Narrow it once the build is stable.
GRANT ALL ON staging.* TO dbt_user;
GRANT ALL ON marts.*   TO dbt_user;

-- Keep dbt from starving dashboard queries on the shared worker node.
CREATE SETTINGS PROFILE IF NOT EXISTS dbt_profile
    SETTINGS max_threads = 4, max_memory_usage = 6000000000
    TO dbt_user;

-- Cube: read marts only. It can never see raw or staging.
CREATE USER IF NOT EXISTS cube_user IDENTIFIED WITH sha256_password BY '__CUBE_PASSWORD__';
GRANT SELECT ON marts.* TO cube_user;
