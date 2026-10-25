-- Cluster logins and the airport database.
-- airport is a database name. The logins are postgres, harperjm, sysdba, and lumynex.
-- Passwords come from psql -v lumynex_password=... harperjm_password=... sysdba_password=...

select not exists (
    select 1
    from pg_roles
    where rolname = 'lumynex'
) as lumynex_missing \gset

\if :lumynex_missing
create role lumynex login createdb password :'lumynex_password';
\else
alter role lumynex with login createdb password :'lumynex_password';
\endif

select not exists (
    select 1
    from pg_roles
    where rolname = 'harperjm'
) as harperjm_missing \gset

\if :harperjm_missing
create role harperjm login password :'harperjm_password';
\else
alter role harperjm with login password :'harperjm_password';
\endif

select not exists (
    select 1
    from pg_roles
    where rolname = 'sysdba'
) as sysdba_missing \gset

\if :sysdba_missing
create role sysdba login superuser password :'sysdba_password';
\else
alter role sysdba with login superuser password :'sysdba_password';
\endif

grant pg_read_all_data to harperjm;
grant pg_read_all_data to lumynex;
grant pg_write_all_data to lumynex;

select 'create database lumynex owner lumynex template template0'
where not exists (
    select 1
    from pg_database
    where datname = 'lumynex'
) \gexec

select 'create database airport owner lumynex'
where not exists (
    select 1
    from pg_database
    where datname = 'airport'
) \gexec

grant connect on database airport to harperjm, sysdba, lumynex;
grant connect on database lumynex to harperjm, sysdba, lumynex;
grant connect on database postgres to harperjm, sysdba, lumynex;
grant connect on database template1 to harperjm, sysdba, lumynex;

select exists (
    select 1
    from pg_roles
    where rolname = 'airport'
) as airport_role_exists \gset

\if :airport_role_exists
\connect airport
reassign owned by airport to lumynex;
drop owned by airport;
\connect lumynex
reassign owned by airport to lumynex;
drop owned by airport;
\connect postgres
reassign owned by airport to lumynex;
drop owned by airport;
drop role airport;
\endif
