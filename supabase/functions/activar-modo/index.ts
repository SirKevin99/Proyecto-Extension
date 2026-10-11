// supabase/functions/activar-modo/index.ts
//
// Habilita el modo de asistencia (entrada | salida) de una sesión.
// El validador debe reingresar SU contraseña; se verifica en el servidor
// contra Supabase Auth y recién después se llama a la RPC
// activar_modo_asistencia, que solo puede ejecutar service_role.
//
// Body: { sesion_id: string, modo: 'entrada' | 'salida', password: string }
// OK:   { exito: true, modo_hasta: string | null }
// Error: { error: string }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respuesta(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return respuesta({ error: "Método no permitido" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. Quién llama (JWT del validador).
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return respuesta({ error: "No autenticado" }, 401);

  const cliente = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: errUser } = await cliente.auth.getUser();
  if (errUser || !user || !user.email) {
    return respuesta({ error: "Sesión inválida" }, 401);
  }

  // 2. Entrada.
  let body: { sesion_id?: string; modo?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return respuesta({ error: "Cuerpo inválido" }, 400);
  }
  const { sesion_id, modo, password } = body;
  if (!sesion_id || typeof sesion_id !== "string") {
    return respuesta({ error: "Falta la sesión" }, 400);
  }
  if (modo !== "entrada" && modo !== "salida") {
    return respuesta({ error: "Modo inválido" }, 400);
  }
  if (!password || typeof password !== "string") {
    return respuesta({ error: "Ingresá tu contraseña" }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 3. Perfil: debe ser un validador vigente.
  const { data: perfil, error: errPerfil } = await admin
    .from("usuarios")
    .select("rol, activo, vigente_hasta")
    .eq("id", user.id)
    .maybeSingle();
  if (errPerfil || !perfil) {
    return respuesta({ error: "Usuario no encontrado" }, 403);
  }
  if (perfil.rol !== "validador") {
    return respuesta({
      error: "Solo un validador puede habilitar la asistencia",
    }, 403);
  }
  if (!perfil.activo) {
    return respuesta({ error: "Validador deshabilitado" }, 403);
  }
  if (perfil.vigente_hasta && new Date(perfil.vigente_hasta) < new Date()) {
    return respuesta({ error: "Tu acceso como validador venció" }, 403);
  }

  // 4. Verificación de contraseña en el servidor.
  //    Cliente aislado: no persiste sesión y no toca la del llamador.
  //    Si el usuario está baneado, Auth también rechaza el login.
  const verificador = createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  const { error: errPass } = await verificador.auth.signInWithPassword({
    email: user.email,
    password,
  });
  if (errPass) return respuesta({ error: "Contraseña incorrecta" }, 401);

  // 5. Activar (la RPC valida que el validador corresponda al evento,
  //    la ventana horaria, el modo único activo, etc.).
  const { data, error: errRpc } = await admin.rpc("activar_modo_asistencia", {
    p_sesion_id: sesion_id,
    p_validador_id: user.id,
    p_modo: modo,
  });
  if (errRpc) return respuesta({ error: errRpc.message }, 400);

  // La RPC puede devolver el timestamp directo o una fila/objeto.
  let modoHasta: string | null = null;
  if (typeof data === "string") modoHasta = data;
  else if (Array.isArray(data) && data[0]) {
    modoHasta = data[0].modo_hasta ?? null;
  } else if (data && typeof data === "object") {
    modoHasta = (data as any).modo_hasta ?? null;
  }

  return respuesta({ exito: true, modo_hasta: modoHasta });
});
