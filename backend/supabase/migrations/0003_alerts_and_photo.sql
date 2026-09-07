-- Alarme de pânico (SOS), toques ("ping") e foto de perfil.

-- ─── Foto de perfil ─────────────────────────────────────────────────────────
-- Guardada como data URI (JPEG pequeno, ~256px) na própria linha do perfil:
-- evita criar bucket de Storage e políticas separadas para um app de família,
-- onde são poucas linhas e a foto viaja junto com o resto do perfil.
alter table public.profiles
  add column if not exists avatar_photo text;

-- ─── Alertas ────────────────────────────────────────────────────────────────
create table if not exists public.alerts (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  -- 'sos' = pânico (tela cheia + som); 'ping' = "me dá um sinal de vida".
  kind text not null check (kind in ('sos', 'ping')),
  latitude double precision,
  longitude double precision,
  place_hint text,
  created_at timestamptz not null default now(),
  -- Quem cancelou/atendeu, e quando.
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id)
);

create index if not exists alerts_family_created_idx
  on public.alerts (family_id, created_at desc);

alter table public.alerts enable row level security;

-- A família toda vê os alertas da família.
create policy alerts_select on public.alerts for select to authenticated
  using (private.is_family_member(family_id));

-- Só dá para disparar em nome de si mesmo, e só na própria família.
create policy alerts_insert on public.alerts for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and private.is_family_member(family_id)
  );

-- Qualquer pessoa da família pode marcar como resolvido ("estou indo").
create policy alerts_update on public.alerts for update to authenticated
  using (private.is_family_member(family_id));

grant select, insert, update on public.alerts to authenticated;

alter publication supabase_realtime add table public.alerts;
