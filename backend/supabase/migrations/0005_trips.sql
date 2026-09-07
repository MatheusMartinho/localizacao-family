-- "Me acompanha até eu chegar" + alvo do toque ("cadê você?").

-- Um toque agora pode ser endereçado a alguém específico.
alter table public.alerts
  add column if not exists target_id uuid references public.profiles (id);

-- Viagem em andamento: a pessoa avisa para onde está indo e a família
-- acompanha. A chegada é marcada pelo próprio aparelho de quem viaja, que é
-- quem tem a melhor informação de posição.
create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  traveler_id uuid not null references public.profiles (id) on delete cascade,
  destination_name text not null,
  destination_emoji text not null default '📍',
  destination_latitude double precision not null,
  destination_longitude double precision not null,
  destination_radius_m integer not null default 150,
  started_at timestamptz not null default now(),
  -- Previsão de chegada, quando o app consegue calcular a rota.
  eta timestamptz,
  arrived_at timestamptz,
  cancelled_at timestamptz
);

create index if not exists trips_family_idx on public.trips (family_id, started_at desc);

alter table public.trips enable row level security;

create policy trips_select on public.trips for select to authenticated
  using (private.is_family_member(family_id));

create policy trips_insert on public.trips for insert to authenticated
  with check (
    traveler_id = (select auth.uid())
    and private.is_family_member(family_id)
  );

-- Qualquer pessoa da família pode encerrar (ex.: "já chegou, pode parar").
create policy trips_update on public.trips for update to authenticated
  using (private.is_family_member(family_id));

grant select, insert, update on public.trips to authenticated;

alter publication supabase_realtime add table public.trips;
