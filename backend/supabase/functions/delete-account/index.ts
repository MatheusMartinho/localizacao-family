// Exclusão de conta — exigida pela App Store (diretriz 5.1.1(v)).
//
// Apagar um usuário do Auth exige a chave `service_role`, que ignora o RLS e
// portanto nunca pode estar dentro do app. Daí esta função: ela roda no
// servidor, recebe o JWT de quem pediu, descobre quem é a pessoa **pelo
// próprio token** e apaga só essa conta. Não existe parâmetro de "qual
// usuário" — assim não há como pedir a exclusão de outra pessoa.
//
// O resto (perfil, localização, histórico, alertas, viagens, participação nas
// famílias) cai por cascata; a migração 0008 acertou as chaves estrangeiras
// que travavam isso.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "missing token" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Quem é o dono deste token? Se o token não valer, não apaga nada.
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData?.user) return json({ error: "invalid token" }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await admin.auth.admin.deleteUser(userData.user.id);
  if (error) return json({ error: error.message }, 500);

  return json({ deleted: true });
});
