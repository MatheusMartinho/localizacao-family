-- Lugares da família: casa, trabalho, casa da vó.
--
-- São da família inteira (não de cada pessoa): quem cria um lugar cria para
-- todo mundo, e aí o app troca "Avenida Paulista" por "🏠 Em casa" para
-- qualquer parente que esteja dentro do raio.

create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  emoji text not null default '📍',
  latitude double precision not null,
  longitude double precision not null,
  -- Raio em metros. O mínimo evita que o GPS "saia" do lugar parado, e o
  -- máximo evita um lugar que engole a cidade inteira.
  radius_m integer not null default 150 check (radius_m between 50 and 2000),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists places_family_idx on public.places (family_id);

alter table public.places enable row level security;

create policy places_select on public.places for select to authenticated
  using (private.is_family_member(family_id));

create policy places_insert on public.places for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and private.is_family_member(family_id)
  );

create policy places_update on public.places for update to authenticated
  using (private.is_family_member(family_id));

create policy places_delete on public.places for delete to authenticated
  using (private.is_family_member(family_id));

grant select, insert, update, delete on public.places to authenticated;

alter publication supabase_realtime add table public.places;
