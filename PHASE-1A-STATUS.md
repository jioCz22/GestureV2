# GestureChallenge v2 — Estado de Fase 1a

## Alcance de esta entrega

Se conserva la base original de aprendizaje y el trabajo de v2.0. Esta entrega completa únicamente la modularización de Fase 1a y prepara una separación explícita entre lo probado localmente y los módulos experimentales.

## Fase 1a realizada

- El navegador carga `script.js` como un único módulo ES; sus imports resuelven los datos, cuenta, eventos, progreso y módulos v2.
- `data.js` exporta datos puros. La lógica de cámara/reconocimiento continúa en `script.js`; no se reescribió el detector.
- `account.js` exporta una API en vez de publicar `window.GCAccount`. `v2.js` exporta su API en vez de `window.GCV2`.
- `progress-store.js` centraliza la clave de almacenamiento local, migraciones heredadas, serialización, saneamiento, fusión de progreso y forma de los datos sincronizados.
- `app-events.js` reemplaza eventos de coordinación en `window` por un bus de eventos importado.
- El modo invitado sigue leyendo y guardando el progreso en LocalStorage.
- El progreso histórico se sincroniza como contenido de aprendizaje; el payload no acepta ni contiene XP, monedas, puntos, rachas o historial como recompensas.
- Se quitó el crédito económico del flujo de finalización de una seña. Compras y misión diaria quedan pausadas en la interfaz hasta que la validación de servidor se corrija y se pruebe.

## Estado de módulos

**Núcleo local:** validaciones de módulos y pruebas unitarias de carga, migración, aislamiento de colecciones, fusión y forma del payload. La cámara y el reconocimiento en navegador no se consideran verificados en esta entrega.

**Cuenta y sincronización remota:** experimental, sin proyecto configurado ni pruebas de integración Supabase.

**Economía, avatar/tienda, misiones, clasificaciones, evaluaciones, laboratorio, comunidad y desafíos:** conservados como trabajo experimental. No se consideran operativos ni seguros hasta completar la preparación de Supabase, corregir sus problemas y superar pruebas de integración/seguridad. La economía está pausada en el frontend; las RPC de las migraciones todavía necesitan endurecimiento antes de habilitar un backend.

## Separación: preparación Supabase pendiente

No se editaron ni ejecutaron migraciones en esta entrega. Antes de conectar incluso un proyecto local, queda pendiente:

1. Corregir la variable incorrecta de `record_challenge_activity`.
2. No enviar respuestas correctas al cliente en evaluaciones y hacer que la puntuación tenga valor verificable.
3. Revisar grants de perfiles y RPC públicas; retirar la clasificación antigua y limitar la función de visibilidad por UUID.
4. Corregir `WITH CHECK` de actualización de reseñas.
5. Desactivar/revocar toda acreditación de monedas que no use evidencia verificable del servidor; la pausa en frontend no protege una RPC pública contra llamadas directas.
6. Habilitar moderación por capas, normalización de texto y acción humana para ocultar/suspender contenido publicado denunciado.
7. Cambiar el modelo de etapas a 1–20 niveles reales y añadir sus operaciones autorizadas.
8. Crear pruebas SQL de migración limpia, grants, RLS por roles, RPC, concurrencia, privacidad, evaluación, denuncias y suspensión.

Las Edge Functions se reservarán para proveedores externos de moderación, límites de abuso por IP y notificaciones. Las operaciones transaccionales de base de datos pueden ser RPC solo cuando las condiciones se validen enteramente en servidor.

## Pruebas ejecutadas

- `npm.cmd test`: 6 pruebas aprobadas, 0 fallidas (currículo exportado y almacenamiento/fusión de progreso).
- `node --check`: 9 archivos JavaScript comprobados.
- Revisión estática: 152 referencias literales al DOM, sin IDs faltantes; un solo punto de entrada ES.
- Comparación con la copia intacta: bloque del detector de gestos sin cambios.

Estas comprobaciones no sustituyen una prueba visual/de cámara ni el ejercicio de Supabase local. Ambos quedan pendientes; no se conectó ningún proyecto ni se ejecutaron migraciones.
