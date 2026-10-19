// supabase/functions/alta-masiva-alumnos/index.ts
//
// Fase 6: alta masiva de alumnos por CSV (solo superadmin).
//
// La app lee el CSV, arma la vista previa y envía las filas en tandas de
// hasta 50. Esta función vuelve a validar TODO en el servidor y registra
// cada fila en cargas_masivas_detalle (script 18).
//
// Decisiones (18/10, Kevin y Pedro):
// - Solo alumnos. La C.I. es el único identificador.
// - Clave por defecto: C.I. + "abc" (riesgo aceptado por Kevin).
// - C.I. existente de un alumno: omitir o actualizar (nombre, carrera y
//   horas; nunca correo ni clave) y, si está desactivado, reactivar o no.
// - C.I. existente de otro rol, correo usado por otra C.I., datos
//   inválidos o repetidos en el archivo: fila rechazada.
// - Carga parcial: cada fila tiene su propio resultado.
//
// Auditoría:
// - Altas: insert con service_role + creado_por (trigger del script 17).
// - Actualizar / reactivar: editar_usuario y reactivar_usuario (script 16)
//   con el JWT del superadmin, para que figure como autor.
//
// Reintentos: si una tanda se reenvía, las filas ya registradas en el
// detalle no se reprocesan; se devuelve el resultado guardado.
//
// Filas con error en la vista previa: la app las envía con
// "rechazo_previo" para que queden registradas en el lote como
// rechazadas, sin procesarlas (p. ej. C.I. repetida: todas las filas
// involucradas son error, no solo la segunda).
//
// Body:
// {
//   carga_id?: string,         // falta en la primera tanda
//   nombre_archivo?: string,   // obligatorio en la primera tanda
//   total_filas?: number,      // obligatorio en la primera tanda (1..300)
//   ultima_tanda?: boolean,    // true en la última: cierra el lote
//   filas: Fila[]              // 1..50
// }
// OK:    { exito: true, carga_id, resultados: Resultado[] }
// Error: { exito: false, error }

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DOMINIO = "@uninorte.edu.py";
const SUFIJO_CLAVE = "abc"; // clave por defecto = C.I. + "abc"
const MAX_FILAS_ARCHIVO = 300;
const MAX_FILAS_TANDA = 50;

const RE_CI = /^\d{4,10}$/;
const RE_CORREO = /^[a-z0-9._-]+@uninorte\.edu\.py$/;
const RE_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Accion = "crear" | "actualizar" | "omitir";
type ResultadoFila = "creado" | "actualizado" | "omitido" | "rechazado";

interface Fila {
  fila: number;
  ci?: string;
  nombre_completo?: string;
  correo?: string;
  carrera?: string;
  horas_requeridas?: string | number;
  accion: Accion;
  reactivar?: boolean;
  // Error detectado en la vista previa (p. ej. C.I. repetida en el
  // archivo): la fila se registra como rechazada sin procesarla.
  rechazo_previo?: string;
}

interface Entrada {
  carga_id?: string;
  nombre_archivo?: string;
  total_filas?: number;
  ultima_tanda?: boolean;
  filas?: Fila[];
}

interface Resultado {
  fila: number;
  resultado: ResultadoFila;
  reactivado: boolean;
  error: string | null;
  usuario_id: string | null;
}

interface Existente {
  id: string;
  ci: string;
  correo_institucional: string;
  rol: string;
  activo: boolean;
}

interface Contexto {
  admin: SupabaseClient;    // service_role
  cliente: SupabaseClient;  // JWT del superadmin
  autorId: string;
  carreras: Set<string>;
  porCi: Map<string, Existente>;
  porCorreo: Map<string, Existente>;
  vistosCi: Set<string>;
  vistosCorreo: Set<string>;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  if (req.method !== "POST") {
    return respuesta({ exito: false, error: "Método no permitido" }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1. Quién llama ---------------------------------------------
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return respuesta({ exito: false, error: "No autenticado" }, 401);
    }

    // Cliente con el JWT del superadmin: identifica a quien llama y
    // ejecuta editar_usuario / reactivar_usuario con su autoría.
    const cliente = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user } } = await cliente.auth.getUser();
    if (!user) {
      return respuesta({ exito: false, error: "No autenticado" }, 401);
    }

    // Cliente service_role: solo se usa después de verificar el rol.
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: perfil } = await admin
      .from("usuarios")
      .select("rol, activo")
      .eq("id", user.id)
      .maybeSingle();
    if (perfil?.rol !== "superadmin" || perfil?.activo !== true) {
      return respuesta(
        { exito: false, error: "Solo el superadmin puede usar la carga masiva" },
        403,
      );
    }

    // 2. Entrada ------------------------------------------------
    let body: Entrada;
    try {
      body = await req.json();
    } catch {
      return respuesta({ exito: false, error: "Cuerpo inválido" }, 400);
    }

    const filas = Array.isArray(body.filas) ? body.filas : [];
    if (filas.length < 1 || filas.length > MAX_FILAS_TANDA) {
      return respuesta({
        exito: false,
        error: `Cada tanda debe tener entre 1 y ${MAX_FILAS_TANDA} filas`,
      }, 400);
    }
    const numeros = filas.map((f) => f?.fila);
    if (
      numeros.some((n) =>
        !Number.isInteger(n) || n < 1 || n > MAX_FILAS_ARCHIVO
      ) ||
      new Set(numeros).size !== numeros.length
    ) {
      return respuesta(
        { exito: false, error: "Números de fila inválidos o repetidos" },
        400,
      );
    }
    if (
      filas.some((f) => !["crear", "actualizar", "omitir"].includes(f.accion))
    ) {
      return respuesta({ exito: false, error: "Acción inválida" }, 400);
    }

    // 3. Lote ---------------------------------------------------
    const carga = await obtenerOCrearCarga(admin, body, user.id);
    if ("error" in carga) {
      return respuesta({ exito: false, error: carga.error }, 400);
    }
    if (numeros.some((n) => n > carga.total_filas)) {
      return respuesta({
        exito: false,
        error: "Hay filas fuera del total declarado para el archivo",
      }, 400);
    }

    // 4. Filas ya registradas (reintento): no se reprocesan --------
    const { data: previas, error: errPrevias } = await admin
      .from("cargas_masivas_detalle")
      .select("fila, resultado, reactivado, error, usuario_id")
      .eq("carga_id", carga.id)
      .in("fila", numeros);
    if (errPrevias) {
      return respuesta({
        exito: false,
        error: "No se pudo leer el detalle de la carga",
      }, 500);
    }
    const yaRegistradas = new Map<number, Resultado>(
      (previas ?? []).map((p) => [p.fila as number, p as Resultado] as [number, Resultado]),
    );

    // 5. Datos de referencia -------------------------------------
    const { data: carrerasData, error: errCarreras } = await admin
      .from("carreras")
      .select("nombre")
      .eq("activa", true);
    if (errCarreras) {
      return respuesta({
        exito: false,
        error: "No se pudo leer la lista de carreras",
      }, 500);
    }

    // Solo valores con formato válido van al filtro .in()
    const cis = [...new Set(
      filas.map((f) => texto(f.ci)).filter((c) => RE_CI.test(c)),
    )];
    const correos = [...new Set(
      filas.map((f) => texto(f.correo).toLowerCase())
        .filter((c) => RE_CORREO.test(c)),
    )];

    const porCi = new Map<string, Existente>();
    const porCorreo = new Map<string, Existente>();
    const columnas = "id, ci, correo_institucional, rol, activo";

    if (cis.length > 0) {
      const { data, error } = await admin
        .from("usuarios").select(columnas).in("ci", cis);
      if (error) {
        return respuesta({
          exito: false,
          error: "No se pudo verificar las C.I. existentes",
        }, 500);
      }
      for (const u of (data ?? []) as Existente[]) porCi.set(u.ci, u);
    }
    if (correos.length > 0) {
      const { data, error } = await admin
        .from("usuarios").select(columnas).in("correo_institucional", correos);
      if (error) {
        return respuesta({
          exito: false,
          error: "No se pudo verificar los correos existentes",
        }, 500);
      }
      for (const u of (data ?? []) as Existente[]) {
        porCorreo.set(u.correo_institucional.toLowerCase(), u);
      }
    }

    const ctx: Contexto = {
      admin,
      cliente,
      autorId: user.id,
      carreras: new Set((carrerasData ?? []).map((c) => c.nombre as string)),
      porCi,
      porCorreo,
      vistosCi: new Set(),
      vistosCorreo: new Set(),
    };

    // 6. Procesamiento fila por fila -----------------------------
    const resultados: Resultado[] = [];
    for (const f of [...filas].sort((a, b) => a.fila - b.fila)) {
      const previa = yaRegistradas.get(f.fila);
      if (previa) {
        resultados.push(previa);
        continue;
      }

      let r: Resultado;
      const rechazoPrevio = texto(f.rechazo_previo).slice(0, 300);
      try {
        r = rechazoPrevio
          ? resultadoDe(f, "rechazado", rechazoPrevio)
          : await procesarFila(ctx, f);
      } catch (e) {
        r = resultadoDe(f, "rechazado", `Error inesperado: ${(e as Error).message}`);
      }

      const { error: errDetalle } = await admin
        .from("cargas_masivas_detalle")
        .insert({
          carga_id: carga.id,
          fila: f.fila,
          ci: texto(f.ci),
          nombre_completo: texto(f.nombre_completo),
          correo: texto(f.correo),
          carrera: texto(f.carrera),
          horas_requeridas: texto(f.horas_requeridas),
          accion: f.accion,
          reactivar: f.reactivar === true,
          resultado: r.resultado,
          reactivado: r.reactivado,
          error: r.error,
          usuario_id: r.usuario_id,
        });
      if (errDetalle) {
        r.error = (r.error ? `${r.error} · ` : "") +
          "No se pudo registrar en la auditoría del lote";
      }
      resultados.push(r);
    }

    // 7. Cierre del lote -----------------------------------------
    if (body.ultima_tanda === true) {
      await admin
        .from("cargas_masivas")
        .update({ finalizada_en: new Date().toISOString() })
        .eq("id", carga.id)
        .is("finalizada_en", null);
    }

    return respuesta({ exito: true, carga_id: carga.id, resultados }, 200);
  } catch (e) {
    return respuesta(
      { exito: false, error: `Error inesperado: ${(e as Error).message}` },
      500,
    );
  }
});

// ---------------------------------------------------------------
// Lote: se crea en la primera tanda; las siguientes lo reutilizan
// ---------------------------------------------------------------
async function obtenerOCrearCarga(
  admin: SupabaseClient,
  body: Entrada,
  autorId: string,
): Promise<{ id: string; total_filas: number } | { error: string }> {
  if (body.carga_id) {
    if (!RE_UUID.test(body.carga_id)) return { error: "La carga no existe" };
    const { data } = await admin
      .from("cargas_masivas")
      .select("id, realizado_por, total_filas, finalizada_en")
      .eq("id", body.carga_id)
      .maybeSingle();
    if (!data || data.realizado_por !== autorId) {
      return { error: "La carga no existe" };
    }
    if (data.finalizada_en) return { error: "Esta carga ya fue finalizada" };
    return { id: data.id, total_filas: data.total_filas };
  }

  const nombre = texto(body.nombre_archivo);
  const total = body.total_filas;
  if (!nombre) return { error: "Falta el nombre del archivo" };
  if (
    typeof total !== "number" || !Number.isInteger(total) ||
    total < 1 || total > MAX_FILAS_ARCHIVO
  ) {
    return {
      error: `El archivo debe tener entre 1 y ${MAX_FILAS_ARCHIVO} filas`,
    };
  }

  const { data, error } = await admin
    .from("cargas_masivas")
    .insert({ realizado_por: autorId, nombre_archivo: nombre, total_filas: total })
    .select("id, total_filas")
    .single();
  if (error || !data) return { error: "No se pudo registrar la carga" };
  return { id: data.id, total_filas: data.total_filas };
}

// ---------------------------------------------------------------
// Una fila
// ---------------------------------------------------------------
async function procesarFila(ctx: Contexto, f: Fila): Promise<Resultado> {
  const ci = texto(f.ci);
  const nombre = texto(f.nombre_completo).replace(/\s+/g, " ");
  const correo = texto(f.correo).toLowerCase();
  const carrera = texto(f.carrera);
  const horasTxt = texto(f.horas_requeridas);

  if (!RE_CI.test(ci)) {
    return resultadoDe(f, "rechazado", "La C.I. debe tener entre 4 y 10 dígitos");
  }
  if (ctx.vistosCi.has(ci)) {
    return resultadoDe(f, "rechazado", "C.I. repetida en el archivo");
  }
  ctx.vistosCi.add(ci);

  // --- C.I. existente ---------------------------------------------
  const existente = ctx.porCi.get(ci);
  if (existente) {
    if (existente.rol !== "alumno") {
      return resultadoDe(
        f, "rechazado", "La C.I. pertenece a un usuario que no es alumno",
        existente.id,
      );
    }
    if (f.accion === "crear") {
      return resultadoDe(
        f, "rechazado",
        "Ya existe un alumno con esa C.I. (elegí omitir o actualizar)",
        existente.id,
      );
    }

    let resultado: ResultadoFila = "omitido";

    if (f.accion === "actualizar") {
      const err = validarDatos(nombre, carrera, horasTxt, ctx.carreras);
      if (err) return resultadoDe(f, "rechazado", err, existente.id);

      // Nombre, carrera y horas. El correo y la clave no se tocan.
      const { error } = await ctx.cliente.rpc("editar_usuario", {
        p_usuario_id: existente.id,
        p_nombre: nombre,
        p_ci: ci,
        p_carrera: carrera,
        p_horas_requeridas: Number(horasTxt),
        p_rol: "alumno",
      });
      if (error) {
        return resultadoDe(f, "rechazado", error.message, existente.id);
      }
      resultado = "actualizado";
    }

    if (f.reactivar === true && !existente.activo) {
      // Quita también el bloqueo en Auth (script 16).
      const { error } = await ctx.cliente.rpc("reactivar_usuario", {
        p_usuario_id: existente.id,
      });
      if (error) {
        return resultadoDe(
          f, resultado, `No se pudo reactivar: ${error.message}`, existente.id,
        );
      }
      return resultadoDe(f, resultado, null, existente.id, true);
    }

    return resultadoDe(f, resultado, null, existente.id);
  }

  // --- C.I. nueva -------------------------------------------------
  if (f.accion === "omitir") return resultadoDe(f, "omitido");
  if (f.accion === "actualizar") {
    return resultadoDe(f, "rechazado", "No existe un alumno con esa C.I.");
  }

  const err = validarDatos(nombre, carrera, horasTxt, ctx.carreras);
  if (err) return resultadoDe(f, "rechazado", err);

  if (!RE_CORREO.test(correo)) {
    return resultadoDe(
      f, "rechazado", `El correo debe ser válido y del dominio ${DOMINIO}`,
    );
  }
  if (ctx.vistosCorreo.has(correo)) {
    return resultadoDe(f, "rechazado", "Correo repetido en el archivo");
  }
  ctx.vistosCorreo.add(correo);
  if (ctx.porCorreo.has(correo)) {
    return resultadoDe(f, "rechazado", "El correo ya lo usa otra C.I.");
  }

  const { data, error } = await ctx.admin.auth.admin.createUser({
    email: correo,
    password: `${ci}${SUFIJO_CLAVE}`,
    email_confirm: true,
  });
  if (error || !data.user) {
    return resultadoDe(
      f, "rechazado",
      `No se pudo crear la cuenta: ${error?.message ?? "error en Auth"}`,
    );
  }

  const { error: errInsert } = await ctx.admin.from("usuarios").insert({
    id: data.user.id,
    nombre_completo: nombre,
    ci,
    correo_institucional: correo,
    carrera,
    rol: "alumno",
    horas_requeridas: Number(horasTxt),
    creado_por: ctx.autorId, // autor en la auditoría (script 17)
  });
  if (errInsert) {
    await ctx.admin.auth.admin.deleteUser(data.user.id); // rollback en Auth
    return resultadoDe(
      f, "rechazado", `No se pudo guardar el perfil: ${errInsert.message}`,
    );
  }

  return resultadoDe(f, "creado", null, data.user.id);
}

// Nombre, carrera y horas (mismas reglas que editar_usuario).
function validarDatos(
  nombre: string,
  carrera: string,
  horasTxt: string,
  carreras: Set<string>,
): string | null {
  if (nombre.length < 3) return "Falta el nombre completo";
  if (!carreras.has(carrera)) {
    return `La carrera "${carrera}" no está en la lista oficial`;
  }
  if (!/^\d{1,3}$/.test(horasTxt)) {
    return "Las horas requeridas deben ser un número entero";
  }
  const horas = Number(horasTxt);
  if (horas < 1 || horas > 500) {
    return "Las horas requeridas deben estar entre 1 y 500";
  }
  return null;
}

function resultadoDe(
  f: Fila,
  resultado: ResultadoFila,
  error: string | null = null,
  usuarioId: string | null = null,
  reactivado = false,
): Resultado {
  return { fila: f.fila, resultado, reactivado, error, usuario_id: usuarioId };
}

function texto(v: unknown): string {
  return v === null || v === undefined ? "" : String(v).trim();
}

function respuesta(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}