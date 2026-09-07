-- Família: esquema inicial
-- Perfis, famílias, membros, localização ao vivo + histórico, RLS e realtime.

create schema if not exists private;

-- ─── Tabelas ────────────────────────────────────────────────────────────────

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_emoji text not null default '🙂',
  avatar_color text not null default '#D4FF3F',
  created_at timestamptz not null default now()
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  invite_code text not null unique,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (family_id, profile_id)
);
create index family_members_profile_id_idx on public.family_members (profile_id);

-- Localização ao vivo: exatamente uma linha por pessoa, atualizada por upsert.
create table public.locations (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  speed_mps double precision,
  heading double precision,
  battery_pct smallint check (battery_pct between 0 and 100),
  is_moving boolean not null default false,
  state_since timestamptz not null default now(),
  place_hint text,
  updated_at timestamptz not null default now()
);

-- Trilha (histórico) para desenhar rotas percorridas.
create table public.location_history (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  recorded_at timestamptz not null default now()
);
create index location_history_profile_recorded_idx
  on public.location_history (profile_id, recorded_at desc);

-- ─── Funções auxiliares (security definer, search_path fixo) ────────────────

-- O usuário atual pertence à família?
create or replace function private.is_family_member(fid uuid)
returns boolean
language sql security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.family_members
    where family_id = fid and profile_id = (select auth.uid())
  );
$$;

-- O usuário atual divide alguma família com `other`?
create or replace function private.shares_family_with(other uuid)
returns boolean
language sql security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_members a
    join public.family_members b on a.family_id = b.family_id
    where a.profile_id = (select auth.uid()) and b.profile_id = other
  );
$$;

-- ─── RPCs ───────────────────────────────────────────────────────────────────

-- Cria família com código de convite e adiciona o criador como owner.
create or replace function public.create_family(family_name text)
returns public.families
language plpgsql security definer
set search_path = ''
as $$
declare
  fam public.families;
  code text;
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated';
  end if;
  code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  insert into public.families (name, invite_code, created_by)
  values (family_name, code, (select auth.uid()))
  returning * into fam;
  insert into public.family_members (family_id, profile_id, role)
  values (fam.id, (select auth.uid()), 'owner');
  return fam;
end;
$$;

-- Entra numa família pelo código de convite.
create or replace function public.join_family(code text)
returns public.families
language plpgsql security definer
set search_path = ''
as $$
declare
  fam public.families;
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated';
  end if;
  select * into fam from public.families where invite_code = upper(trim(code));
  if fam.id is null then
    raise exception 'invalid invite code';
  end if;
  insert into public.family_members (family_id, profile_id)
  values (fam.id, (select auth.uid()))
  on conflict do nothing;
  return fam;
end;
$$;

-- ─── RLS ────────────────────────────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.locations enable row level security;
alter table public.location_history enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_family_with(id));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()));

create policy families_select on public.families for select to authenticated
  using (private.is_family_member(id));

create policy family_members_select on public.family_members for select to authenticated
  using (private.is_family_member(family_id));
create policy family_members_delete on public.family_members for delete to authenticated
  using (profile_id = (select auth.uid()));

create policy locations_select on public.locations for select to authenticated
  using (profile_id = (select auth.uid()) or private.shares_family_with(profile_id));
create policy locations_insert on public.locations for insert to authenticated
  with check (profile_id = (select auth.uid()));
create policy locations_update on public.locations for update to authenticated
  using (profile_id = (select auth.uid()));

create policy location_history_select on public.location_history for select to authenticated
  using (profile_id = (select auth.uid()) or private.shares_family_with(profile_id));
create policy location_history_insert on public.location_history for insert to authenticated
  with check (profile_id = (select auth.uid()));

-- ─── Privilégios da Data API ────────────────────────────────────────────────
-- Explícitos para a migração não depender do "Automatically expose new tables"
-- do painel. O RLS acima é quem de fato filtra as linhas.

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.profiles, public.families, public.family_members,
  public.locations, public.location_history
  to authenticated;
grant execute on function public.create_family(text), public.join_family(text)
  to authenticated;

-- ─── Realtime ───────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.locations;
