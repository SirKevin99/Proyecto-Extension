// supabase/functions/crear-usuario/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const DOMINIO = "@uninorte.edu.py";
const ZONA = "-03:00"; // America/Asuncion

interface Entrada {
  rol: "alumno" | "admin" | "validador";
  nombre_completo: string;
  // alumno / admin
  ci?: string;
  correo_local?: string;
  carrera?: string;
  password?: string;
  // validador
  evento_id?: string;
  vigente_hasta?: string; // ISO opcional; por defecto hora_fin + 1 h
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

    if (perfil?.rol !== "admin" || perfil?.activo !== true) {
      return respuesta(
        { error: "Solo un administrador puede crear usuarios" },
        403,
      );
    }

    // Cliente service_role: solo se usa después de verificar el rol.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const entrada: Entrada = await req.json();

    const resultado = entrada.rol === "validador"
      ? await crearValidador(admin, entrada)
      : await crearUsuarioNormal(admin, entrada);

    return respuesta(resultado, resultado.exito ? 200 : 400);
  } catch (e) {
    return respuesta({ error: `Error inesperado: ${(e as Error).message}` }, 500);
  }
});

// ---------------------------------------------------------------
// Alumno / Admin: el admin define C.I., correo y contraseña
// ---------------------------------------------------------------
async function crearUsuarioNormal(
  admin: ReturnType<typeof createClient>,
  u: Entrada,
) {
  if (
    !["alumno", "admin"].includes(u.rol) ||
    !u.nombre_completo?.trim() ||
    !u.ci?.trim() ||
    !u.correo_local?.trim() ||
    !u.carrera?.trim() ||
    !u.password
  ) {
    return { exito: false, error: "Faltan campos obligatorios o rol inválido" };
  }
  if (!/^\d{4,10}$/.test(u.ci.trim())) {
    return { exito: false, error: "La C.I. debe tener entre 4 y 10 dígitos" };
  }
  if (!/^[a-zA-Z0-9._-]+$/.test(u.correo_local.trim())) {
    return { exito: false, error: "Usuario de correo inválido" };
  }
  if (u.password.length < 8) {
    return { exito: false, error: "La contraseña debe tener al menos 8 caracteres" };
  }

  const correo = `${u.correo_local.trim().toLowerCase()}${DOMINIO}`;

  const { data: existente } = await admin
    .from("usuarios")
    .select("id")
    .or(`ci.eq.${u.ci.trim()},correo_institucional.eq.${correo}`)
    .maybeSingle();
  if (existente) {
    return { exito: false, error: "Ya existe un usuario con esa C.I. o correo" };
  }

  return await altaCompleta(admin, {
    correo,
    password: u.password,
    perfil: {
      nombre_completo: u.nombre_completo.trim(),
      ci: u.ci.trim(),
      correo_institucional: correo,
      carrera: u.carrera.trim(),
      rol: u.rol,
    },
  });
}

// ---------------------------------------------------------------
// Validador temporal: código y clave los genera el servidor
// ---------------------------------------------------------------
async function crearValidador(
  admin: ReturnType<typeof createClient>,
  u: Entrada,
) {
  if (!u.nombre_completo?.trim() || !u.evento_id) {
    return { exito: false, error: "Faltan el nombre y el evento asignado" };
  }

  const { data: evento } = await admin
    .from("eventos")
    .select("id, fecha, hora_fin, activo")
    .eq("id", u.evento_id)
    .maybeSingle();

  if (!evento || !evento.activo) {
    return { exito: false, error: "El evento no existe o no está activo" };
  }

  // Vigencia: la indicada, o hora_fin del evento + 1 hora.
  let vigenteHasta: Date;
  if (u.vigente_hasta) {
    vigenteHasta = new Date(u.vigente_hasta);
  } else {
    const horaFin = evento.hora_fin ?? "23:00:00";
    vigenteHasta = new Date(
      new Date(`${evento.fecha}T${horaFin}${ZONA}`).getTime() + 60 * 60 * 1000,
    );
  }
  if (isNaN(vigenteHasta.getTime()) || vigenteHasta <= new Date()) {
    return { exito: false, error: "La vigencia debe ser una fecha futura" };
  }

  // Un solo validador activo por evento.
  const { data: yaExiste } = await admin
    .from("usuarios")
    .select("id")
    .eq("rol", "validador")
    .eq("evento_asignado_id", u.evento_id)
    .eq("activo", true)
    .gt("vigente_hasta", new Date().toISOString())
    .maybeSingle();
  if (yaExiste) {
    return {
      exito: false,
      error: "Este evento ya tiene un validador activo. Desactivalo primero",
    };
  }

  // Código VAL-#### único (se guarda en la columna ci).
  let codigo = "";
  for (let i = 0; i < 10; i++) {
    const candidato = `VAL-${aleatorioNumerico(4)}`;
    const { data: choque } = await admin
      .from("usuarios").select("id").eq("ci", candidato).maybeSingle();
    if (!choque) { codigo = candidato; break; }
  }
  if (!codigo) {
    return { exito: false, error: "No se pudo generar un código único" };
  }

  const password = claveAleatoria(10);
  const correo = `${codigo.toLowerCase()}${DOMINIO}`; // buzón ficticio

  const res = await altaCompleta(admin, {
    correo,
    password,
    perfil: {
      nombre_completo: u.nombre_completo.trim(),
      ci: codigo,
      correo_institucional: correo,
      carrera: "Validador temporal",
      rol: "validador",
      evento_asignado_id: u.evento_id,
      vigente_hasta: vigenteHasta.toISOString(),
    },
  });

  if (!res.exito) return res;

  // La clave se devuelve UNA sola vez: no queda guardada en claro.
  return {
    exito: true,
    codigo,
    password,
    correo,
    vigente_hasta: vigenteHasta.toISOString(),
  };
}

// ---------------------------------------------------------------
// Auth + perfil, con rollback si falla el segundo paso
// ---------------------------------------------------------------
async function altaCompleta(
  admin: ReturnType<typeof createClient>,
  d: { correo: string; password: string; perfil: Record<string, unknown> },
) {
  const { data, error } = await admin.auth.admin.createUser({
    email: d.correo,
    password: d.password,
    email_confirm: true,
  });
  if (error || !data.user) {
    return { exito: false, error: error?.message ?? "No se pudo crear en Auth" };
  }

  const { error: errorInsert } = await admin
    .from("usuarios")
    .insert({ id: data.user.id, ...d.perfil });

  if (errorInsert) {
    await admin.auth.admin.deleteUser(data.user.id);
    return { exito: false, error: `No se pudo guardar el perfil: ${errorInsert.message}` };
  }

  return { exito: true, correo: d.correo };
}

function aleatorioNumerico(largo: number): string {
  const bytes = crypto.getRandomValues(new Uint32Array(largo));
  return Array.from(bytes, (b) => (b % 10).toString()).join("");
}

// Sin caracteres ambiguos (0/O, 1/l/I) para que se pueda dictar
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