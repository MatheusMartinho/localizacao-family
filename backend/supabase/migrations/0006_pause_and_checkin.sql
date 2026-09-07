-- Pausa visível para a família + check-in ("cheguei bem").

-- ─── Pausa do compartilhamento ──────────────────────────────────────────────
-- Antes a pausa era só local: quem pausava simplesmente parava de aparecer, e
-- para a família era indistinguível de celular sem bateria ou sem sinal. Agora
-- o estado é publicado, então o app pode dizer "pausado há 20 min" em vez de
-- deixar o pin envelhecendo no mapa sem explicação.
alter table public.locations
  add column if not exists sharing_paused boolean not null default false,
  add column if not exists paused_at timestamptz;

-- ─── Check-in ───────────────────────────────────────────────────────────────
-- O contrário do SOS: "cheguei, está tudo bem". Reaproveita a tabela de
-- alertas, que já tem RLS, realtime e a posição junto.
alter table public.alerts
  drop constraint if exists alerts_kind_check;
alter table public.alerts
  add constraint alerts_kind_check check (kind in ('sos', 'ping', 'checkin'));
