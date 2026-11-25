# GestureChallenge v2 — Supabase Cloud (Dashboard)

## Estado

Las 10 migraciones fueron revisadas estáticamente y corregidas para una instalación nueva. No se ejecutó SQL. La sintaxis final debe validarse en un proyecto de prueba de Supabase Cloud antes de usar un proyecto con datos. El paquete no depende de CLI ni Docker.

## Archivos

- `supabase/migrations/20261123000100_profiles_and_player_progress.sql` a `20261123001000_phase1b_security_hardening.sql`, en orden ascendente.
- `supabase/dashboard/security_checks.sql`: comprobaciones SQL de catálogo, RLS y permisos; ejecutar después de las migraciones.
- No se entrega un SQL maestro. Las migraciones contienen DDL no idempotente y el SQL Editor podría dejar estado parcial si falla una ejecución intermedia. Ejecutarlas una por una permite identificar y reparar con precisión el archivo que falla; solo continuar cuando la ejecución anterior terminó sin error. Esta es una decisión deliberada de seguridad.

## Instalación desde Supabase Dashboard

1. Crea un proyecto Cloud **de prueba** vacío. No uses un proyecto con datos de usuarios.
2. Abre **SQL Editor → New query**.
3. Abre cada archivo de `supabase/migrations/` localmente, copia su contenido completo y pégalo en una query nueva.
4. Ejecuta exactamente de `20261123000100` a `20261123001000`, esperando confirmación de éxito por cada archivo. No los combines, no repitas una migración parcialmente ejecutada y no continúes si aparece un error.
5. Ejecuta `supabase/dashboard/security_checks.sql`. Debe terminar con `PASS: 16 catalog, RLS, and privilege checks`.
6. En caso de error, detente. No intentes corregirlo sobre una base con estado parcial sin revisar los objetos ya creados.

Las migraciones están diseñadas para primera instalación, no como scripts repetibles ni como actualización de una base ya migrada parcialmente. Esta ejecución no es necesaria para revisar el paquete; la hizo explícitamente el usuario bajo su control.

## Authentication

En **Authentication → Sign In / Providers → Email**:

- Habilita Email + contraseña.
- Mantén **Confirm email** activado.
- Mantén los inicios anónimos desactivados.
- Define la longitud mínima de contraseña de acuerdo con la política del proyecto (la UI valida 8 caracteres).

En **Authentication → URL Configuration**:

- Configura `Site URL` con el origen HTTPS de la aplicación publicada.
- Agrega como redirect URLs solo orígenes/rutas exactos que realmente uses, incluidos los de desarrollo servidos por `localhost` (no abras comodines amplios en producción).
- Prueba confirmación de correo y recuperación de contraseña desde las URLs permitidas.

## Conexión del frontend

En `supabase-config.js`, establece:

```js
export const SUPABASE_CONFIG = Object.freeze({
  url: "https://<project-ref>.supabase.co",
  anonKey: "sb_publishable_..."
});
```

También se acepta la clave heredada `anon`. Esta propiedad es pública e incluida en el navegador; la seguridad depende de RLS y de los permisos SQL. **Nunca configures la clave `secret` ni `service_role` en este archivo, HTML, módulos JS, repositorio o variables frontend.** No hay `.env` en esta aplicación estática. Si se migra a un proceso de build, usa variables públicas (por ejemplo `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY`) solo para URL y clave publicable.

La autenticación y sincronización existente están en `account.js`: usa sesiones de Supabase Auth, lee y escribe únicamente la fila `player_progress` del usuario autenticado, y excluye puntos, monedas, rachas e historial local del payload. Prueba cuenta, confirmación, login, logout, recuperación, merge y aislamiento entre dos usuarios.

## Storage

No se requiere bucket de Supabase Storage para esta entrega. Las imágenes de referencia son assets estáticos dentro de `assets/`; `avatar_url` es solo un valor de perfil y no hay flujo de carga de archivos implementado. No crees buckets públicos.

## Funcionalidades que deben seguir deshabilitadas/experimentales

- Compras, misión diaria económica y recompensas en frontend (`ECONOMY_REWARDS_ENABLED = false`). No hay servicio confiable que compruebe evidencia de señas; no acredites XP/monedas desde el navegador ni importes monedas históricas.
- `record_stage_completion` falla de forma segura hasta que exista verificación de finalización confiable. Desafíos que dependan de ese registro tampoco están verificados.
- Evaluaciones tienen puntuación server-side y la respuesta no se devuelve como campo de API; requieren prueba funcional de RPC y tasa de intentos en Cloud de prueba.
- La publicación continúa requiriendo moderación humana. Hay filtros de etiquetas y enlaces, pero falta lista de ofensivos curada, normalización completa de texto y una política probada de falsos positivos. No se debe declarar completa la moderación automática.
- La RPC de suspensión está disponible para moderadores, pero la UI aún no ofrece esa acción.
- No añadir service/secret key al cliente. Una eventual Edge Function requiere despliegue y controles propios; todavía no existe.



## Asignar moderadores

Solo el administrador del proyecto asigna moderadores. Después de crear y confirmar la cuenta correspondiente, sustituye el correo de ejemplo y ejecuta esta sentencia en SQL Editor:

```sql
insert into public.moderators(user_id)
select id from auth.users where lower(email)=lower('moderador@example.com')
on conflict (user_id) do nothing;
```

Comprueba que afectó una fila. La app cliente no recibe permisos para alterar `public.moderators`.
