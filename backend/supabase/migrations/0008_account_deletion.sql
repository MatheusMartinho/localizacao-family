-- Exclusão de conta (App Store, diretriz 5.1.1(v)).
--
-- Apagar o usuário em auth.users cascateia para `profiles`, e de lá para
-- `family_members`, `locations`, `location_history`, `alerts.sender_id` e
-- `trips.traveler_id`. Mas quatro chaves estrangeiras **sem** cascata travavam
-- tudo — a mais grave sendo `families.created_by`, que é `not null`: como quem
-- cria a família é sempre alguém, na prática nenhum usuário real conseguia ser
-- apagado. O `delete` estourava com violação de chave estrangeira.
--
-- A regra aqui é: a saída de uma pessoa não pode destruir o que é da família.
-- A família não morre porque quem a criou saiu; o lugar marcado não some porque
-- quem o marcou saiu. Esses campos viram apenas "não se sabe mais quem foi".

-- ─── families.created_by ────────────────────────────────────────────────────
alter table public.families
  alter column created_by drop not null;

alter table public.families
  drop constraint if exists families_created_by_fkey;
alter table public.families
  add constraint families_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

-- ─── places.created_by ──────────────────────────────────────────────────────
alter table public.places
  alter column created_by drop not null;

alter table public.places
  drop constraint if exists places_created_by_fkey;
alter table public.places
  add constraint places_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

-- ─── alerts.resolved_by e alerts.target_id ──────────────────────────────────
alter table public.alerts
  drop constraint if exists alerts_resolved_by_fkey;
alter table public.alerts
  add constraint alerts_resolved_by_fkey
  foreign key (resolved_by) references public.profiles (id) on delete set null;

alter table public.alerts
  drop constraint if exists alerts_target_id_fkey;
alter table public.alerts
  add constraint alerts_target_id_fkey
  foreign key (target_id) references public.profiles (id) on delete set null;

-- ─── Família sem ninguém é lixo ─────────────────────────────────────────────
-- Quando sai o último membro (por exclusão de conta ou por "sair da família"),
-- a família e tudo que pende dela — lugares, viagens, alertas — vão junto por
-- cascata. Sem isto sobrariam famílias fantasma segurando localizações antigas.
create or replace function private.delete_empty_family()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.family_members where family_id = old.family_id
  ) then
    delete from public.families where id = old.family_id;
  end if;
  return old;
end;
$$;

drop trigger if exists on_family_member_removed on public.family_members;
create trigger on_family_member_removed
  after delete on public.family_members
  for each row execute function private.delete_empty_family();
