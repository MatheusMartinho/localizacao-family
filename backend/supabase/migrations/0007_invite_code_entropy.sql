-- Código de convite à prova de força bruta.
--
-- O código original tinha 6 caracteres hexadecimais (os 6 primeiros de um UUID):
-- 16^6 = 16,7 milhões de combinações. Medindo o endpoint real, o `join_family`
-- responde a ~2 req/s numa conexão; com 50 conexões em paralelo o espaço
-- inteiro é varrido em ~50 h, e o RPC é um oráculo perfeito, porque distingue
-- "invalid invite code" de sucesso. Entrar numa família dá acesso à localização
-- ao vivo de todo mundo nela — o preço do erro é alto demais para 50 h de VPS.
--
-- Agora são 10 caracteres de um alfabeto de 32 (sem I, O, 0 e 1, que as pessoas
-- confundem ao ditar): 32^10 ≈ 1,1 quatrilhão. A mesma varredura levaria mais
-- de 300 mil anos.

create or replace function private.generate_invite_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text := '';
  i integer;
begin
  for i in 1..10 loop
    -- `gen_random_bytes` vem do pgcrypto e é criptograficamente seguro;
    -- `random()` não é, e um gerador previsível derrubaria toda a entropia.
    code := code || substr(
      alfabeto,
      1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(alfabeto)),
      1
    );
  end loop;
  return code;
end;
$$;

-- Famílias novas já nascem com o código longo.
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
  -- Colisão em 32^10 é remota, mas o `unique` da coluna transformaria isso em
  -- erro na cara do usuário; tentar de novo é barato.
  loop
    code := private.generate_invite_code();
    exit when not exists (select 1 from public.families where invite_code = code);
  end loop;
  insert into public.families (name, invite_code, created_by)
  values (family_name, code, (select auth.uid()))
  returning * into fam;
  insert into public.family_members (family_id, profile_id, role)
  values (fam.id, (select auth.uid()), 'owner');
  return fam;
end;
$$;

-- Famílias que já existem trocam de código. Ninguém é expulso: quem já é membro
-- continua membro; o que deixa de valer é o código antigo para **entrar**.
update public.families
set invite_code = private.generate_invite_code()
where length(invite_code) < 10;
