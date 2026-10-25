-- Tables for the airport load test. Safe to run again.
alter schema public owner to lumynex;
grant all on schema public to lumynex;
set role lumynex;

create table if not exists airport (
    id integer generated always as identity primary key
    , code text not null unique
    , name text not null
    , city text not null
);

create table if not exists flight (
    id integer generated always as identity primary key
    , origin_id integer not null references airport (id)
    , dest_id integer not null references airport (id)
    , departs_at timestamp not null
    , seats integer not null
);

create table if not exists booking (
    id bigint generated always as identity primary key
    , flight_id integer not null references flight (id)
    , passenger text not null
    , seats integer not null
    , created_at timestamptz not null default now()
);

create table if not exists load_run (
    id bigint generated always as identity primary key
    , sessions integer not null
    , duration_s integer not null
    , state text not null
    , started_at timestamptz not null default now()
    , finished_at timestamptz
    , requests integer not null default 0
    , errors integer not null default 0
    , p50_ms numeric
    , p95_ms numeric
    , note text not null default ''
);

create index if not exists flight_origin_departs_idx
    on flight (origin_id, departs_at);

create index if not exists booking_flight_idx
    on booking (flight_id);

insert into airport (
    code
    , name
    , city
)
select v.code
 , v.name
 , v.city
from (
    values
        ('IND', 'Indianapolis International', 'Indianapolis')
        , ('ORD', 'Chicago O Hare', 'Chicago')
        , ('MDW', 'Chicago Midway', 'Chicago')
        , ('CVG', 'Cincinnati', 'Hebron')
        , ('SDF', 'Louisville', 'Louisville')
        , ('DAY', 'Dayton', 'Dayton')
        , ('CMH', 'Columbus', 'Columbus')
        , ('CLE', 'Cleveland Hopkins', 'Cleveland')
        , ('DTW', 'Detroit Metro', 'Detroit')
        , ('ATL', 'Hartsfield Jackson', 'Atlanta')
        , ('DFW', 'Dallas Fort Worth', 'Dallas')
        , ('DEN', 'Denver', 'Denver')
        , ('LAX', 'Los Angeles', 'Los Angeles')
        , ('SFO', 'San Francisco', 'San Francisco')
        , ('SEA', 'Seattle Tacoma', 'Seattle')
        , ('JFK', 'Kennedy', 'New York')
        , ('EWR', 'Newark Liberty', 'Newark')
        , ('BOS', 'Boston Logan', 'Boston')
        , ('MIA', 'Miami', 'Miami')
        , ('MCO', 'Orlando', 'Orlando')
        , ('PHX', 'Phoenix Sky Harbor', 'Phoenix')
        , ('LAS', 'Harry Reid', 'Las Vegas')
        , ('MSP', 'Minneapolis Saint Paul', 'Minneapolis')
        , ('BNA', 'Nashville', 'Nashville')
) as v (
    code
    , name
    , city
)
where not exists (
    select 1
    from airport a
    where a.code = v.code
);

insert into flight (
    origin_id
    , dest_id
    , departs_at
    , seats
)
select o.id
 , d.id
 , timestamp '2026-10-24 06:00' + (n.n || ' minutes')::interval
 , 180
from generate_series(1, 4000) as n (n)
join airport o
    on o.id = 1 + (n.n % 24)
join airport d
    on d.id = 1 + ((n.n * 7) % 24)
where o.id <> d.id
 and not exists (
    select 1
    from flight f
);

reset role;
