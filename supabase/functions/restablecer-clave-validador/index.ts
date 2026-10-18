// supabase/functions/restablecer-clave-validador/index.ts
// Ajuste 3 (fase 4G): el admin genera una clave nueva para un validador.
// - Solo admin (o superadmin) activo.
// - Solo validadores activos y vigentes: no reactiva a uno deshabilitado.
// - La clave nueva se devuelve UNA sola vez; no se guarda en claro.
// - Queda registrado en auditoria_validadores.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface Entrada {
  validador_id: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return respuesta({ error: "Método no permitido" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return respuesta({ error: "No autenticado" }, 401);

    // Cliente con el JWT de quien llama: solo para verificar que es admin.
    const supabaseCliente = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user } } = await supabaseCliente.auth.getUser();
    if (!user) return respuesta({ error: "No autenticado" }, 401);

    const { data: perfil } = await supabaseCliente
      .from("usuarios")
      .select("rol, activo")
      .eq("id", user.id)
      .single();

    if (
      !["admin", "superadmin"].includes(perfil?.rol ?? "") ||
      perfil?.activo !== true
    ) {
      return respuesta(
        { error: "Solo un administrador puede restablecer claves" },
        403,
      );
    }

    const entrada: Entrada = await req.json();
    if (!entrada?.validador_id) {
      return respuesta({ exito: false, error: "Falta el validador" }, 400);
    }

    // Cliente service_role: solo se usa después de verificar el rol.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: validador } = await admin
      .from("usuarios")
      .select("id, ci, rol, activo, vigente_hasta, evento_asignado_id")
      .eq("id", entrada.validador_id)
      .maybeSingle();

    if (!validador || validador.rol !== "validador") {
      return respuesta({ exito: false, error: "El validador no existe" }, 400);
    }
    if (
      validador.activo !== true ||
      !validador.vigente_hasta ||
      new Date(validador.vigente_hasta) <= new Date()
    ) {
      return respuesta(
        {
          exito: false,
          error: "El validador está deshabilitado o vencido; no se puede restablecer su clave",
        },
        400,
      );
    }

    // 1. Auditoría primero: si falla, no se cambia la clave.
    const { data: registro, error: errorAuditoria } = await admin
      .from("auditoria_validadores")
      .insert({
        validador_id: validador.id,
        evento_id: validador.evento_asignado_id,
        accion: "restablecer_clave",
        realizado_por: user.id,
      })
      .select("id")
      .single();

    if (errorAuditoria || !registro) {
      return respuesta(
        { exito: false, error: "No se pudo registrar la auditoría. No se cambió la clave" },
        500,
      );
    }

    // 2. Clave nueva en Auth.
    const password = claveAleatoria(10);
    const { error: errorAuth } = await admin.auth.admin.updateUserById(
      validador.id,
      { password },
    );

    if (errorAuth) {
      // Deshacer el registro de auditoría de un cambio que no ocurrió.
      await admin.from("auditoria_validadores").delete().eq("id", registro.id);
      return respuesta(
        { exito: false, error: `No se pudo cambiar la clave: ${errorAuth.message}` },
        500,
      );
    }

    // La clave se devuelve UNA sola vez: no queda guardada en claro.
    return respuesta(
      {
        exito: true,
        codigo: validador.ci,
        password,
        vigente_hasta: validador.vigente_hasta,
      },
      200,
    );
  } catch (e) {
    return respuesta({ error: `Error inesperado: ${(e as Error).message}` }, 500);
  }
});

// Mismo alfabeto que crear-usuario: sin caracteres ambiguos (0/O, 1/l/I).
function claveAleatoria(largo: number): string {
  const alfabeto = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint32Array(largo));
  return Array.from(bytes, (b) => alfabeto[b % alfabeto.length]).join("");
}

function respuesta(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}