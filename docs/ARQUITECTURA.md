# Arquitectura de `app_estudiantes` (estado verificado)

> Verificado contra el código el **11/10/2026** (commit `6b2c770`).
> Este repo es el **frontend**. El backend (`api-tienda`) tiene su propio
> `docs/ARQUITECTURA.md`; aquí solo se documenta la parte de la API que la app
> consume (sección 5).

## 1. Resumen

App Flutter (Material 3, tema claro/oscuro) con 3 pestañas — Estudiantes,
Gráficas y Predicción — que consume la API FastAPI desplegada en Render
(`https://api-tienda-wjac.onrender.com`). No tiene usuarios, sesión, estado
persistente ni caché: cada pantalla pide sus datos al abrirse.

```
main.dart ─ EstudiantesApp (MaterialApp) ─ InicioPage (NavigationBar + IndexedStack)
                                              ├─ EstudiantesScreen ─► EstudianteDetalleScreen (Navigator.push)
                                              ├─ GraficasScreen
                                              └─ PrediccionScreen
                     ApiService (una instancia, pasada por constructor a las 3 pantallas)
```

## 2. Estructura de carpetas

```
lib/
├── main.dart                     80  EstudiantesApp, InicioPage (3 pestañas, IndexedStack)
├── config.dart                   51  Config: API_URL (--dart-define), timeouts
├── theme.dart                   124  AppTheme (semilla #3F51B5) + ThemeExtension ColoresEstado
├── models/
│   ├── json_utils.dart           55  comoMapa/comoLista/leerNum/leerInt/leerString/leerBool
│   ├── estudiante.dart           76  Estudiante (+ umbralRiesgo = 3.0, normalizar())
│   ├── estadistica.dart         119  Estadistica + enum TipoEstadistica (6 rutas) + enum Unidad
│   └── prediccion.dart          145  EntradaPrediccion, ResultadoPrediccion, MetricasModelo
├── services/
│   └── api_service.dart         201  ApiService + ApiException (único punto que habla HTTP)
├── screens/
│   ├── estudiantes_screen.dart          207  lista + buscador + filtro "en riesgo" + pull-to-refresh
│   ├── estudiante_detalle_screen.dart   215  detalle (sin petición: usa los datos de la lista)
│   ├── graficas_screen.dart             291  selector de 6 estadísticas + resumen
│   └── prediccion_screen.dart           603  formulario (carrera + 4 sliders) + resultado + métricas
└── widgets/
    ├── estado_vistas.dart        186  CargandoVista (aviso "despertando"), ErrorVista, VaciaVista, AnchoMaximo
    ├── grafica_barras.dart       345  BarChart de fl_chart; etiquetas horizontales / 45° / scroll
    └── promedio_badge.dart        87  PromedioBadge, EstudianteAvatar
test/                                  36 tests (modelos, ApiService, widgets, arranque en frío)
├── support/api_falsa.dart             apiFalsa(): ApiService con MockClient por ruta
integration_test/                      2 tests contra la API real (no corren en CI)
├── app_real_test.dart                 recorre las 3 pestañas y las 6 gráficas
└── capturas_test.dart                 regenera docs/capturas/ (--dart-define=CAPTURAS_DIR)
android/ linux/ windows/ web/          plataformas generadas (no hay ios/ ni macos/)
assets/icono/                          icono.png + icono_foreground.png (flutter_launcher_icons)
.github/workflows/web.yml              CI/CD de la web
```

## 3. Capas y decisiones

| Capa | Implementación real |
|---|---|
| UI | Material 3, `ColorScheme.fromSeed(#3F51B5)`, extensión `ColoresEstado` (riesgo/ok) para claro y oscuro |
| Navegación | `NavigationBar` + `IndexedStack` (las 3 pantallas viven a la vez); `Navigator.push` imperativo al detalle; `Hero` en el avatar |
| Estado | `setState` en cada pantalla; un único `ValueNotifier<bool> despertando` en `ApiService` |
| Inyección | `ApiService` se crea en `main()` y se pasa por constructor (`EstudiantesApp` → `InicioPage` → pantallas) |
| HTTP | `package:http`; `http.Client` inyectable (tests con `MockClient`) |
| JSON | Parseo manual con `json_utils.dart`; errores de formato → `FormatException` → `ApiException` con mensaje legible |
| Gráficas | `fl_chart` `BarChart`; línea de umbral 3.0 en promedio por carrera |

### 3.1 `ApiService` (arranque en frío de Render)

| Constante (`Config`) | Valor | Uso |
|---|---|---|
| `timeout` | 8 s | servidor "despierto" |
| `timeoutArranque` | 60 s | primera petición o tras inactividad |
| `avisoDespertar` | 3 s | a partir de aquí `despertando = true` → "Despertando el servidor…" |
| `inactividadParaDormir` | 14 min | sin respuestas durante este tiempo se asume servidor dormido |

- Cualquier respuesta HTTP (incluso 4xx/5xx) marca el servidor como despierto.
- `_esLocal` (regex de IP privada/localhost) solo cambia el consejo del mensaje de error.
- Errores: `TimeoutException` y `http.ClientException` → `ApiException(statusCode: null)`;
  4xx/5xx → `ApiException` con el `detail` de FastAPI (texto, `{mensaje}` o lista de Pydantic).
- El cuerpo se decodifica a mano como UTF-8 (FastAPI no envía `charset`).
- Métodos genéricos: solo `get` y `post`. **No hay cabeceras configurables** (no hay forma de añadir `Authorization`).

### 3.2 URL de la API (`lib/config.dart`)

`--dart-define=API_URL` (tiempo de compilación) o, si falta: `http://10.0.2.2:8000`
en Android nativo, `http://127.0.0.1:8000` en el resto. Se quita la `/` final.

## 4. Dependencias (versiones resueltas en `pubspec.lock`)

| Paquete | Restricción | Resuelta | Tipo |
|---|---|---|---|
| Flutter / Dart | `sdk: ^3.13.2` | Flutter 3.47.2 · Dart 3.13.2 (stable) | — |
| `http` | ^1.6.0 | 1.6.0 | main |
| `fl_chart` | ^1.2.0 | 1.2.0 | main |
| `cupertino_icons` | ^1.0.8 | 1.0.9 | main (no se usa) |
| `flutter_lints` | ^6.0.0 | 6.0.0 | dev |
| `flutter_launcher_icons` | ^0.14.4 | 0.14.4 | dev |
| `flutter_test`, `integration_test` | sdk | — | dev |

Análisis: `flutter_lints` + `strict-casts`, `strict-raw-types`,
`prefer_single_quotes`, `prefer_final_locals`, `always_declare_return_types`,
`avoid_print`. Estado actual: `flutter analyze` → 0 issues; `flutter test` → 36/36.

## 5. Contrato con la API (lo que la app consume)

Verificado en `api-tienda/app/routers/*.py` y `app/schemas.py`. Ningún endpoint
requiere autenticación.

| Método y ruta | Respuesta | Usado en |
|---|---|---|
| `GET /estudiantes/` | `list[EstudianteOut]`, ordenado por `id` | Estudiantes |
| `GET /estudiantes/estadisticas/{tipo}` | `list[{etiqueta: str, valor: int\|float}]` | Gráficas |
| `GET /prediccion/metricas` | `dict` libre (`metricas.json`) + `carreras_validas` — **sin `response_model`** | Predicción |
| `POST /prediccion/riesgo` | `PrediccionSalida` | Predicción |

`{tipo}` ∈ `por-carrera` (desc. por cantidad), `por-edad`, `por-semestre`
(ascendentes), `por-ciudad` (top 10), `promedio-por-carrera`,
`riesgo-por-carrera` (% con promedio < 3, 2 decimales).

**`EstudianteOut`**: `id:int, nombre:str(1-50), apellido:str(1-50), edad:int(16-35),
carrera:str(1-100), semestre:int(1-10), promedio:Decimal(0-5, 2 dec) → llega como
texto "3.95", ciudad:str(1-100), horas_estudio:int(0-40), asistencia:int(0-100)`.

**`PrediccionEntrada`**: `horas_estudio, asistencia, semestre, edad, carrera`
(mismos rangos). **`PrediccionSalida`**: `en_riesgo:bool` (probabilidad sin
redondear ≥ 0.5), `probabilidad:float` (2 decimales), `modelo:str`.

Errores que la app maneja: `422` carrera desconocida →
`detail: {mensaje, carreras_validas}`; `422` de Pydantic → `detail: [{msg,…}]`;
`503` modelo no entrenado → `detail: str`.

Endpoints que existen y la app **no** usa: `GET /`, `GET|PUT|DELETE /estudiantes/{id}`,
`POST /estudiantes/`, CRUD de `/productos` y `/categorias`, `GET /categorias/{id}/productos`.

Tablas del backend (4 migraciones Alembic): `categorias`, `productos`,
`estudiantes` (CHECK de rangos), y una migración de collation `utf8mb4_unicode_ci`.

## 6. Despliegue

| Destino | Cómo | Notas |
|---|---|---|
| **Web** | `.github/workflows/web.yml`: push a `main` → `flutter analyze` → `flutter test` → `flutter build web --release --base-href /<repo>/ --dart-define=API_URL=$vars.API_URL` → GitHub Pages | Flutter fijado a 3.47.2; falla si falta la variable `API_URL` |
| **APK** | Manual: `flutter build apk --release --dart-define=API_URL=…` → `gh release create` | minSdk = `flutter.minSdkVersion` (24 → Android 7.0); firmado con la clave **debug**; `applicationId com.ejemplo.app_estudiantes` |
| **Linux / Windows** | `flutter run -d linux|windows` | sin empaquetado ni CI |
| **API** | Render free (Blueprint `render.yaml`, Oregon): build = `pip install` + `alembic upgrade head` + entrenar modelo; `uvicorn app.main:app --host 0.0.0.0 --port $PORT` | `CORS_ORIGINS=https://buelvasmanuel.github.io`; BD en Aiven MySQL con SSL |

Android: `INTERNET` declarado y `android:usesCleartextTraffic="true"` **global**
(también en release).

## 7. Diferencias con la sección 1 de `PROPUESTA_ESTUDIANTES_2.0.md`

| Propuesta dice | Código real |
|---|---|
| "~36 tests" (frontend) | Exacto: 36 en `test/` + 2 de integración que **no** corren en CI. |
| "~133 tests" (backend) | Exacto: 133 recolectados (67 funciones `test_*` con `parametrize`). |
| "Timeouts 8 s / 60 s" | Correcto, y hay dos umbrales más: aviso a los 3 s e inactividad de 14 min. |
| "`setState` + `ValueNotifier`" | Correcto; hay un solo `ValueNotifier` (`despertando`). |
| Plataformas: Android, Web, Linux, Windows | Correcto; no existen `ios/` ni `macos/`. |
| Endpoints del backend | Faltan en la lista `GET /` (health check) y `GET /categorias/{id}/productos`. |
| "Lo que NO tiene: usuarios, autenticación…" | Correcto, pero se queda corto: **las escrituras (`POST/PUT/DELETE` de estudiantes, productos y categorías) están abiertas a internet** en Render. |
| "Sin auto-deploy" en Render | No se puede comprobar desde el código: `render.yaml` no fija `autoDeploy`. Está configurado en el panel. |
| Validación con "rangos con `Annotated`" | Correcto, y los mismos rangos están **copiados a mano** en los sliders de Flutter. |

## 8. Deuda técnica

**Frontend (este repo)**

1. `ApiService` solo tiene `get`/`post` sin cabeceras: no hay dónde meter `Authorization` ni lógica de refresh.
2. `ApiService` se pasa a mano por constructores; con sesión, perfil y juego esto escala mal.
3. `IndexedStack` construye las 3 pantallas al arrancar → **4 peticiones en paralelo** (estudiantes, primera estadística, métricas). Con tokens rotativos esto provoca refrescos concurrentes (ver plan de la Fase 1).
4. Reglas de negocio duplicadas: `Estudiante.umbralRiesgo = 3.0` (y en la API `RIESGO = 3` en `estadisticas.py` y `UMBRAL_RIESGO = 3.0` en `ml.py`); rangos de los sliders en `prediccion_screen.dart:157-185`.
5. `TipoEstadistica` fija las 6 rutas en el cliente: una estadística nueva exige publicar la app.
6. Sin caché: volver a una pestaña o hacer pull-to-refresh siempre va a la red.
7. Android: `usesCleartextTraffic="true"` global, APK firmado con clave debug, `applicationId` de ejemplo, `flutter_launcher_icons.min_sdk_android: 21` no coincide con el minSdk real (24). En cuanto viajen tokens, el cleartext global no es aceptable.
8. README desactualizado: dice "Flutter 3.27 o superior" (el SDK `^3.13.2` exige Flutter 3.47+) y que "la API no tiene HTTPS" (Render sí lo tiene).
9. Publicar el APK es manual y `pubspec.yaml` sigue en `1.0.0+1`.
10. La web en GitHub Pages no puede enviar cabeceras (CSP, HSTS); solo cabe `<meta http-equiv="Content-Security-Policy">`.
11. `cupertino_icons` está declarado y no se usa; `ApiService.cerrar()` no se llama nunca (inocuo hoy).

**Backend (visto al verificar el contrato; detalle en el repo `api-tienda`)**

1. **Escrituras públicas** en `/estudiantes`, `/productos`, `/categorias`. Además el modelo se entrena en el build con lo que haya en la BD: alguien podría envenenar los datos.
2. `GET /prediccion/metricas` sin `response_model`: el contrato no aparece en OpenAPI.
3. `uvicorn` sin `--proxy-headers`: detrás del proxy de Render, `request.client.host` no es la IP real (importa para el rate limiting).
4. `healthCheckPath: /` no comprueba la BD.
5. `CORSMiddleware` con `allow_methods=["*"]`, `allow_headers=["*"]` y sin `allow_credentials` (cambiará con cookies).
6. Sin CI para la API.
7. `joblib.load` (pickle) del modelo: aceptable solo porque se genera en el build.
