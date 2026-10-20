# Mapa del proyecto Flutter + Supabase

**Actualizado:** 2026-10-19 · **Rama:** `docs/mapa-proyecto` · **Commit:** `5810aa5` (merge: fase 6 - carga masiva de alumnos por CSV)

Documento generado por lectura del código fuente. Solo describe lo que aparece en los archivos;
lo que no se pudo verificar se indica explícitamente.

Excluidos: `assets/`, `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`, `build/`,
`.dart_tool/`, imágenes, íconos y archivos generados.

---

## Etapa 1 — Inventario de `lib/`

Columna **Estado** respecto del mapa anterior: **NUEVO** = el archivo no figuraba; *cambió* = mismo
archivo con otro tamaño (se indica el tamaño anterior); vacío = mismo tamaño.

| # | Archivo | Bytes | Estado |
|---|---------|------:|--------|
| 1 | lib/main.dart | 2666 | |
| 2 | lib/core/router.dart | 11412 | *cambió* (antes 9885) |
| 3 | lib/core/secure_storage.dart | 2427 | |
| 4 | lib/core/supabase_client.dart | 1742 | |
| 5 | lib/core/supabase_secrets.dart | 767 | |
| 6 | lib/core/supabase_secrets.example.dart | 574 | |
| 7 | lib/core/theme.dart | 5332 | |
| 8 | lib/features/admin/admin_usuarios_provider.dart | 3059 | |
| 9 | lib/features/admin/alta_usuario_screen.dart | 8878 | *cambió* (antes 7474) |
| 10 | lib/features/admin/alta_validador_screen.dart | 9249 | *cambió* (antes 9123) |
| 11 | lib/features/admin/lista_validadores_screen.dart | 14412 | *cambió* (antes 7279) |
| 12 | lib/features/admin/validadores_provider.dart | 3580 | *cambió* (antes 1244) |
| 13 | lib/features/asistencia/asistencia_provider.dart | 8192 | *cambió* (antes 7675) |
| 14 | lib/features/asistencia/gestion_asistencia_provider.dart | 5113 | |
| 15 | lib/features/asistencia/gestion_asistencia_screen.dart | 20270 | |
| 16 | lib/features/asistencia/marcar_asistencia_screen.dart | 15559 | *cambió* (antes 15529) |
| 17 | lib/features/asistencia/panel_asistencia_screen.dart | 27817 | *cambió* (antes 27360) |
| 18 | lib/features/auth/auth_provider.dart | 5234 | *cambió* (antes 5115) |
| 19 | lib/features/auth/login_screen.dart | 8241 | |
| 20 | lib/features/auth/recuperar_password_screen.dart | 12254 | |
| 21 | lib/features/eventos/admin_eventos_provider.dart | 2382 | |
| 22 | lib/features/eventos/admin_eventos_screen.dart | 13166 | |
| 23 | lib/features/eventos/crear_evento_screen.dart | 24456 | *cambió* (antes 20046) |
| 24 | lib/features/eventos/detalle_evento_screen.dart | 12126 | |
| 25 | lib/features/eventos/eventos_provider.dart | 11714 | *cambió* (antes 10869) |
| 26 | lib/features/eventos/historial_eventos_provider.dart | 2647 | |
| 27 | lib/features/eventos/historial_eventos_screen.dart | 8467 | *cambió* (antes 2647) |
| 28 | lib/features/eventos/lista_eventos_screen.dart | 11087 | |
| 29 | lib/features/home/home_admin_screen.dart | 15890 | *cambió* (antes 14634) |
| 30 | lib/features/home/home_estudiante_screen.dart | 23472 | *cambió* (antes 12502) |
| 31 | lib/features/home/home_provider.dart | 8867 | *cambió* (antes 5776) |
| 32 | lib/features/sistema/auditoria_provider.dart | 3420 | **NUEVO** |
| 33 | lib/features/sistema/auditoria_screen.dart | 17434 | **NUEVO** |
| 34 | lib/features/sistema/carga_alumnos_csv.dart | 7843 | **NUEVO** |
| 35 | lib/features/sistema/carga_alumnos_provider.dart | 11126 | **NUEVO** |
| 36 | lib/features/sistema/carga_alumnos_screen.dart | 33832 | **NUEVO** |
| 37 | lib/features/sistema/editar_usuario_screen.dart | 16619 | **NUEVO** |
| 38 | lib/features/sistema/lista_usuarios_screen.dart | 13659 | **NUEVO** |
| 39 | lib/features/sistema/usuarios_provider.dart | 6126 | **NUEVO** |
| 40 | lib/shared/carreras_provider.dart | 885 | **NUEVO** |

**Total: 40 archivos `.dart`** (411 996 bytes, ≈ 402 KB): 9 nuevos, 15 cambiados y 16 sin cambio de tamaño.
En `lib/` no hay archivos que no sean `.dart`. Ningún archivo del mapa anterior desapareció.

Observaciones de la etapa:
- `historial_eventos_screen.dart` y `historial_eventos_provider.dart` **ya no son idénticos**
  (`cmp` marca la primera diferencia en la línea 1); el "screen" pasó de 2647 a 8467 bytes. Su
  contenido se revisa en la Etapa 3.
- `lib/core/supabase_secrets.dart` sigue en `.gitignore` (línea 53). Contiene credenciales;
  este documento no reproduce sus valores.
- Los tamaños se midieron con `wc -c` sobre la copia de trabajo. Con `core.autocrlf = true` los
  archivos tienen finales CRLF, así que los bytes incluyen los `\r` y son mayores que en el repositorio.
  Los archivos que no cambiaron dan el mismo número que en el mapa anterior, por lo que este parece
  haberse medido igual.

---

## Etapa 2 — `lib/main.dart` y `lib/core/`

### lib/main.dart
- **Propósito:** punto de entrada; inicializa Supabase, el formato de fechas `es` y el snapshot de sesión, y arranca la app.
- **Clases públicas:** `UniNorteApp` (`MaterialApp.router` con `UniNorteTheme.lightTheme` y `appRouter`).
- **Privadas:** `_ErrorDeInicio` (pantalla que se muestra si falla el arranque).
- **Providers:** ninguno (envuelve la app en `ProviderScope`).
- **Lógica de arranque:** si `SessionSnapshot` dice "autenticado" pero `supabase.auth.currentSession == null`, limpia el storage y el snapshot.

### lib/core/router.dart
- **Propósito:** define las rutas (GoRouter), los roles y la guardia de acceso por prefijo de ruta.
- **Clases/tipos públicos:** `AppRoutes` (constantes de rutas y helpers `detalleEventoPath`, `marcarAsistenciaPath`, `gestionAsistenciaPath`, `editarEventoPath`, `editarUsuarioPath`), `enum RolUsuario { alumno, admin, validador, superadmin }`, `SessionSnapshot` (singleton en memoria: `autenticado`, `rol`; `cargarDesdeStorage`, `limpiar`), `AppRouterRefresh` (`ChangeNotifier` para re-evaluar `redirect`).
- **Funciones/variables públicas:** `rolDesdeString(String?)` (reconoce `superadmin`; cualquier otro valor, incluido `docente`, devuelve `null`), `appRouter` (`GoRouter`).
- **Privadas:** `_rutasPublicas`, `_esRuta`, `_rolesPermitidos`, `_homePorRol`, `_PlaceholderScreen`.
- **Providers:** ninguno.
- **Guardia por prefijo (`_rolesPermitidos`)**, en este orden: `/admin/sistema` → solo `superadmin`; `/admin` → `admin` y `superadmin` (el comentario dice "El superadmin usa las mismas pantallas del admin (fase 5)"); `/validador` → `validador`; `/home-estudiante`, `/eventos`, `/historial`, `/certificados`, `/carnet`, `/perfil` → `alumno`.
- **Home por rol (`_homePorRol`):** `admin` y `superadmin` → `/admin`; `validador` → `/validador`; `alumno` → `/home-estudiante`.
- **Pantallas que importa:** de `features/home`, `eventos`, `asistencia`, `auth`, `admin` y, desde esta versión, de `features/sistema` (`ListaUsuariosScreen`, `EditarUsuarioScreen`, `AuditoriaScreen`, `CargaAlumnosScreen`).
- Detalle de rutas en la Etapa 5(a).

### lib/core/secure_storage.dart
- **Propósito:** único punto de acceso a `flutter_secure_storage` para tokens y datos de sesión.
- **Clases públicas:** `SecureStorageService` (singleton) — `guardarTokens`, `obtenerAccessToken`, `obtenerRefreshToken`, `guardarDatosUsuario(ci, rol)`, `obtenerRol`, `obtenerCi`, `limpiarSesion` (`deleteAll`).
- **Claves:** `sb_access_token`, `sb_refresh_token`, `user_ci`, `user_rol`.
- **Providers:** ninguno.

### lib/core/supabase_client.dart
- **Propósito:** configura e inicializa el cliente Supabase (flujo PKCE) y expone un acceso global.
- **Clases públicas:** `SupabaseConfig` — `init()`, constante `dominioInstitucional = '@uninorte.edu.py'`. Credenciales desde `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) con valores por defecto de `SupabaseSecrets`.
- **Variables públicas:** `supabase` (`SupabaseClient`).
- **Providers:** ninguno.

### lib/core/supabase_secrets.dart
- **Propósito:** credenciales locales (URL y clave publicable) — archivo ignorado por Git.
- **Clases públicas:** `SupabaseSecrets` (`url`, `anonKey`). Valores no reproducidos aquí.

### lib/core/supabase_secrets.example.dart
- **Propósito:** plantilla de credenciales.
- **Clases públicas:** `SupabaseSecretsExample` (`url`, `anonKey` de ejemplo). Nadie la importa (es una plantilla).

### lib/core/theme.dart
- **Propósito:** paleta y `ThemeData` institucional.
- **Clases públicas:** `UniNorteColors` (constantes de color), `UniNorteTheme` (`lightTheme`).
- **Providers:** ninguno.

Observaciones de la etapa:
- `main.dart`, `secure_storage.dart`, `supabase_client.dart`, `theme.dart` y los dos archivos de credenciales se releyeron y **no cambiaron** respecto del mapa anterior. El único archivo de esta etapa que cambió es `router.dart`: se agregaron el rol `superadmin`, las 4 rutas de `/admin/sistema`, el helper `editarUsuarioPath` y la guardia correspondiente.
- `router.dart` usa `EditarEventoScreen`, que no está en un archivo propio: está definida en `features/eventos/crear_evento_screen.dart` (línea 14).
- `router.dart` sigue construyendo `HistorialEventosScreen` para `/historial`. **Esa clase ahora sí existe**, en `features/eventos/historial_eventos_screen.dart` (línea 12). Lo que el mapa anterior decía sobre una "clase inexistente" ya no vale; el detalle está en la Etapa 3.
- El comentario de `supabase_client.dart` (líneas 6‑15) sigue mezclando dos versiones de la documentación (`/// ///` duplicado en la línea 13).
- El comentario de `RolUsuario` (línea 76) dice "según el CHECK constraint de la tabla `usuarios`". Si el CHECK incluye `superadmin` se verifica en la Etapa 4.
- `router.dart` sigue apuntando a `_PlaceholderScreen` desde las rutas de alumno `/certificados`, `/carnet` y `/perfil`, y desde la pública `/validar-certificado`.

---

## Etapa 3 — `lib/features/`

### 3.1 `features/admin/`

#### admin_usuarios_provider.dart
- **Propósito:** servicio que da de alta usuarios (alumno/admin) y validadores invocando la Edge Function `crear-usuario`.
- **Clases públicas:** `ValidadorCreado` (`codigo`, `password`, `vigenteHasta`), `AltaException` (`mensaje`), `AdminUsuariosService` — `crearUsuario(rol, nombreCompleto, ci, correoLocal, carrera, password)`, `crearValidador(nombreCompleto, eventoId, vigenteHasta?)`.
- **Providers:** ninguno (a pesar del nombre del archivo).
- **Supabase:** Edge Function `crear-usuario` (`supabase.functions.invoke`). Cuerpo enviado: `rol`, `nombre_completo`, `ci`, `correo_local`, `carrera`, `password` / `evento_id`, `vigente_hasta`. Respuesta esperada: `exito`, `codigo`, `password`, `vigente_hasta`, `error`.
- **Tablas / RPC:** ninguna directa.
- **Rutas que abre:** ninguna.

#### alta_usuario_screen.dart
- **Propósito:** formulario de alta de alumno o administrador; la opción "Administrador" solo aparece si `SessionSnapshot.instance.rol == RolUsuario.superadmin` (comentario: "Solo el superadmin crea administradores (fase 5)").
- **Clases públicas:** `AltaUsuarioScreen` (`ConsumerStatefulWidget`).
- **Providers que consume/invalida:** `carrerasProvider` (de `shared/carreras_provider.dart`), con el que arma el desplegable de carrera (se envía `c.nombre`). Usa `AdminUsuariosService.crearUsuario`.
- **Validaciones locales:** nombre de 3+ caracteres, C.I. de 4–10 dígitos, usuario `^[a-zA-Z0-9._-]+$`, carrera obligatoria y contraseña de 8+ caracteres.
- **Tablas / RPC:** ninguna directa (vía Edge Function `crear-usuario`).
- **Rutas que abre:** ninguna.

#### alta_validador_screen.dart
- **Propósito:** alta de un validador temporal para un evento vigente; muestra código y clave una sola vez. El texto de la pantalla dice: "Cada evento admite hasta 5 validadores activos, que comparten la misma sesión de asistencia".
- **Clases públicas:** `AltaValidadorScreen` (`ConsumerStatefulWidget`). Privada: `_Dato`.
- **Providers que consume:** `adminEventosProvider` (de `eventos/admin_eventos_provider.dart`); filtra `e.vigente` y ordena por fecha.
- **Tablas / RPC:** ninguna directa (vía Edge Function `crear-usuario`). No envía `vigente_hasta`: usa el valor por defecto del servidor.
- **Rutas que abre:** ninguna.

#### lista_validadores_screen.dart
- **Propósito:** lista los validadores activos y permite **restablecerles la clave** o deshabilitarlos.
- **Clases públicas:** `ListaValidadoresScreen` (`ConsumerWidget`). Privadas: `_TarjetaValidador` (muestra el código si viene), `_DialogoClaveNueva` (muestra código y clave nueva una sola vez), `_DatoCopiable`.
- **Providers que consume/invalida:** `validadoresProvider`, `metricasAdminProvider` (de `home/home_provider.dart`).
- **Supabase:** indirecto vía `desactivarValidador` → RPC `desactivar_validador`, y vía `restablecerClaveValidador` → Edge Function `restablecer-clave-validador`.
- **Rutas que abre:** `AppRoutes.altaValidador` (`/admin/validadores/nuevo`, con `context.push`).

#### validadores_provider.dart
- **Propósito:** obtiene los validadores vigentes, los deshabilita y les restablece la clave.
- **Clases públicas:** `ValidadorActivo` (`id`, `codigo` nullable, `nombre`, `eventoNombre`, `eventoFecha`, `vigenteHasta`), `ClaveRestablecida` (`codigo`, `password`, `vigenteHasta`), `RestablecerClaveException` (`mensaje`).
- **Providers públicos:** `validadoresProvider` (`FutureProvider.autoDispose<List<ValidadorActivo>>`).
- **Funciones públicas:** `desactivarValidador(String id)`, `restablecerClaveValidador(String validadorId)`.
- **RPC:** `listar_validadores` (campos leídos: `id`, `codigo`, `nombre_completo`, `evento_nombre`, `evento_fecha`, `vigente_hasta`), `desactivar_validador` (`p_usuario_id`).
- **Edge Function:** `restablecer-clave-validador` (cuerpo `validador_id`; espera `exito == true`, `codigo`, `password`, `vigente_hasta`; error en `error`).
- **Rutas que abre:** ninguna.
- Notas: el comentario de `codigo` dice "null si el script 12 no está aplicado"; el del provider dice que la RPC "solo responde a admin y superadmin". El comentario de `restablecerClaveValidador` dice que el servidor verifica "que quien llama sea admin" (se contrasta con la función en la Etapa 4).

### 3.2 `features/asistencia/`

#### asistencia_provider.dart
- **Propósito:** modelos y servicio de asistencia (sesión del validador, QR, PIN, resumen y marcaje del alumno).
- **Clases públicas:** `EventoPanel` (`id`, `nombre`, `vigenteHasta`), `ResumenAsistencia` (`inscriptos`, `conEntrada`, `presentes`, porcentajes), `EstadoSesion` (`abierta`, `modo`, `modoHasta`), `PinGenerado` (`codigo`, `venceEn`, `segundosRestantes`), `MiMarcaje` (`entradaEn`, `salidaEn`, `completo`), `AsistenciaService` (estático).
- Según los comentarios, si otro validador ya tenía un PIN vigente, el servidor devuelve ese mismo (script 14b), y `segundosRestantes` viene del servidor "no depende del reloj del dispositivo".
- **Providers públicos:**
  - `miMarcajeProvider` (`FutureProvider.autoDispose.family<MiMarcaje, String>`) — tabla `inscripciones` (`entrada_en`, `salida_en`, filtro `evento_id`, `usuario_id`).
  - `eventoPanelProvider` (`FutureProvider.autoDispose.family<EventoPanel, String?>`) — con `null` lee `usuarios` (`evento_asignado_id`, `vigente_hasta`) del usuario actual; luego `eventos` (`nombre`).
- **RPC (`AsistenciaService`):**
  | Método | RPC | Parámetros | Campos leídos |
  |---|---|---|---|
  | `abrirSesion` | `abrir_sesion_asistencia` | `p_evento_id` | retorna `String` (id de sesión) |
  | `estadoSesion` | `estado_sesion_asistencia` | `p_sesion_id` | `esta_abierta`, `modo_activo`, `modo_vence_en` |
  | `obtenerTokenQr` | `obtener_token_qr` | `p_sesion_id` | `String` `sesion:modo:ventana:firma` |
  | `activarPin` | `activar_pin` | `p_sesion_id` | `pin_codigo`, `vence_en`, `segundos_restantes` (opcional: si no viene, usa 20) |
  | `cerrarModo` | `cerrar_modo_asistencia` | `p_sesion_id` | — |
  | `cerrarSesion` | `cerrar_sesion_asistencia` | `p_sesion_id` | — |
  | `resumen` | `resumen_asistencia` | `p_evento_id` | `inscriptos`, `con_entrada`, `presentes` |
  | `marcarQr` | `marcar_asistencia_qr` | `p_token` | — |
  | `marcarPin` | `marcar_asistencia_pin` | `p_evento_id`, `p_pin` | `'ok' \| 'incorrecto' \| 'bloqueado' \| 'pin_no_activo' \| 'registro_cerrado'` |
- **Edge Function:** `activar-modo` (`activarModo`; cuerpo `sesion_id`, `modo`, `password`; espera `exito == true`).
- **Rutas que abre:** ninguna.

#### gestion_asistencia_provider.dart
- **Propósito:** datos de la pantalla de corrección de asistencia del admin y servicio de correcciones.
- **Clases públicas:** `InscriptoAsistencia`, `GestionAsistenciaData` (contadores, `esCancelado`, `esHoy`, `puedeAutorizarSalidaAnticipada`), `CorreccionService`.
- **Providers públicos:** `gestionAsistenciaProvider` (`FutureProvider.autoDispose.family<GestionAsistenciaData, String>`).
- **Tablas:** `eventos` (`nombre`, `estado`, `fecha`, `salida_anticipada_en`); `inscripciones` (`id`, `entrada_en`, `salida_en`, `metodo_entrada`, `metodo_salida`, `migrado`, `evento_id`) con embed `usuarios!usuario_id(nombre_completo, ci)`.
- **RPC:** `corregir_asistencia` (`p_inscripcion_ids`, `p_campo`, `p_registrar`, `p_motivo`; retorna `int`), `autorizar_salida_anticipada` (`p_evento_id`).
- **Usa:** `EstadoEvento` de `eventos/admin_eventos_provider.dart`.
- **Rutas que abre:** ninguna.

#### gestion_asistencia_screen.dart
- **Propósito:** pantalla del admin para registrar/revocar entrada y salida (individual o en lote, con motivo) y autorizar salida anticipada.
- **Clases públicas:** `GestionAsistenciaScreen(eventoId)`. Privadas: `_Filtro`, `_AccionFila`, `_Aviso`, `_DialogoMotivo`.
- **Providers que consume/invalida:** `gestionAsistenciaProvider`, `metricasAdminProvider`.
- **RPC:** indirectas vía `CorreccionService` (`corregir_asistencia`, `autorizar_salida_anticipada`).
- **Rutas que abre:** ninguna.

#### marcar_asistencia_screen.dart
- **Propósito:** el alumno registra entrada o salida escaneando el QR (`mobile_scanner`) o con PIN de 4 dígitos.
- **Clases públicas:** `MarcarAsistenciaScreen(eventoId)`.
- Con el resultado `bloqueado` muestra: "Superaste los 5 intentos. Pedile al administrador del evento que registre tu asistencia."
- **Providers que consume/invalida:** `miMarcajeProvider`, `detalleEventoProvider` (de `eventos/eventos_provider.dart`), `progresoEstudianteProvider` (de `home/home_provider.dart`).
- **RPC:** indirectas `marcar_asistencia_qr`, `marcar_asistencia_pin`.
- **Rutas que abre:** ninguna (solo `context.pop()`).

#### panel_asistencia_screen.dart
- **Propósito:** panel del validador: abre sesión, habilita entrada/salida con contraseña, muestra QR rotativo (60 s), PIN (20 s) y quórum; sincroniza cada 10 s.
- **Clases públicas:** `PanelAsistenciaScreen`. Privada: `_DialogoClave`.
- **Providers que consume:** `eventoPanelProvider(null)`, `authProvider` (logout).
- **RPC:** indirectas `abrir_sesion_asistencia`, `estado_sesion_asistencia`, `resumen_asistencia`, `obtener_token_qr`, `activar_pin`, `cerrar_modo_asistencia`, `cerrar_sesion_asistencia`; Edge Function `activar-modo`.
- **Rutas que abre:** ninguna.
- **Vencimiento del PIN:** el panel toma `segundosRestantes` del servidor (acotado a 0–20) y calcula `DateTime.now() + segundosRestantes` (líneas 281‑290). El comentario explica que, si otro validador ya mostró el PIN, quedan menos de 20 s. `venceEn` no se usa en el panel.
- **Sincronización:** un `Timer` de 1 s; cada 10 s (`_segundos % 10 == 0`, línea 160) llama a `estadoSesion` y `resumen`.

### 3.3 `features/auth/`

#### auth_provider.dart
- **Propósito:** login (C.I. o código `VAL-####`), logout y estado de autenticación.
- **Clases públicas:** `enum AuthStatus { inicial, cargando, autenticado, error }`, `AuthState` (`status`, `mensajeError`, `rol`), `AuthNotifier` (`StateNotifier<AuthState>`: `login`, `logout`, `limpiarError`).
- **Providers públicos:** `authProvider` (`StateNotifierProvider<AuthNotifier, AuthState>`).
- **Tablas/vistas:** `vista_resolucion_ci` (`correo_institucional`, filtro `ci`) antes de autenticar; `usuarios` (`rol`, `activo`, `vigente_hasta`, filtro `id`) después.
- **Auth:** `signInWithPassword`, `signOut`. Persiste tokens y rol en `SecureStorageService`, recarga `SessionSnapshot` y llama `AppRouterRefresh.refrescar()`.
- **Rechazos:** si `vista_resolucion_ci` no devuelve fila, muestra "El código no existe o su vigencia ya venció." (validador) o "La cédula no está registrada o la cuenta está desactivada…" (resto). Tras autenticar, cierra la sesión si no hay perfil, si el rol no se reconoce, si `activo = false` o si `vigente_hasta` ya pasó. El rol `superadmin` se acepta porque `rolDesdeString` lo reconoce. Los errores de Auth que contienen `banned` se muestran como "Tu acceso temporal ya venció.".
- **RPC:** ninguna.
- **Rutas que abre:** ninguna directamente (la navegación la hace el `redirect` del router).

#### login_screen.dart
- **Propósito:** formulario de inicio de sesión.
- **Clases públicas:** `LoginScreen`. Privada: `_LogoInstitucional`.
- **Providers que consume:** `authProvider`.
- **Tablas / RPC:** ninguna directa.
- **Rutas que abre:** `AppRoutes.recuperarPassword` (`/recuperar-password`, `context.push`).

#### recuperar_password_screen.dart
- **Propósito:** recuperación de contraseña en 3 pasos (C.I. → OTP por correo → nueva contraseña).
- **Clases públicas:** `RecuperarPasswordScreen`. Privadas: `enum _PasoRecuperacion { ingresarCi, ingresarOtp, nuevaPassword, exito }`, `_BotonCargando`.
- **Providers:** ninguno (es `ConsumerStatefulWidget` pero no lee providers).
- **Tablas/vistas:** `vista_resolucion_ci` (`correo_institucional`, filtro `ci`).
- **Auth:** `signInWithOtp(shouldCreateUser: false)`, `verifyOTP(type: email)`, `updateUser(password)`, `signOut`.
- **RPC:** ninguna.
- **Rutas que abre:** ninguna (solo `context.pop()`).

### 3.4 `features/eventos/`

#### admin_eventos_provider.dart
- **Propósito:** listado de todos los eventos para el admin y cambio de estado (finalizar/cancelar).
- **Clases/tipos públicos:** `enum EstadoEvento { vigente, finalizado, cancelado }` (`desdeTexto`; cualquier valor desconocido → `vigente`), `EventoAdmin`.
- **Providers públicos:** `adminEventosProvider` (`FutureProvider.autoDispose<List<EventoAdmin>>`).
- **Funciones públicas:** `finalizarEvento(id)`, `cancelarEvento(id)`.
- **Tablas:** `eventos` (`id`, `nombre`, `fecha`, `hora_inicio`, `ubicacion`, `estado`, `cupos_maximos`) con embed `inscripciones(id)`; orden `fecha` desc.
- **RPC:** `finalizar_evento` (`p_evento_id`), `cancelar_evento` (`p_evento_id`).
- **Rutas que abre:** ninguna.

#### admin_eventos_screen.dart
- **Propósito:** pantalla del admin con todos los eventos, filtros por estado, búsqueda y acciones editar/finalizar/cancelar.
- **Clases públicas:** `AdminEventosScreen`. Privadas: `_Filtro`, `_Accion`, `_TarjetaEventoAdmin`, `_EtiquetaEstado`.
- **Providers que consume/invalida:** `adminEventosProvider`.
- **RPC:** indirectas `finalizar_evento`, `cancelar_evento`.
- **Rutas que abre:** `AppRoutes.crearEvento` (`/admin/eventos/crear`), `AppRoutes.editarEventoPath(id)` (`/admin/eventos/:id/editar`), `AppRoutes.gestionAsistenciaPath(id)` (`/admin/eventos/:id/asistencia`).

#### crear_evento_screen.dart
- **Propósito:** formulario de creación y edición de evento, con selección de **carreras habilitadas** (casilla "Todas las carreras" + una por carrera; exige al menos una).
- **Clases públicas:** `EditarEventoScreen(eventoId)` (carga el evento y sus carreras y delega en el formulario), `CrearEventoScreen({evento, carrerasIniciales})`. Privadas: `_Etiqueta`, `_TextoError`, `_CampoSelector`.
- **Providers que consume/invalida:** `eventoPorIdProvider`, `carrerasDeEventoProvider`, `carrerasProvider` (de `shared/carreras_provider.dart`), `crearEventoNotifierProvider`, `metricasAdminProvider`, `catalogoEventosProvider`, `adminEventosProvider`, `detalleEventoProvider`.
- **Tablas / RPC:** indirectas vía `CrearEventoNotifier` (RPC `crear_evento`, `editar_evento`, `definir_carreras_evento`) y `carrerasDeEventoProvider` (tabla `evento_carreras`). Los errores `PostgrestException` con código `P0001` se muestran tal como vienen de la RPC.
- **Rutas que abre:** ninguna (`router.pop()` al guardar).

#### detalle_evento_screen.dart
- **Propósito:** detalle de un evento para el alumno, con inscripción y acceso a marcar asistencia.
- **Clases públicas:** `DetalleEventoScreen(eventoId)`. Privadas: `_FilaInfo`, `_EstadoInscripcionBanner`.
- **Providers que consume/invalida:** `detalleEventoProvider`, `inscripcionNotifierProvider`, `catalogoEventosProvider`.
- **RPC:** indirecta `inscribirse_a_evento`.
- **Rutas que abre:** `AppRoutes.marcarAsistenciaPath(id)` (`/eventos/:id/marcar`).

#### eventos_provider.dart
- **Propósito:** modelo `Evento`, catálogo del alumno, detalle con estado de inscripción, inscripción, alta/edición de eventos y carreras habilitadas por evento.
- **Constantes públicas:** `categoriasEvento`, `modalidadesEvento`.
- **Clases públicas:** `Evento` (`fromMap`, `cuposIlimitados`, `cuposAgotados`), `enum EstadoInscripcion { noInscripto, inscriptoPendiente, asistenciaConfirmada }`, `FiltrosEventos`, `DetalleEventoData`, `InscripcionNotifier`, `CrearEventoNotifier` (`crear`, `editar`, ambos con `carreraIds`).
- **Providers públicos:** `filtrosEventosProvider` (`StateProvider.autoDispose`), `catalogoEventosProvider` (`FutureProvider.autoDispose`), `catalogoFiltradoProvider` (`Provider.autoDispose`), `detalleEventoProvider` (`FutureProvider.autoDispose.family`), `inscripcionNotifierProvider` (`StateNotifierProvider.autoDispose`), `eventoPorIdProvider` (`FutureProvider.autoDispose.family`), **`carrerasDeEventoProvider`** (`FutureProvider.autoDispose.family<Set<int>, String>`), `crearEventoNotifierProvider` (`StateNotifierProvider.autoDispose`).
- **Tablas:**
  - `eventos`: `select()` completo filtrando `activo = true` (catálogo) o por `id`. Columnas leídas en `fromMap`: `id`, `nombre`, `descripcion`, `categoria`, `expositor`, `fecha`, `hora_inicio`, `hora_fin`, `ubicacion`, `modalidad`, `horas_otorgadas`, `cupos_maximos`, `cupos_disponibles`, `tolerancia_entrada_min`, `creado_por`, `activo`. El comentario del catálogo dice: "RLS ya filtra por carrera: el alumno solo recibe los eventos habilitados para su carrera o en los que ya está inscripto".
  - `evento_carreras`: `carrera_id` filtrando `evento_id` (comentario: "solo admin, por RLS").
  - `inscripciones`: `asistencia_confirmada` (filtro `evento_id`, `usuario_id`).
  - **Ya no hay `insert` directo en `eventos`:** la creación pasó a la RPC `crear_evento`.
- **RPC:**
  - `inscribirse_a_evento` (`p_evento_id`); según el comentario, también valida que el evento esté habilitado para la carrera del alumno.
  - `crear_evento` (`p_nombre`, `p_descripcion`, `p_categoria`, `p_expositor`, `p_fecha`, `p_hora_inicio`, `p_hora_fin`, `p_ubicacion`, `p_modalidad`, `p_horas_otorgadas`, `p_cupos_maximos`, `p_tolerancia_min`, `p_carrera_ids`).
  - `editar_evento` (`p_evento_id`, `p_nombre`, `p_descripcion`, `p_categoria`, `p_expositor`, `p_fecha`, `p_hora_inicio`, `p_hora_fin`, `p_ubicacion`, `p_modalidad`, `p_horas_otorgadas`, `p_cupos_maximos`, `p_tolerancia_min`), seguida de
  - `definir_carreras_evento` (`p_evento_id`, `p_carrera_ids`). Son dos llamadas separadas, no una transacción.
- **Rutas que abre:** ninguna.

#### historial_eventos_provider.dart
- **Propósito:** historial de inscripciones del alumno con su situación (acreditado / en curso / no acreditado / cancelado).
- **Clases/tipos públicos:** `enum SituacionHistorial { acreditado, enCurso, noAcreditado, cancelado }`, `EventoHistorial` (`completo`, `situacion`).
- **Providers públicos:** `historialEventosProvider` (`FutureProvider.autoDispose<List<EventoHistorial>>`).
- **RPC:** `mis_eventos_historial` (sin parámetros; campos leídos: `evento_id`, `nombre`, `fecha`, `hora_inicio`, `hora_fin`, `ubicacion`, `horas_otorgadas`, `estado`, `entrada_en`, `salida_en`).
- **Usa:** `EstadoEvento` (import con `show`).
- **Rutas que abre:** ninguna.
- Lo importa `historial_eventos_screen.dart`.

#### historial_eventos_screen.dart
- **Propósito:** historial del alumno con el total de horas acreditadas, filtro por situación y una tarjeta por evento con entrada y salida.
- **Clases públicas:** `HistorialEventosScreen` (`ConsumerStatefulWidget`). Privadas: `enum _Filtro { todos, acreditados, enCurso, noAcreditados, cancelados }`, `_TarjetaHistorial`.
- **Providers que consume/invalida:** `historialEventosProvider`.
- **Tablas / RPC:** indirecta `mis_eventos_historial`.
- **Rutas que abre:** `AppRoutes.detalleEventoPath(id)` (`/eventos/:id`), solo para eventos `enCurso` (comentario: "Solo los eventos vigentes son visibles para el alumno").
- La pantalla se restauró en el commit `6bfc033` ("fix(alumno): restaurar pantalla de historial de eventos"). Ya no es una copia del provider.

#### lista_eventos_screen.dart
- **Propósito:** catálogo de eventos para el alumno con búsqueda y filtro por categoría.
- **Clases públicas:** `ListaEventosScreen`. Privadas: `_ChipCategoria`, `_TarjetaEvento`, `_BadgeInfo`.
- **Providers que consume:** `catalogoFiltradoProvider`, `filtrosEventosProvider`, `catalogoEventosProvider`.
- **Tablas / RPC:** ninguna directa.
- **Rutas que abre:** `AppRoutes.detalleEvento` (`/eventos/:id`, armada con `replaceFirst(':id', ...)` en lugar de `detalleEventoPath`).

### 3.5 `features/home/`

#### home_provider.dart
- **Propósito:** datos de los dos homes: métricas del admin, progreso del alumno y próximos eventos del alumno.
- **Clases públicas:** `ProgresoEstudiante` (`porcentaje`, `horasFaltantes`), `EventoResumen`, `MetricasAdmin`, `EventoProximo` (`evento`, `inscripto`, `enCurso`), `ProximosEventosAlumno` (`destacado`, `siguientes`).
- **Providers públicos:** `metricasAdminProvider` (`FutureProvider.autoDispose<MetricasAdmin>`), `progresoEstudianteProvider` (`FutureProvider.autoDispose<ProgresoEstudiante>`), **`proximosEventosAlumnoProvider`** (`FutureProvider.autoDispose<ProximosEventosAlumno>`).
- **Tablas:**
  - `usuarios`: `nombre_completo` (admin); `nombre_completo`, `carrera`, `horas_requeridas` (alumno); conteo de validadores con `id` filtrando `rol = 'validador'`, `activo = true`, `vigente_hasta > now`.
  - `eventos`: `id`, `nombre`, `fecha`, `hora_inicio`, `cupos_maximos`, `estado` + embed `inscripciones(id)` (admin); `select()` completo con `activo = true`, `fecha >= hoy`, orden `fecha`, `hora_inicio`, límite 20 (próximos del alumno; descarta los que ya pasaron `hora_fin` según la hora del dispositivo).
  - `inscripciones`: `asistencia_confirmada` + embed `eventos(id)`, filtro `usuario_id`; `evento_id` con `inFilter` sobre los próximos eventos.
- **RPC:** `mis_horas_acreditadas` (sin parámetros; retorna número).
- **Usa:** `Evento` de `eventos/eventos_provider.dart`.
- **Rutas que abre:** ninguna.

#### home_admin_screen.dart
- **Propósito:** panel del administrador con métricas, accesos de gestión y eventos vigentes. Si `SessionSnapshot.instance.rol == RolUsuario.superadmin` agrega la sección "Administración del sistema" (Usuarios, Carga masiva de alumnos, Auditoría).
- **Clases públicas:** `HomeAdminScreen`. Privadas: `_AccesoDestacado`, `_TarjetaMetrica`, `_AccesoRapido`, `_TarjetaEvento`, `_SinEventos`.
- **Providers que consume:** `metricasAdminProvider`, `authProvider` (logout).
- **Tablas / RPC:** ninguna directa.
- **Rutas que abre:** `/admin/eventos/crear`, `/admin/eventos` (×2), `/admin/usuarios/nuevo`, `/admin/validadores`, `/admin/eventos/:id/asistencia`; solo superadmin: `/admin/sistema/usuarios`, `/admin/sistema/carga-alumnos`, `/admin/sistema/auditoria`.

#### home_estudiante_screen.dart
- **Propósito:** home del alumno con progreso de horas, sección de próximos eventos (uno destacado y hasta 3 siguientes), accesos rápidos y barra de navegación.
- **Clases públicas:** `HomeEstudianteScreen`. Privadas: `_SeccionProximosEventos`, `_TarjetaEventoDestacado`, `_FilaEventoProximo`, `_Etiqueta`, `_LineaInfo`, `_TarjetaProgreso`, `_TarjetaMetrica`, `_AccesoRapido`, `_BarraNavegacionEstudiante`.
- **Providers que consume/invalida:** `progresoEstudianteProvider`, `proximosEventosAlumnoProvider`, `authProvider` (logout).
- **Tablas / RPC:** ninguna directa.
- **Rutas que abre:** `/carnet` (×2), `/eventos` (×3), `/eventos/:id` (con `detalleEventoPath`), `/historial`, `/certificados` (×2), `/perfil`.

### 3.6 `features/sistema/` (nuevo; solo superadmin, rutas bajo `/admin/sistema`)

#### usuarios_provider.dart
- **Propósito:** listado filtrado de usuarios (alumnos, admins y superadmin) y operaciones de edición, desactivación y reactivación del superadmin.
- **Clases/tipos públicos:** `UsuarioSistema` (`id`, `nombreCompleto`, `ci`, `correo`, `carrera`, `rol`, `activo`, `horasRequeridas`; `esEditable` = `alumno` o `admin`; `rolLegible`; `fromMap`), `enum FiltroRolUsuario { todos, alumno, admin }`, `enum FiltroEstadoUsuario { todos, activos, inactivos }`, `FiltrosUsuarios` (con `==`/`hashCode` para usarse como clave de `.family`), `GestionUsuarioException`, `GestionUsuariosService` (`obtener`, `editar`, `desactivar`, `reactivar`).
- **Constantes públicas:** `limiteUsuarios = 200`.
- **Providers públicos:** `usuariosSistemaProvider` (`FutureProvider.autoDispose.family<List<UsuarioSistema>, FiltrosUsuarios>`).
- **Tablas:** `usuarios` (`id`, `nombre_completo`, `ci`, `correo_institucional`, `carrera`, `rol`, `activo`, `horas_requeridas`), con `inFilter('rol', …)` (`todos` = `alumno`, `admin`, `superadmin`), `eq('activo')`, `or('nombre_completo.ilike…,ci.ilike…')` (la búsqueda se limpia de `, ( ) % * \ : "`), orden `nombre_completo`, límite 200. El comentario atribuye el permiso de lectura a la policy `usuarios_select_admin` (script 15).
- **RPC:** `editar_usuario` (`p_usuario_id`, `p_nombre`, `p_ci`, `p_carrera`, `p_horas_requeridas`, `p_rol`), `desactivar_usuario` (`p_usuario_id`), `reactivar_usuario` (`p_usuario_id`). El comentario las ubica en el script 16.
- **Rutas que abre:** ninguna.

#### lista_usuarios_screen.dart
- **Propósito:** lista de usuarios con búsqueda (con espera antes de consultar), filtros por rol y estado y aviso si se alcanza el límite de 200.
- **Clases públicas:** `ListaUsuariosScreen` (`ConsumerStatefulWidget`). Privadas: `_FilaFiltros`, `_Filtro`, `_TarjetaUsuario`, `_Etiqueta`, `_Mensaje`.
- **Providers que consume/invalida:** `usuariosSistemaProvider`.
- **Supabase:** solo `supabase.auth.currentUser?.id`, para no permitir abrir el propio usuario (`esPropio`). Solo se abren los usuarios con `esEditable`.
- **Rutas que abre:** `AppRoutes.editarUsuarioPath(id)` (`/admin/sistema/usuarios/:id`).

#### editar_usuario_screen.dart
- **Propósito:** edita nombre, C.I., carrera, horas requeridas y rol (`alumno`/`admin`) de un usuario, y lo desactiva o reactiva, con diálogos de confirmación.
- **Clases públicas:** `EditarUsuarioScreen(usuarioId)` (`ConsumerStatefulWidget`). Privada: `_Encabezado`.
- **Providers que consume/invalida:** `carrerasProvider` (de `shared/`).
- **Supabase:** indirecto vía `GestionUsuariosService` (tabla `usuarios`; RPC `editar_usuario`, `desactivar_usuario`, `reactivar_usuario`).
- **Rutas que abre:** ninguna (`context.pop()` al guardar).

#### auditoria_provider.dart
- **Propósito:** consulta paginada de la auditoría unificada.
- **Clases/tipos públicos:** `enum OrigenAuditoria { todos, usuarios, eventos, asistencias, validadores }` + extensión `OrigenAuditoriaX` (`valor`, `etiqueta`), `RegistroAuditoria` (`origen`, `accion`, `entidad`, `detalle`, `motivo`, `actorNombre`, `actorRol`, `realizadoEn`), `AuditoriaException`, `AuditoriaService` (`listar`, `tamanoPagina = 50`).
- **Providers:** ninguno.
- **RPC:** `listar_auditoria` (`p_origen`, `p_desde`, `p_hasta` como `yyyy-MM-dd`, `p_limite`, `p_offset`); campos leídos: `origen`, `accion`, `entidad`, `detalle`, `motivo`, `actor_nombre`, `actor_rol`, `realizado_en`. El comentario la ubica en el script 17 y lista las acciones `alta | modificacion | baja | correccion | cambio_horario | restablecer_clave`.
- **Rutas que abre:** ninguna.

#### auditoria_screen.dart
- **Propósito:** pantalla de auditoría con filtro por origen y rango de fechas, carga incremental de 50 en 50 y detalle legible de cada cambio.
- **Clases públicas:** `AuditoriaScreen` (`StatefulWidget`, sin Riverpod). Privadas: `_TarjetaRegistro`, `_LineaDetalle`, `_Mensaje`, el mapa `_campos` (nombres legibles de columnas) y helpers de formato.
- **Supabase:** indirecto vía `AuditoriaService.listar` (RPC `listar_auditoria`).
- **Rutas que abre:** ninguna.

#### carga_alumnos_csv.dart
- **Propósito:** lectura y generación de los CSV de la carga masiva (sin dependencias de Flutter ni Supabase).
- **Constantes públicas:** `separadorCsv = ';'`, `maxFilasArchivo = 300`, `columnasPlantilla` (`nombre_completo`, `ci`, `correo`, `carrera (nombre oficial exacto)`, `horas_requeridas`), `maxBytesArchivo = 1 MB`.
- **Clases públicas:** `FilaCsv` (`numero`, `linea`, `nombre`, `ci`, `correo`, `carrera`, `horas`), `ArchivoInvalidoException`.
- **Funciones públicas:** `leerFilasCsv` (rechaza vacío, > 1 MB, `.xlsx` por la firma `PK`, separador coma, encabezado distinto y > 300 filas), `decodificarCsv` (UTF-8 con o sin BOM; si falla, Latin‑1), `generarPlantillaCsv`, `generarCarrerasCsv`, `generarCsv` (UTF-8 con BOM, `;`, `\r\n`; con `proteger` antepone `'` a celdas que empiezan con `= + - @`).
- **Supabase / rutas:** ninguna.

#### carga_alumnos_provider.dart
- **Propósito:** clasificación de las filas del CSV y envío por tandas a la Edge Function.
- **Constantes públicas:** `filasPorTanda = 50`, `sufijoClaveInicial = 'abc'` (comentario: clave inicial = C.I. + "abc").
- **Clases/tipos públicos:** `UsuarioExistente`, `enum EstadoFila { nuevo, existente, error }`, `enum AccionExistente { omitir, actualizar }`, `FilaPrevia` (`accion`, `reactivar`, `puedeActualizar`, `aPayload()`), `ResultadoFila` (`creado | actualizado | omitido | rechazado`), `RespuestaTanda`, `CargaAlumnosException`, `CargaAlumnosService` (`verificar`, `enviarTanda`).
- **Funciones públicas:** `normalizarNombre`, `validarDatosAlumno` (nombre de 3+ caracteres, carrera de la lista oficial, horas de 1 a 500), `clasificarFilas` (C.I. de 4–10 dígitos, C.I./correo repetidos en el archivo, C.I. de otro rol, correo `@uninorte.edu.py` y que no lo use otra C.I.).
- **RPC:** `verificar_carga_alumnos` (`p_cis`, `p_correos`); campos leídos: `usuario_id`, `ci`, `nombre_completo`, `correo`, `carrera`, `horas_requeridas`, `rol`, `activo`.
- **Edge Function:** `alta-masiva-alumnos`. Cuerpo: `carga_id` (falta en la primera tanda; usa la sintaxis `?cargaId` de elemento nulo), `nombre_archivo`, `total_filas`, `ultima_tanda`, `filas` (cada una con `fila`, `ci`, `nombre_completo`, `correo`, `carrera`, `horas_requeridas`, `accion` = `crear | actualizar | omitir`, y `reactivar` o `rechazo_previo`). Respuesta esperada: `exito`, `carga_id`, `resultados[]` (`fila`, `resultado`, `reactivado`, `error`).
- **Rutas que abre:** ninguna.

#### carga_alumnos_screen.dart
- **Propósito:** asistente de carga masiva en 4 etapas (`inicio`, `previa`, `enviando`, `terminado`). Permite descargar la plantilla y la lista de carreras, elegir el CSV, revisar la vista previa con filtros (todas, nuevas, existentes, errores) y elegir por fila "omitir/actualizar" y "reactivar". Después confirma, envía por tandas con reintento y descarga un informe CSV.
- **Clases públicas:** `CargaAlumnosScreen` (`ConsumerStatefulWidget`). Privadas: `_Etapa`, `_FiltroPrevia`, `_TarjetaFila`, `_Paso`, `_Recuadro`, `_TarjetaResumen`, `_FilaFiltros`, `_Filtro`, `_Etiqueta`.
- **Paquete:** `file_picker` (`FilePicker.pickFiles` con `withData: true` y extensión `csv`; `FilePicker.saveFile` para la plantilla, las carreras y el informe). Rechaza nombres que no terminan en `.csv`.
- **Providers que consume:** `carrerasProvider`.
- **Supabase:** indirecto vía `CargaAlumnosService` (RPC `verificar_carga_alumnos`, Edge Function `alta-masiva-alumnos`).
- **Rutas que abre:** ninguna.

### 3.7 `lib/shared/` (nuevo)

#### carreras_provider.dart
- **Propósito:** lista oficial de carreras activas.
- **Clases públicas:** `Carrera` (`id`, `nombre`, `fromMap`).
- **Providers públicos:** `carrerasProvider` (`FutureProvider.autoDispose<List<Carrera>>`).
- **Tablas:** `carreras` (`id`, `nombre`, filtro `activa = true`, orden `nombre`).
- **Lo usan:** `admin/alta_usuario_screen.dart`, `eventos/crear_evento_screen.dart`, `sistema/editar_usuario_screen.dart`, `sistema/carga_alumnos_screen.dart`.
- **Rutas que abre:** ninguna.

Observación de las secciones 3.1–3.5: los archivos que cambiaron se leyeron completos o en las partes que cambiaron (según `git log`). Los que tienen el mismo tamaño y no cambiaron desde la versión anterior del mapa se verificaron con búsquedas de `rpc`, `from`, `functions.invoke`, providers y navegación, sin releerlos línea por línea.

---

## Etapa 4 — `supabase/sql` y `supabase/functions`

Archivos: 23 scripts SQL (4 059 líneas) y 4 Edge Functions (1 120 líneas). No existe ningún `04_*.sql`.
Los 12 scripts de 01 a 10c no cambiaron respecto de la versión anterior del mapa (suman las mismas 2 017 líneas). Los scripts nuevos son 11, 11b, 12, 13, 14, 14b, 15, 15b, 16, 17 y 18. Las Edge Functions nuevas son `restablecer-clave-validador` y `alta-masiva-alumnos`. `crear-usuario` cambió y `activar-modo` no.
`supabase/.temp/` (`cli-latest`, `linked-project.json`) es estado local del CLI y se ignoró por ser generado.

**Importante:** ningún script crea las tablas base `usuarios`, `eventos` ni `inscripciones`, ni la función
`inscribirse_a_evento` original. Todos los scripts asumen que ya existen (ver Etapa 6).

**Estado de ejecución:** los scripts de 11 a 18 dicen en el encabezado *"NO EJECUTAR sin autorización"* (11: *"sin completar y confirmar la sección 6"*). Desde el repo no se puede saber cuáles se ejecutaron en la base. Todos van envueltos en `BEGIN … COMMIT`, y varios terminan con un bloque `DO` de verificación que revierte todo si falla.

### 4.1 Scripts SQL

#### 01_refactor_roles.sql
- **Modifica `usuarios`:** pasa `rol = 'docente'` a `'admin'`; reemplaza `usuarios_rol_check` por `rol IN ('alumno','admin','validador')`; agrega `evento_asignado_id` (FK `eventos`), `vigente_hasta`, `activo`; agrega `usuarios_validador_chk` (un validador exige evento y vigencia).
- **Crea tablas:** `sesiones_asistencia` (`id`, `evento_id`, `validador_id`, `secreto`, `pin`, `pin_expira_en`, `abierta`, `abierta_en`, `cerrada_en`) + índice `idx_sesiones_evento`; `intentos_pin` (`sesion_id`, `usuario_id`, `intentos`). Ambas con RLS activo y sin acceso para `anon`/`authenticated`.
- **Modifica `inscripciones`:** agrega `metodo_validacion` (`qr|pin|manual`), `fecha_marcaje`, `sesion_id`.
- **Crea función:** `rol_actual()`.
- **Policies:** borra las de `docente`; crea `usuarios_select_admin`, `usuarios_insert_admin`, `usuarios_update_admin`, `eventos_select_admin`, `eventos_insert_admin` (exige `creado_por = auth.uid()`), `eventos_update_admin`, `inscripciones_select_admin`.
- **Vista:** `vista_resolucion_ci` (`ci`, `correo_institucional`, `rol`) filtrando `activo` y `vigente_hasta`.
- No se puede re-ejecutar: `CREATE TABLE` y `ADD CONSTRAINT usuarios_validador_chk` van sin `IF NOT EXISTS`.

#### 02_rpc_asistencia.sql
- **Crea índice:** `uq_sesion_abierta_por_evento` (único parcial `WHERE abierta`).
- **Crea funciones (primera versión; 10 las reemplaza):** `puede_gestionar_evento(UUID)`, `_firma_qr`, `_registrar_marcaje`, `abrir_sesion_asistencia(UUID)`, `obtener_token_qr(UUID)` (ventana de 5 s), `marcar_asistencia_qr(TEXT)` (token de 3 partes), `activar_pin(UUID, INT)`, `marcar_asistencia_pin(UUID, TEXT)`, `cerrar_sesion_asistencia(UUID)`, `desactivar_validador(UUID)`, `resumen_asistencia(UUID)` (`inscriptos`, `presentes`), `corregir_asistencia(UUID[], BOOLEAN)`.
- **Permisos:** revoca `EXECUTE` a `PUBLIC, anon` (incluye `inscribirse_a_evento(UUID)`, que este script no crea) y también a `authenticated` en las funciones internas; ejecuta `ALTER FUNCTION inscribirse_a_evento ... SET search_path`.
- Usa columnas de `inscripciones` que ningún script crea: `asistencia_confirmada`, `fecha_validacion`, `validado_por`, `hash_certificado`.

#### 03_expirar_validadores.sql
- **Crea función:** `expirar_validadores()`: desactiva los validadores vencidos, cierra sus sesiones y pone `auth.users.banned_until = 'infinity'`. Ningún cliente tiene `EXECUTE`.
- **Programa cron:** `expirar-validadores` cada 5 min (requiere la extensión `pg_cron`).

#### 05_grants.sql
- `USAGE` en `public` a `anon, authenticated`; `SELECT, INSERT, UPDATE` en `usuarios` y `eventos`; `SELECT` en `inscripciones`.
- `EXECUTE` a `authenticated` sobre las funciones de 02 con sus firmas originales (`activar_pin(UUID, INT)`, `corregir_asistencia(UUID[], BOOLEAN)`) y sobre `inscribirse_a_evento(UUID)`.
- `SELECT` en `vista_resolucion_ci` a `anon, authenticated`.

#### 06_grants_service_role.sql
- Para `service_role`: `USAGE` en `public`; `SELECT, INSERT, UPDATE, DELETE` en `usuarios`; `SELECT` en `eventos` e `inscripciones`.

#### 07_estado_eventos.sql
- **Modifica `eventos`:** agrega `estado` (`vigente|finalizado|cancelado`), lo migra a partir de `activo` y de la fecha; índice `idx_eventos_estado`.
- **Crea trigger:** `_sync_activo_evento()` / `trg_eventos_sync_activo` (`activo = (estado = 'vigente')`).
- **Crea funciones:** `finalizar_eventos_vencidos()` (cron), `_cerrar_evento(UUID, TEXT)`, `finalizar_evento(UUID)`, `cancelar_evento(UUID)`.
- **Programa cron:** `finalizar-eventos-vencidos` cada minuto.

#### 08_lista_validadores.sql
- **Crea función:** `listar_validadores()` (`id`, `nombre_completo`, `evento_id`, `evento_nombre`, `evento_fecha`, `vigente_hasta`).
- **Reemplaza:** `desactivar_validador(UUID)` (acepta `superadmin`; falla si el validador no existe).

#### 08b_endurecer_roles.sql
- **Reemplaza:** `_cerrar_evento`, `listar_validadores` y `desactivar_validador`, ahora con `COALESCE(rol_actual(), '')`. Además, `desactivar_validador` banea al usuario en `auth.users`.

#### 09_edicion_eventos.sql
- **Modifica `eventos`:** rellena `hora_fin` y la vuelve `NOT NULL`; agrega `eventos_horario_check`; `cupos_maximos` y `cupos_disponibles` pasan a aceptar `NULL`; agrega `tolerancia_entrada_min` (0–120, default 15).
- **Reemplaza:** `inscribirse_a_evento(UUID)` (con soporte de cupo ilimitado).
- **Crea función:** `editar_evento(...)` (13 parámetros), con `EXECUTE` a `authenticated`.

#### 10_asistencia_entrada_salida.sql
- Cierra todas las sesiones abiertas.
- **Modifica `eventos`:** agrega `tolerancia_salida_min`, `salida_anticipada_en`.
- **Modifica `inscripciones`:** agrega `entrada_en`, `salida_en`, `metodo_entrada`, `metodo_salida`, `migrado`; migra las asistencias confirmadas; agrega el constraint `inscripciones_salida_requiere_entrada`.
- **Triggers:** `_sync_asistencia_confirmada` (deriva `asistencia_confirmada`), `_bloquear_certificado_cancelado`, `_bloquear_cambio_horario`.
- **Modifica `sesiones_asistencia`:** agrega `modo`, `modo_desde`, `modo_hasta`; índice `ux_sesion_abierta_por_evento`.
- **Recrea `intentos_pin`** (`DROP TABLE` + `CREATE`, ahora con columna `modo`).
- **Crea tabla:** `correcciones_asistencia` + policy `correcciones_select_admin`.
- **Crea/reemplaza funciones:** `_hora_local`, `_firma_qr_modo`, `puede_validar_evento`, `puede_gestionar_evento`, `abrir_sesion_asistencia`, `cerrar_sesion_asistencia`, `cerrar_modo_asistencia`, `activar_modo_asistencia` (solo `service_role`), `obtener_token_qr` (ventana de 60 s, 4 partes), `activar_pin(UUID)` (elimina la de `(UUID, INTEGER)`; devuelve `pin_codigo`, `vence_en`), `_registrar_marcaje`, `marcar_asistencia_qr`, `marcar_asistencia_pin`, `resumen_asistencia` (la elimina y la recrea con `con_entrada`), `autorizar_salida_anticipada`, `corregir_asistencia(UUID[], TEXT, BOOLEAN, TEXT)` (elimina la de `(UUID[], BOOLEAN)`), `mis_horas_acreditadas()`.
- **Vista:** `vista_horas_acreditadas` (los clientes no la leen directo).
- **Permisos:** `EXECUTE` a `authenticated` sobre las firmas nuevas.

#### 10b_estado_sesion_asistencia.sql
- **Crea función:** `estado_sesion_asistencia(UUID)` → `esta_abierta`, `modo_activo`, `modo_vence_en`. Necesita `puede_validar_evento` y las columnas `modo`/`modo_hasta` de 10.
- El encabezado dice: *"NO ejecutar todavía: solo se prepara"*.

#### 10c_historial_eventos_alumno.sql
- **Crea función:** `mis_eventos_historial()` (solo `alumno`), con las columnas que lee `historial_eventos_provider.dart`.
- El encabezado dice: *"NO ejecutar todavía: solo se prepara"*.

#### 11_carreras_por_evento.sql (fase 4G, ajuste 0)
- **Crea tablas:** `carreras` (`id` SMALLINT identity, `nombre` único, `activa`) con 15 carreras oficiales; `evento_carreras` (`evento_id`, `carrera_id`, `creado_en`; PK compuesta) + índice `idx_evento_carreras_carrera`. Habilita todas las carreras para los eventos existentes.
- **RLS/permisos:** `carreras_select_autenticados` (cualquier autenticado lee `carreras`); `evento_carreras_select_admin` (admin y superadmin). `SELECT` a `authenticated` y `service_role`; la escritura de `evento_carreras` solo va por RPC.
- **Crea función y policy:** `evento_visible_para_alumno(UUID)` + policy **RESTRICTIVE** `eventos_alumno_por_carrera` sobre `eventos`: el alumno solo ve eventos de su carrera o en los que ya está inscripto.
- **Datos:** normaliza `usuarios.carrera` de un admin y un alumno de prueba (sección 6).
- **Trigger:** `_validar_carrera_alumno()` / `trg_usuarios_validar_carrera`: para `rol = 'alumno'`, `carrera` debe ser una carrera oficial activa.
- **Crea/reemplaza funciones:** `definir_carreras_evento(UUID, INT[])` (admin/superadmin, evento vigente, mínimo una carrera, no toca inscripciones), `inscribirse_a_evento(UUID)` (versión de 09 + valida la carrera), `crear_evento(…13 parámetros…, INT[])` (admin/superadmin; mismas validaciones que `editar_evento` + fecha y hora futuras; inserta con `estado = 'vigente'` y llama a `definir_carreras_evento`). `EXECUTE` a `authenticated`.
- **Verificación final:** falla si quedan alumnos con carrera fuera de la lista o eventos sin carreras.

#### 11b_quitar_insert_directo_eventos.sql
- **Borra** la policy `eventos_insert_admin` (01) y verifica que no quede ninguna policy `INSERT`/`ALL` sobre `eventos`.
- El encabezado dice: *"Ejecutar SOLO cuando todo el equipo tenga develop actualizado (una app vieja dejaría de poder crear eventos)"*.

#### 12_restablecer_clave_validador.sql (ajuste 3)
- **Crea tabla:** `auditoria_validadores` (`id`, `validador_id`, `evento_id`, `accion` = `'restablecer_clave'`, `realizado_por`, `realizado_en`) + índice; policy `auditoria_validadores_select_admin` (admin/superadmin); `service_role` con `SELECT, INSERT, DELETE`.
- **Reemplaza (DROP + CREATE):** `listar_validadores()`, que ahora devuelve también `codigo` (columna `ci`).

#### 13_cambio_horario_evento.sql (ajuste 2)
- **Crea tabla:** `cambios_horario_evento` (`evento_id`, `inicio_anterior`, `fin_anterior`, `inicio_nuevo`, `fin_nuevo`, `con_entradas`, `cambiado_por`, `cambiado_en`) + índice; policy `cambios_horario_select_admin`.
- **Reemplaza:** `_bloquear_cambio_horario()` (trigger de 10): con entradas registradas sigue bloqueando fecha y tolerancias, y solo deja cambiar las horas si la transacción tiene la marca `uninorte.cambio_horario_autorizado = 'on'`. También reemplaza `editar_evento(...)`, que mantiene la firma de 09, acepta admin/superadmin, registra el cambio de horas en `cambios_horario_evento` y activa esa marca.

#### 14_varios_validadores.sql (ajuste 1)
- **Trigger:** `_limitar_validadores_por_evento()` / `trg_usuarios_limitar_validadores`: máximo 5 validadores activos y vigentes por evento.
- **Modifica `sesiones_asistencia`:** agrega `modo_activado_por` (FK `usuarios`).
- **Reemplaza:** `activar_modo_asistencia` (guarda `modo_activado_por`), `cerrar_modo_asistencia`, `cerrar_sesion_asistencia` (limpian `modo_activado_por`), `_registrar_marcaje` (`validado_por` = quien activó el modo), `desactivar_validador` y `expirar_validadores` (03). Las dos últimas cierran la sesión compartida solo si no queda otro validador activo del evento.

#### 14b_pin_compartido.sql
- **Reemplaza (DROP + CREATE):** `activar_pin(UUID)`, que ahora devuelve `pin_codigo`, `vence_en` y **`segundos_restantes`**. Si la sesión ya tiene un PIN vigente (más de 2 s de vida), devuelve ese mismo; si no, genera uno nuevo con `LEAST(NOW() + 20 s, modo_hasta)`.

#### 15_rol_superadmin.sql (fase 5, paso 5.1)
- **Modifica `usuarios`:** `usuarios_rol_check` pasa a `('alumno','admin','validador','superadmin')`; índice único parcial `ux_usuarios_un_superadmin` (un solo superadmin).
- **Recrea policies** para admin y superadmin: `usuarios_select_admin`, `eventos_select_admin`, `eventos_update_admin`, `inscripciones_select_admin`.
- **Borra** `usuarios_insert_admin` y `usuarios_update_admin`; `REVOKE INSERT, UPDATE, DELETE ON usuarios FROM anon, authenticated`.
- El encabezado nombra policies que **no se tocan y no están en el repo:** `usuarios_select_propio`, `eventos_select_activos`, `inscripciones_select_propio`.
- **Verificación final:** que no queden policies de escritura en `usuarios` ni policies "solo admin" en `usuarios`, `eventos` e `inscripciones`, y que el CHECK incluya `superadmin`.

#### 15b_crear_superadmin.sql
- Inserta en `usuarios` el perfil del único superadmin para una cuenta que ya existe en `auth.users` (con `carrera = 'Administración del sistema'`). Valida el formato del correo y de la C.I., que la cuenta no tenga perfil, que la C.I. y el correo estén libres y que no exista otro superadmin.
- El archivo tiene **valores concretos ya completados** (correo, nombre y C.I.); este documento no los reproduce.

#### 16_gestion_usuarios.sql (fase 5, paso 5.3)
- **Crea funciones:** `_es_superadmin()` (helper; sin `EXECUTE` para clientes), `editar_usuario(UUID, TEXT, TEXT, TEXT, INT, TEXT)`, `desactivar_usuario(UUID)` (además pone `auth.users.banned_until = 'infinity'`) y `reactivar_usuario(UUID)` (quita el baneo). Las tres exigen superadmin activo, operan solo sobre `alumno`/`admin` y no permiten actuar sobre la propia cuenta. `editar_usuario` valida la C.I. (4–10 dígitos, única), la carrera oficial, las horas (1–500) y el rol `alumno|admin`. `EXECUTE` a `authenticated`.

#### 17_auditoria.sql (fase 5, paso 5.4)
- **Modifica `usuarios`:** agrega `creado_por` (FK a `usuarios`).
- **Crea tabla:** `auditoria_cambios` (`tabla`, `registro_id`, `operacion` = `alta|modificacion|baja`, `cambios` JSONB, `realizado_por`, `rol_actor`, `realizado_en`) + 3 índices; policy `auditoria_cambios_select_superadmin`.
- **Trigger genérico:** `_auditar_cambio()` sobre `usuarios`, `eventos` (ignora `cupos_disponibles`, `activo`) e `inscripciones` (ignora `asistencia_confirmada`, `metodo_validacion`, `fecha_marcaje`, `fecha_validacion`, `sesion_id`). En las altas hechas con `service_role`, el autor sale de `creado_por`.
- **Crea función:** `listar_auditoria(TEXT, DATE, DATE, INT, INT)` (solo superadmin; límite de 1 a 200). Une `auditoria_cambios`, `correcciones_asistencia` (10), `cambios_horario_evento` (13) y `auditoria_validadores` (12), y omite las modificaciones de inscripciones hechas por admin/superadmin para no duplicar las correcciones.
- El encabezado pide **redesplegar `crear-usuario` después** de ejecutarlo. Requiere 10, 12, 13 y 16.

#### 18_carga_masiva_alumnos.sql (fase 6, paso 6.1)
- **Crea tablas:** `cargas_masivas` (`id`, `realizado_por`, `nombre_archivo`, `total_filas` 1–300, `iniciada_en`, `finalizada_en`) y `cargas_masivas_detalle` (`carga_id`, `fila`, `ci`, `nombre_completo`, `correo`, `carrera`, `horas_requeridas` como TEXT, `accion`, `reactivar`, `resultado`, `reactivado`, `error`, `usuario_id`, `registrado_en`; `UNIQUE (carga_id, fila)`). Policies de lectura solo para superadmin; `service_role` con `SELECT, INSERT, UPDATE` (sin `DELETE`).
- **Vista:** `vista_cargas_masivas` (`security_invoker = true`) con totales por lote. Ningún archivo Dart ni Edge Function la lee.
- **Crea función:** `verificar_carga_alumnos(TEXT[], TEXT[])` (solo superadmin; máximo 300 valores por arreglo).
- **Verificación final:** exige `_es_superadmin`, `editar_usuario`, `reactivar_usuario` y `auditoria_cambios`. Además avisa (sin fallar) si `usuarios.ci` no tiene índice único.

#### Objetos redefinidos por scripts posteriores

| Objeto | Versiones (la última es la vigente) |
|---|---|
| `inscribirse_a_evento(UUID)` | fuera del repo → 09 → **11** |
| `editar_evento(...)` | 09 → **13** |
| `listar_validadores()` | 08 → 08b → **12** (agrega `codigo`) |
| `desactivar_validador(UUID)` | 02 → 08 → 08b → **14** |
| `expirar_validadores()` | 03 → **14** |
| `activar_modo_asistencia`, `cerrar_modo_asistencia`, `cerrar_sesion_asistencia`, `_registrar_marcaje` | 02/10 → **14** |
| `activar_pin` | 02 `(UUID, INT)` → 10 `(UUID)` → **14b** (agrega `segundos_restantes`) |
| `_bloquear_cambio_horario()` | 10 → **13** |
| `usuarios_rol_check` | 01 → **15** (agrega `superadmin`) |
| Policies `usuarios_select_admin`, `eventos_select_admin`, `eventos_update_admin`, `inscripciones_select_admin` | 01 → **15** |
| Policies `usuarios_insert_admin`, `usuarios_update_admin` | 01 → borradas en **15** |
| Policy `eventos_insert_admin` | 01 → borrada en **11b** |

### 4.2 Orden de ejecución (deducido de las dependencias en el código)

0. *(fuera del repo)* Esquema base: `usuarios`, `eventos`, `inscripciones`, `inscribirse_a_evento(UUID)` y las extensiones `pgcrypto` y `pg_cron`.
1. `01_refactor_roles.sql`
2. `02_rpc_asistencia.sql`: necesita `sesiones_asistencia`, `intentos_pin` y `rol_actual` (01).
3. `03_expirar_validadores.sql`: necesita 01.
4. `05_grants.sql`: **tiene que ir antes de 10**, porque nombra `activar_pin(UUID, INT)` y `corregir_asistencia(UUID[], BOOLEAN)`, que 10 elimina.
5. `06_grants_service_role.sql`: independiente.
6. `07_estado_eventos.sql`: necesita `eventos.activo` y `sesiones_asistencia`.
7. `08_lista_validadores.sql`
8. `08b_endurecer_roles.sql`: reemplaza funciones de 07 y 08.
9. `09_edicion_eventos.sql`: `editar_evento` usa `estado` (07).
10. `10_asistencia_entrada_salida.sql`: usa `estado` (07) y `tolerancia_entrada_min` (09).
11. `10b_estado_sesion_asistencia.sql`: necesita 10.
12. `10c_historial_eventos_alumno.sql`: necesita 10 (`entrada_en`, `salida_en`).
13. `11_carreras_por_evento.sql`: `crear_evento` usa `estado` (07) y `tolerancia_entrada_min` (09); necesita la columna `usuarios.carrera` (esquema base). Antes de ejecutarlo hay que completar la sección 6.
14. `11b_quitar_insert_directo_eventos.sql`: después de 11 y **solo cuando la app que usa `crear_evento` esté desplegada para todos**.
15. `12_restablecer_clave_validador.sql`: reemplaza `listar_validadores` (08b). Requisito de la Edge Function `restablecer-clave-validador` y del campo `codigo` en la app.
16. `13_cambio_horario_evento.sql`: necesita 10 (trigger `trg_eventos_bloquear_horario`, `tolerancia_salida_min`).
17. `14_varios_validadores.sql`: necesita 10 (`modo`, `modo_hasta`, `_hora_local`, `puede_validar_evento`, `tolerancia_salida_min`, `salida_anticipada_en`).
18. `14b_pin_compartido.sql`: necesita 10 (o 14) por la sesión con `modo`/`modo_hasta`.
19. `15_rol_superadmin.sql`: independiente de 11–14b. Va antes de 15b y 16.
20. `15b_crear_superadmin.sql`: necesita 15 y que la cuenta ya exista en Auth.
21. `16_gestion_usuarios.sql`: necesita 11 (`carreras`) y 15 (rol `superadmin`); usa `usuarios.horas_requeridas` (esquema base).
22. `17_auditoria.sql`: necesita 10, 12, 13 y 16 (lo dice el encabezado y lo verifica). Después hay que **redesplegar `crear-usuario`**.
23. `18_carga_masiva_alumnos.sql`: necesita 15, 16 y 17 (lo verifica). La Edge Function `alta-masiva-alumnos` necesita además 11 (`carreras`) y 17 (`usuarios.creado_por`).

Nota: la versión actual de `crear-usuario` inserta `creado_por` en `usuarios`, una columna que crea 17. Sin ese script, el alta fallaría con un error de columna inexistente. Se deduce del código; no se probó contra la base.

### 4.3 Edge Functions

#### functions/activar-modo/index.ts
- **Recibe:** `POST` con header `Authorization` (JWT del validador) y body `{ sesion_id, modo: 'entrada'|'salida', password }`. Responde a `OPTIONS` (CORS) y devuelve `405` para otros métodos.
- **Verifica:** (1) que el JWT sea válido (`auth.getUser()`) y el usuario tenga email; (2) que el body sea válido; (3) con `service_role`, en `usuarios` (`rol`, `activo`, `vigente_hasta`), que sea un `validador` activo y vigente; (4) la contraseña, con `signInWithPassword` en un cliente aislado.
- **Llama a:** la RPC `activar_modo_asistencia(p_sesion_id, p_validador_id, p_modo)` con `service_role`.
- **Responde:** `{ exito: true, modo_hasta }` o `{ error }` con 400/401/403.

#### functions/crear-usuario/index.ts
- **Recibe:** `POST` con `Authorization` y body `{ rol, nombre_completo, ci?, correo_local?, carrera?, password?, evento_id?, vigente_hasta? }`.
- **Verifica:** que el usuario esté autenticado y, con el JWT de quien llama, en `usuarios` (`rol`, `activo`), que tenga `rol` **`admin` o `superadmin`** y esté activo. **Solo el superadmin puede crear `rol = 'admin'`** (403 si no).
  - Alumno/admin: campos obligatorios, C.I. de 4–10 dígitos, usuario de correo válido, contraseña de 8+ caracteres; que no exista otro registro en `usuarios` con la misma `ci` o `correo_institucional`.
  - Validador: nombre y `evento_id`; evento existente y `activo` (lee `id`, `fecha`, `hora_fin`, `activo`); vigencia futura (por defecto `hora_fin + 1 h`, con zona fija `-03:00`); **que el evento tenga menos de 5 validadores activos y vigentes** (`MAX_VALIDADORES_POR_EVENTO`; la base lo vuelve a exigir con el trigger de 14). Genera un código `VAL-####` único (que guarda en la columna `ci`) y una clave de 10 caracteres.
- **Llama a:** ninguna RPC. Usa `auth.admin.createUser`, `insert` en `usuarios` (`id`, `nombre_completo`, `ci`, `correo_institucional`, `carrera`, `rol`, **`creado_por`** y, para validador, `evento_asignado_id`, `vigente_hasta`; validador con `carrera = 'Validador temporal'`) y `auth.admin.deleteUser` como rollback si el insert falla.
- **Responde:** `{ exito: true, correo }` (alumno/admin) o `{ exito: true, codigo, password, correo, vigente_hasta }` (validador); los errores vienen como `{ exito: false, error }` o `{ error }`.

#### functions/restablecer-clave-validador/index.ts (nueva)
- **Recibe:** `POST` con `Authorization` y body `{ validador_id }`.
- **Verifica:** usuario autenticado; con su JWT, en `usuarios` (`rol`, `activo`), que sea `admin` o `superadmin` y esté activo. Con `service_role` lee el validador (`id`, `ci`, `rol`, `activo`, `vigente_hasta`, `evento_asignado_id`) y exige que sea `validador`, activo y vigente.
- **Llama a:** ninguna RPC. Primero hace `insert` en `auditoria_validadores` (`validador_id`, `evento_id`, `accion = 'restablecer_clave'`, `realizado_por`); después `auth.admin.updateUserById(password)` con una clave nueva de 10 caracteres. Si falla Auth, borra el registro de auditoría.
- **Responde:** `{ exito: true, codigo, password, vigente_hasta }` o `{ exito: false, error }` / `{ error }` (400/401/403/405/500).

#### functions/alta-masiva-alumnos/index.ts (nueva)
- **Recibe:** `POST` con `Authorization` y body `{ carga_id?, nombre_archivo?, total_filas?, ultima_tanda?, filas: [{ fila, ci, nombre_completo, correo, carrera, horas_requeridas, accion: 'crear'|'actualizar'|'omitir', reactivar?, rechazo_previo? }] }`.
- **Verifica:**
  - Quien llama: usuario autenticado; con `service_role`, en `usuarios`, que sea `superadmin` activo.
  - Tanda: de 1 a 50 filas; números de fila enteros entre 1 y 300, sin repetir y no mayores que `total_filas`; acción válida.
  - Lote: la primera tanda crea el registro en `cargas_masivas` (nombre obligatorio, total de 1 a 300). Las siguientes exigen un `carga_id` UUID del mismo autor y sin finalizar.
  - Reintentos: las filas que ya están en `cargas_masivas_detalle` no se reprocesan; se devuelve el resultado guardado.
  - Por fila: C.I. de 4–10 dígitos y no repetida en la tanda. Si la C.I. existe: debe ser de un `alumno`, y `crear` se rechaza. Si es nueva: `actualizar` se rechaza; nombre de 3+ caracteres, carrera oficial activa, horas de 1–500, correo `@uninorte.edu.py` no repetido ni usado por otra C.I. Una fila con `rechazo_previo` se registra como rechazada sin procesarla.
- **Llama a:**
  - Con el **JWT del superadmin**: RPC `editar_usuario` (para `actualizar`, con `p_rol = 'alumno'`) y `reactivar_usuario` (si `reactivar` y la cuenta está inactiva). Así la auditoría registra al superadmin como autor.
  - Con **`service_role`**: tablas `usuarios` (lectura por `ci` y `correo_institucional`; `insert` con `horas_requeridas` y `creado_por`), `carreras` (`nombre`, `activa`), `cargas_masivas` (insert y cierre con `finalizada_en` en la última tanda) y `cargas_masivas_detalle` (lectura e insert). También `auth.admin.createUser` con clave C.I. + `"abc"` y `deleteUser` como rollback.
- **Responde:** `{ exito: true, carga_id, resultados: [{ fila, resultado, reactivado, error, usuario_id }] }` o `{ exito: false, error }`.

Observación de la Etapa 4: se leyeron completos los 11 scripts nuevos (11–18), `crear-usuario`, `restablecer-clave-validador`, `alta-masiva-alumnos` y `activar-modo` (este último coincide con lo que ya decía el mapa). Los 12 scripts de 01 a 10c no se releyeron porque no cambiaron (mismo total de líneas y sin commits desde `20e4de5`). No se leyó `supabase/.temp/` (lo genera el CLI).

---

## Etapa 5 — Tablas de síntesis

### (a) Rutas de `router.dart` y rol permitido

Reglas del `redirect`: sin sesión, solo rutas públicas; si el rol es desconocido, solo rutas públicas; si hay sesión y se pide `/login`, redirige al home del rol; si el rol no coincide, redirige al home del rol (`/admin` para admin y superadmin, `/validador` o `/home-estudiante`).
La guardia de rol compara por prefijo (`ruta == base` o `ruta.startsWith('$base/')`) y evalúa primero `/admin/sistema` (solo superadmin) y después `/admin` (admin y superadmin).

| Ruta | Constante `AppRoutes` | Pantalla | Rol permitido |
|---|---|---|---|
| `/login` | `login` | `LoginScreen` | Pública (con sesión, redirige al home) |
| `/recuperar-password` | `recuperarPassword` | `RecuperarPasswordScreen` | Pública |
| `/validar-certificado` | `validadorHash` | `_PlaceholderScreen` | Pública |
| `/home-estudiante` | `homeEstudiante` | `HomeEstudianteScreen` | alumno |
| `/eventos` | `listaEventos` | `ListaEventosScreen` | alumno |
| `/historial` | `historial` | `HistorialEventosScreen` | alumno |
| `/eventos/:id` | `detalleEvento` | `DetalleEventoScreen` | alumno (prefijo `/eventos`) |
| `/eventos/:id/marcar` | `marcarAsistencia` | `MarcarAsistenciaScreen` | alumno (prefijo `/eventos`) |
| `/certificados` | `certificados` | `_PlaceholderScreen` | alumno |
| `/carnet` | `carnetQr` | `_PlaceholderScreen` | alumno |
| `/perfil` | `perfil` | `_PlaceholderScreen` | alumno |
| `/admin` | `homeAdmin` | `HomeAdminScreen` | admin, superadmin |
| `/admin/eventos` | `adminEventos` | `AdminEventosScreen` | admin, superadmin |
| `/admin/eventos/crear` | `crearEvento` | `CrearEventoScreen` | admin, superadmin |
| `/admin/eventos/:id/editar` | `editarEvento` | `EditarEventoScreen` | admin, superadmin |
| `/admin/eventos/:id/asistencia` | `gestionAsistencia` | `GestionAsistenciaScreen` | admin, superadmin |
| `/admin/usuarios/nuevo` | `altaUsuario` | `AltaUsuarioScreen` | admin, superadmin (solo el superadmin ve la opción "Administrador") |
| `/admin/validadores/nuevo` | `altaValidador` | `AltaValidadorScreen` | admin, superadmin |
| `/admin/validadores` | `validadores` | `ListaValidadoresScreen` | admin, superadmin |
| `/admin/sistema/usuarios` | `usuariosSistema` | `ListaUsuariosScreen` | superadmin |
| `/admin/sistema/usuarios/:id` | `editarUsuario` | `EditarUsuarioScreen` | superadmin |
| `/admin/sistema/auditoria` | `auditoriaSistema` | `AuditoriaScreen` | superadmin |
| `/admin/sistema/carga-alumnos` | `cargaAlumnos` | `CargaAlumnosScreen` | superadmin |
| `/validador` | `homeValidador` | `PanelAsistenciaScreen` | validador |

Total: 24 rutas (3 públicas, 8 de alumno, 8 de admin/superadmin, 4 solo de superadmin y 1 de validador).

### (b) RPC de Supabase y archivos Dart que las llaman

"Llamada directa" es el archivo con `.rpc(...)`; "Usada desde" son las pantallas que la disparan a través de ese servicio o provider. En "Definida en" la última versión es la vigente.

| RPC | Llamada directa (Dart / Edge Function) | Usada desde | Definida en |
|---|---|---|---|
| `abrir_sesion_asistencia` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 02 → 10 |
| `estado_sesion_asistencia` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 10b |
| `obtener_token_qr` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 02 → 10 |
| `activar_pin` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 02 `(UUID, INT)` → 10 `(UUID)` → 14b |
| `cerrar_modo_asistencia` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 10 → 14 |
| `cerrar_sesion_asistencia` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 02 → 10 → 14 |
| `resumen_asistencia` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | 02 → 10 (recreada) |
| `marcar_asistencia_qr` | asistencia/asistencia_provider.dart | asistencia/marcar_asistencia_screen.dart | 02 → 10 |
| `marcar_asistencia_pin` | asistencia/asistencia_provider.dart | asistencia/marcar_asistencia_screen.dart | 02 → 10 |
| `corregir_asistencia` | asistencia/gestion_asistencia_provider.dart | asistencia/gestion_asistencia_screen.dart | 02 `(UUID[], BOOLEAN)` → 10 `(UUID[], TEXT, BOOLEAN, TEXT)` |
| `autorizar_salida_anticipada` | asistencia/gestion_asistencia_provider.dart | asistencia/gestion_asistencia_screen.dart | 10 |
| `listar_validadores` | admin/validadores_provider.dart | admin/lista_validadores_screen.dart | 08 → 08b → 12 |
| `desactivar_validador` | admin/validadores_provider.dart | admin/lista_validadores_screen.dart | 02 → 08 → 08b → 14 |
| `finalizar_evento` | eventos/admin_eventos_provider.dart | eventos/admin_eventos_screen.dart | 07 |
| `cancelar_evento` | eventos/admin_eventos_provider.dart | eventos/admin_eventos_screen.dart | 07 |
| `inscribirse_a_evento` | eventos/eventos_provider.dart | eventos/detalle_evento_screen.dart | fuera del repo → 09 → 11 (02 y 05 solo le cambian permisos) |
| `crear_evento` | eventos/eventos_provider.dart | eventos/crear_evento_screen.dart | 11 |
| `editar_evento` | eventos/eventos_provider.dart | eventos/crear_evento_screen.dart | 09 → 13 |
| `definir_carreras_evento` | eventos/eventos_provider.dart | eventos/crear_evento_screen.dart (al editar) | 11 (también la llama `crear_evento` dentro de la base) |
| `mis_eventos_historial` | eventos/historial_eventos_provider.dart | eventos/historial_eventos_screen.dart | 10c |
| `mis_horas_acreditadas` | home/home_provider.dart | home/home_estudiante_screen.dart, asistencia/marcar_asistencia_screen.dart (invalida el provider) | 10 |
| `editar_usuario` | sistema/usuarios_provider.dart; Edge Function `alta-masiva-alumnos` (JWT del superadmin) | sistema/editar_usuario_screen.dart; sistema/carga_alumnos_screen.dart (vía la Edge Function) | 16 |
| `desactivar_usuario` | sistema/usuarios_provider.dart | sistema/editar_usuario_screen.dart | 16 |
| `reactivar_usuario` | sistema/usuarios_provider.dart; Edge Function `alta-masiva-alumnos` (JWT del superadmin) | sistema/editar_usuario_screen.dart; sistema/carga_alumnos_screen.dart (vía la Edge Function) | 16 |
| `listar_auditoria` | sistema/auditoria_provider.dart | sistema/auditoria_screen.dart | 17 |
| `verificar_carga_alumnos` | sistema/carga_alumnos_provider.dart | sistema/carga_alumnos_screen.dart | 18 |
| `activar_modo_asistencia` | Edge Function `activar-modo` (service_role) | asistencia/panel_asistencia_screen.dart (vía `AsistenciaService.activarModo`) | 10 → 14 |

Total: 26 RPC distintas llamadas desde Dart y 3 llamadas desde Edge Functions (`activar_modo_asistencia`, `editar_usuario` y `reactivar_usuario`); de estas, solo `activar_modo_asistencia` no se llama desde Dart.

**Edge Functions** (no son RPC, se listan como complemento):

| Función | Llamada directa | Usada desde | RPC que ejecuta |
|---|---|---|---|
| `crear-usuario` | admin/admin_usuarios_provider.dart | admin/alta_usuario_screen.dart, admin/alta_validador_screen.dart | ninguna |
| `activar-modo` | asistencia/asistencia_provider.dart | asistencia/panel_asistencia_screen.dart | `activar_modo_asistencia` |
| `restablecer-clave-validador` | admin/validadores_provider.dart | admin/lista_validadores_screen.dart | ninguna |
| `alta-masiva-alumnos` | sistema/carga_alumnos_provider.dart | sistema/carga_alumnos_screen.dart | `editar_usuario`, `reactivar_usuario` |

Funciones SQL que **no** se llaman desde Dart ni desde Edge Functions: `expirar_validadores` y `finalizar_eventos_vencidos` (cron), los helpers `rol_actual`, `puede_gestionar_evento`, `puede_validar_evento`, `evento_visible_para_alumno` (policy) y `_es_superadmin`, y las internas con prefijo `_` (triggers y auxiliares).

Observación de la Etapa 5: las tablas salen de lo leído en las Etapas 2–4 y de una búsqueda de `.rpc(` (incluidas las llamadas que ocupan varias líneas) en `lib/` y `supabase/functions/`.

---

## Etapa 6 — Inconsistencias

Todo sale de leer el código. No se ejecutó `flutter analyze` ni nada contra la base, así que los efectos en compilación o en ejecución se deducen del código y no fueron comprobados.

### (1) RPC llamadas desde Dart o Edge Functions que no existen en `supabase/sql`

**Ninguna.** Las 26 RPC distintas que se llaman desde Dart y las 3 que se llaman desde Edge Functions (`activar_modo_asistencia`, `editar_usuario`, `reactivar_usuario`) están definidas en algún script. Los nombres de los parámetros coinciden con la firma vigente, y también los de las RPC nuevas (`crear_evento`, `definir_carreras_evento`, `editar_usuario`, `desactivar_usuario`, `reactivar_usuario`, `listar_auditoria`, `verificar_carga_alumnos`).

Matices:
- **Scripts que quizá no se ejecutaron.** `estado_sesion_asistencia` (10b) y `mis_eventos_historial` (10c) están en scripts que dicen *"NO ejecutar todavía: solo se prepara"*, y todos los scripts de 11 a 18 dicen *"NO EJECUTAR sin autorización"*. Aun así, la app ya llama a `crear_evento`, `definir_carreras_evento`, `editar_usuario`, `desactivar_usuario`, `reactivar_usuario`, `listar_auditoria` y `verificar_carga_alumnos`, y lee `listar_validadores.codigo` y `activar_pin.segundos_restantes`. Desde el repo no se puede saber qué se ejecutó en la base. La app tolera la falta de `codigo` y de `segundos_restantes` (comentarios en `validadores_provider.dart` y `asistencia_provider.dart`), pero no la de las RPC nuevas.
- **Primera versión de `inscribirse_a_evento` fuera del repo.** 02 (`REVOKE`, `ALTER FUNCTION`) y 05 (`GRANT`) la usan antes de que 09 la defina. El comentario de 02 dice "la RPC de inscripción que hicimos antes".

### (2) Archivos `.dart` que nadie importa

| Archivo | Situación |
|---|---|
| `lib/main.dart` | Entry point de la app: es normal que nadie lo importe. |
| `lib/core/supabase_secrets.example.dart` | Plantilla para copiar a mano: es normal. |

**No hay archivos huérfanos.** Lo verifiqué buscando, para cada uno de los 40 `.dart`, un `import` que termine exactamente en su nombre de archivo, en `lib/` y `test/`.

Se resolvió lo que marcaba el mapa anterior:
- `historial_eventos_provider.dart` ya no es huérfano: lo importa `historial_eventos_screen.dart`.
- `historial_eventos_screen.dart` ya no es una copia del provider: define `HistorialEventosScreen`, que es la clase que usa `router.dart`. Se restauró en el commit `6bfc033`.
- `historialEventosProvider` ahora lo consume `HistorialEventosScreen`.

### (3) Tablas, vistas y columnas que se usan pero no aparecen en los scripts

**Tablas y vistas:** todas las que se leen o escriben desde Dart y desde las Edge Functions están creadas en algún script, salvo las tres tablas base (`usuarios`, `eventos`, `inscripciones`). Las nuevas son `carreras` y `evento_carreras` (11), `auditoria_validadores` (12) y `cargas_masivas` / `cargas_masivas_detalle` (18). `vista_resolucion_ci` está en 01. A la inversa, `vista_cargas_masivas` (18), `cambios_horario_evento` (13) y `auditoria_cambios` (17) existen en los scripts pero ningún cliente las lee directamente: las dos últimas se leen a través de `listar_auditoria`.

**Columnas que ningún script crea** (se suponen del esquema base, que no está en el repo):

| Tabla | Columnas |
|---|---|
| `usuarios` | `id`, `nombre_completo`, `ci`, `correo_institucional`, `rol` (01 y 15 solo cambian su CHECK), **`carrera`**, **`horas_requeridas`** |
| `eventos` | `id`, `nombre`, `descripcion`, `categoria`, `expositor`, `fecha`, `hora_inicio`, `hora_fin` (09 solo le pone `NOT NULL`), `ubicacion`, `modalidad`, `horas_otorgadas`, `cupos_maximos`, `cupos_disponibles` (09 solo les saca el `NOT NULL`), `creado_por`, **`activo`** (07 lo usa para migrar `estado`; el `activo` que crea 01 es de `usuarios`) |
| `inscripciones` | `id`, `usuario_id`, `evento_id`, `asistencia_confirmada`, `fecha_validacion`, `validado_por`, `hash_certificado` |

Corrección respecto del mapa anterior: `usuarios.carrera` y `usuarios.horas_requeridas` **ahora sí se nombran** en los scripts (11 usa `u.carrera`; 16 actualiza ambas; 18 las devuelve), pero siguen sin crearse con `ADD COLUMN`. Las usan `home_provider.dart`, `sistema/usuarios_provider.dart`, `crear-usuario` y `alta-masiva-alumnos`.

Columnas que sí se crean en los scripts y usa el código: `usuarios.evento_asignado_id/vigente_hasta/activo` (01), **`usuarios.creado_por`** (17), `eventos.estado` (07), `eventos.tolerancia_entrada_min` (09), `eventos.salida_anticipada_en` (10), `inscripciones.entrada_en/salida_en/metodo_entrada/metodo_salida/migrado` (10), **`sesiones_asistencia.modo_activado_por`** (14), **`carreras.*`** y **`evento_carreras.*`** (11).

### (4) Rutas que todavía usan `_PlaceholderScreen`

| Ruta | Título del placeholder | Quién navega a ella |
|---|---|---|
| `/validar-certificado` (pública) | "Validador de certificados (módulo Certificados)" | nadie en `lib/` |
| `/certificados` (alumno) | "Certificados (módulo Certificados)" | `home_estudiante_screen.dart` (acceso rápido y barra inferior) |
| `/carnet` (alumno) | "Carnet QR (módulo Perfil)" | `home_estudiante_screen.dart` (botón del AppBar y acceso rápido) |
| `/perfil` (alumno) | "Perfil (módulo Perfil)" | `home_estudiante_screen.dart` (barra inferior) |

Las rutas nuevas de `/admin/sistema` usan todas pantallas reales.

### (5) Otras inconsistencias encontradas

1. **`crear-usuario` depende del script 17.** Inserta `creado_por` en `usuarios`, una columna que crea 17. Sin ese script, cualquier alta (alumno, admin o validador) fallaría en el `insert` y la función haría rollback en Auth. El encabezado de 17 pide redesplegar la función *después* de ejecutarlo. Se deduce del código; no se probó.
2. **`05_grants.sql` no se puede volver a ejecutar después de 10.** Nombra `activar_pin(UUID, INT)` y `corregir_asistencia(UUID[], BOOLEAN)`, firmas que 10 elimina con `DROP FUNCTION`. 14b vuelve a cambiar `activar_pin` (DROP + CREATE).
3. **Dos índices únicos iguales** sobre `sesiones_asistencia (evento_id) WHERE abierta`: `uq_sesion_abierta_por_evento` (02) y `ux_sesion_abierta_por_evento` (10).
4. **Políticas RLS que el código da por hechas pero no están en el repo.** El encabezado de 15 dice que existen en la base y las nombra: `usuarios_select_propio`, `eventos_select_activos` e `inscripciones_select_propio`. Ningún script las crea. De ellas dependen:
   - las lecturas de la fila propia de `usuarios` (`auth_provider.dart`, `home_provider.dart`, `eventoPanelProvider`);
   - el catálogo y los próximos eventos del alumno (`eventos_provider.dart`, `home_provider.dart`; `eventos_alumno_por_carrera` de 11 se combina con ellas porque es RESTRICTIVE);
   - las `inscripciones` propias (`miMarcajeProvider`, `detalleEventoProvider`, `progresoEstudianteProvider`, `proximosEventosAlumnoProvider`).
5. **Vencimiento del PIN en el panel** (corrige el punto 5 del mapa anterior). Ahora el panel usa `segundos_restantes` del servidor (14b), así que el contador refleja el `LEAST(NOW() + 20 s, modo_hasta)` real y el PIN compartido. Si 14b no está ejecutado, el campo no viene y el panel usa 20 s fijos (`asistencia_provider.dart:213`), con el mismo desfase de antes cerca del fin del modo.
6. **`vista_resolucion_ci`** se crea con `security_invoker = false` y `GRANT SELECT` a `anon` (01, 05): cualquier cliente sin sesión puede leer `ci`, `correo_institucional` y `rol` de todos los usuarios activos. Es lo que permite el login por C.I., pero también expone la lista completa.
7. **La edición de un evento hace dos RPC separadas.** `CrearEventoNotifier.editar` llama a `editar_evento` y después a `definir_carreras_evento`, que no forman una transacción. Si la segunda falla (por ejemplo, el evento dejó de estar vigente), el evento queda editado con las carreras anteriores y la pantalla muestra error. La creación sí es atómica (`crear_evento` llama a `definir_carreras_evento` dentro de la base).
8. **Hasta que se ejecute 11b**, sigue vigente la policy `eventos_insert_admin` (01), que permite un `INSERT` directo en `eventos` sin carreras. El propio 11b lo explica.
9. **Comentario desactualizado en `validadores_provider.dart`.** El comentario de `restablecerClaveValidador` dice que el servidor verifica "que quien llama sea admin", pero `restablecer-clave-validador` acepta `admin` y `superadmin`.
10. **Carrera de los admins.** `crear-usuario` no valida la carrera contra la lista oficial (el trigger de 11 solo la exige para `alumno`), pero `editar_usuario` (16) la exige para ambos roles. Un admin creado con una carrera fuera de la lista no se puede editar sin cambiársela. Desde la app no pasa, porque `alta_usuario_screen.dart` solo ofrece carreras de `carrerasProvider`.
11. **Duplicados en la carga masiva.** `alta-masiva-alumnos` detecta C.I. y correos repetidos solo dentro de cada tanda (`vistosCi`/`vistosCorreo` se crean por request). Entre tandas depende de que la app marque los repetidos con `rechazo_previo` (lo hace `clasificarFilas`) y, en la base, de que `usuarios.ci` tenga índice único: 18 solo emite un aviso si no lo tiene, y ningún script lo crea.
12. **Datos concretos en un script versionado.** `15b_crear_superadmin.sql` tiene completados el correo, el nombre y la C.I. del superadmin (no la contraseña). Este documento no los reproduce.
13. **Rol `superadmin`** (corrige el punto 1 del mapa anterior). Ya no es inalcanzable en el código: 15 lo agrega al CHECK, `RolUsuario` lo incluye y el router lo maneja. Sigue dependiendo de que 15 y 15b se hayan ejecutado en la base.

Observación de la Etapa 6: no hubo archivos nuevos que leer. Fuera del alcance solo se leyó `test/widget_test.dart`, para comprobar qué importa (solo `core/theme.dart`). No se ejecutó `flutter analyze` ni nada contra la base.
