-- Cria o perfil automaticamente quando nasce um usuário em auth.users.
--
-- Antes o app criava o perfil pelo cliente logo após o cadastro, o que quebra
-- quando "Confirm email" está ligado: sem sessão, o usuário ainda é anônimo e
-- o RLS (corretamente) recusa a inserção. O trigger roda no banco e não
-- depende de sessão nenhuma.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_emoji, avatar_color)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Eu'),
    coalesce(nullif(new.raw_user_meta_data ->> 'avatar_emoji', ''), '🙂'),
    coalesce(nullif(new.raw_user_meta_data ->> 'avatar_color', ''), '#D4FF3F')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: quem já se cadastrou antes do trigger existir ganha o perfil agora.
insert into public.profiles (id, display_name, avatar_emoji, avatar_color)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'display_name', ''), 'Eu'),
  coalesce(nullif(u.raw_user_meta_data ->> 'avatar_emoji', ''), '🙂'),
  coalesce(nullif(u.raw_user_meta_data ->> 'avatar_color', ''), '#D4FF3F')
from auth.users u
on conflict (id) do nothing;
