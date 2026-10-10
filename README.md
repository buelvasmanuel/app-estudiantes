# Estudiantes

App Flutter (Material 3) que consume la API FastAPI de `api-tienda` y tiene
tres pestañas:

| Pestaña | Qué hace | Endpoints |
|---|---|---|
| **Estudiantes** | Listado con buscador, filtro "en riesgo", indicador de color (promedio < 3.0), pull-to-refresh y pantalla de detalle | `GET /estudiantes/` |
| **Gráficas** | Gráfica de barras (fl_chart) de 6 estadísticas, con el valor encima de cada barra y un resumen | `GET /estudiantes/estadisticas/{tipo}` |
| **Predicción** | Formulario (carrera + 4 sliders) que predice el riesgo académico, con el resultado en rojo/verde y las métricas del modelo | `GET /prediccion/metricas`, `POST /prediccion/riesgo` |

<p>
  <img src="docs/capturas/1_estudiantes.png" width="200" alt="Listado de estudiantes">
  <img src="docs/capturas/3_grafica_por_carrera.png" width="200" alt="Gráfica por carrera">
  <img src="docs/capturas/5_prediccion_en_riesgo.png" width="200" alt="Predicción en riesgo">
  <img src="docs/capturas/6_sobre_el_modelo.png" width="200" alt="Métricas del modelo">
</p>

## Requisitos

- Flutter 3.27 o superior (probado con 3.47.2 / Dart 3.13).
- La API `api-tienda` con datos (`python -m scripts.seed_estudiantes`) y el
  modelo entrenado (`python -m scripts.entrenar_modelo`).
- Paquetes: [`http`](https://pub.dev/packages/http) 1.6 y
  [`fl_chart`](https://pub.dev/packages/fl_chart) 1.2.

```bash
flutter pub get
```

## 1. Arrancar la API

En `~/Proyectos/api-tienda`, con el entorno virtual activado:

```bash
uvicorn app.main:app --reload --host 0.0.0.0
```

`--host 0.0.0.0` hace que la API escuche en **todas** las interfaces de red.
Con el valor por defecto (`127.0.0.1`) solo acepta conexiones del propio PC,
y el celular no podría llegar a ella por WiFi.

Comprueba que responde: <http://127.0.0.1:8000/docs>.

## 2. Ejecutar la app

### Linux (escritorio) — lo más rápido para desarrollar

```bash
flutter run -d linux
```

### Chrome / Brave (web)

```bash
flutter run -d chrome
```

Funciona porque la API permite CORS desde cualquier origen
(`allow_origins=["*"]`, solo para desarrollo).

### Celular por USB (recomendado para probar en el celular)

Activa la *depuración USB* en el celular (Opciones de desarrollador),
conéctalo y comprueba que aparece en `flutter devices`. Después:

```bash
adb reverse tcp:8000 tcp:8000
flutter run -d <id-del-celular> --dart-define=API_URL=http://127.0.0.1:8000
```

`adb reverse` crea un túnel por el cable: el puerto 8000 **del celular**
lleva al puerto 8000 **del PC**. Así no dependes de la WiFi, de la IP del PC
ni del cortafuegos. Hay que repetirlo cada vez que se desconecta el cable.

### Celular por WiFi (misma red que el PC)

```bash
ip -4 addr            # busca la IP de la WiFi: inet 192.168.x.y/24
flutter run -d <id-del-celular> --dart-define=API_URL=http://192.168.x.y:8000
```

Si no conecta, abre el puerto en el cortafuegos
(`sudo ufw allow 8000/tcp` o `sudo firewall-cmd --add-port=8000/tcp`).

### Emulador de Android

Crea un emulador en Android Studio (*Device Manager*) y:

```bash
flutter emulators --launch <nombre>
flutter run
```

No hace falta `--dart-define`: en Android la app usa por defecto
`http://10.0.2.2:8000`, la dirección especial con la que el emulador llega al
PC anfitrión (dentro del emulador, `127.0.0.1` es el propio emulador).

## Configuración de la URL de la API

La URL se decide en `lib/config.dart`:

| Dónde corre | URL por defecto |
|---|---|
| Android (emulador) | `http://10.0.2.2:8000` |
| Linux, Chrome, etc. | `http://127.0.0.1:8000` |
| Cualquiera, con `--dart-define=API_URL=...` | la que indiques |

`String.fromEnvironment('API_URL')` se resuelve **al compilar**: si cambias
la URL hay que volver a lanzar `flutter run` (el *hot reload* no basta).

## Android: `INTERNET` y `usesCleartextTraffic`

En `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application android:usesCleartextTraffic="true" ...>
```

- **`INTERNET`**: sin este permiso Android no deja que la app abra conexiones
  de red. En modo *debug* Flutter lo añade por su cuenta, pero en *release*
  (`flutter build apk`) la app no podría hablar con la API si faltara.
- **`usesCleartextTraffic="true"`**: desde Android 9 se bloquea por defecto el
  tráfico HTTP **sin cifrar** (`http://`, sin la *s*). Nuestra API de clase no
  tiene HTTPS, así que lo permitimos. **Solo para desarrollo**: en producción la
  API debería ir por `https://` y esta línea debería quitarse (o limitarse a un
  dominio con un `network_security_config`).

## Estructura

```
lib/
├── main.dart                  # MaterialApp + NavigationBar (IndexedStack)
├── config.dart                # URL de la API (--dart-define) y timeout
├── theme.dart                 # Tema M3 claro/oscuro + colores de riesgo/ok
├── models/
│   ├── json_utils.dart        # Lectura segura de JSON (num, String, bool...)
│   ├── estudiante.dart
│   ├── estadistica.dart       # Estadistica + enum TipoEstadistica (6 tipos)
│   └── prediccion.dart        # Entrada, resultado y métricas del modelo
├── services/
│   └── api_service.dart       # Único punto que habla con la API
├── screens/
│   ├── estudiantes_screen.dart
│   ├── estudiante_detalle_screen.dart
│   ├── graficas_screen.dart
│   └── prediccion_screen.dart
└── widgets/
    ├── estado_vistas.dart     # Cargando / Error con Reintentar / Vacío
    ├── grafica_barras.dart    # BarChart de fl_chart
    └── promedio_badge.dart    # Pastilla y avatar con el color del riesgo
```

## Tests

```bash
flutter analyze                 # análisis estático: 0 issues
flutter test                    # tests de modelos y de widgets (API simulada)
```

Los tests de widgets usan `MockClient` (de `package:http/testing.dart`) para
simular la API: no necesitan red ni la API encendida.

Con la API corriendo, la prueba de extremo a extremo abre la app de verdad y
comprueba que las 3 pestañas cargan datos reales (y las 6 gráficas):

```bash
flutter test integration_test/app_real_test.dart -d linux
```

Para regenerar las capturas de `docs/capturas/` (tamaño celular, datos reales):

```bash
flutter test integration_test/capturas_test.dart -d linux \
  --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
```

## Problemas típicos

| Síntoma | Causa y solución |
|---|---|
| "Sin conexión con la API" | La API no está corriendo, o no escucha en `0.0.0.0`, o la URL no es la correcta para ese dispositivo (ver tabla de arriba). |
| Funciona en Linux pero no en el celular | Falta `adb reverse tcp:8000 tcp:8000` (USB) o la IP/cortafuegos (WiFi). |
| "Servicio no disponible (503): Modelo no entrenado" | En la API: `python -m scripts.entrenar_modelo`. |
| Lista vacía | En la API: `python -m scripts.seed_estudiantes`. |
| El celular aparece y desaparece en `flutter devices` | Hay dos `adb` instalados (`/usr/bin/adb` y el del SDK). Deja solo uno. |
| Cambié `API_URL` y no hace nada | Es de compilación: detén la app y vuelve a hacer `flutter run`. |

## Detalles técnicos que vale la pena conocer

- **El promedio llega como texto** (`"promedio": "3.95"`): en Python es un
  `Decimal` y Pydantic lo envía como string para no perder precisión. Por eso
  los modelos leen los números con `leerNum`, que acepta `int`, `double` o
  `String`. `valor` y `probabilidad` se guardan como `num` (pueden ser `30` o
  `33.33`).
- **UTF-8**: FastAPI no indica el *charset*, así que se decodifica
  `response.bodyBytes` como UTF-8 a mano (si no, "Ingeniería" saldría mal).
- **Errores**: `ApiService` convierte los fallos en un `ApiException` con un
  mensaje para el usuario: sin conexión, *timeout* (8 s), y los `detail` de
  FastAPI (texto, objeto propio o lista de validación de Pydantic).
- **`IndexedStack`** mantiene vivas las 3 pestañas: al cambiar no se pierde la
  búsqueda ni el formulario, ni se repiten peticiones.
- **`if (!mounted) return;`** después de cada `await` antes de `setState`: la
  pantalla pudo cerrarse mientras llegaba la respuesta.
- **Gráficas legibles**: las etiquetas se miden con `TextPainter` y se ponen
  horizontales, inclinadas 45° o con scroll según el espacio disponible.
- **Las probabilidades del modelo** salen "infladas" hacia el riesgo
  (`class_weight="balanced"`): sirven para ordenar estudiantes, no como un
  porcentaje literal. Es un indicador orientativo, no un diagnóstico.

## Icono

Generado a partir de `assets/icono/icono.png` con:

```bash
dart run flutter_launcher_icons
```
