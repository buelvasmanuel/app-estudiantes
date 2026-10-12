# Contrato de animación: búho y medidor en Rive (Fase 7.3)

> Entre quien diseña los `.riv` en el editor de Rive y `app_estudiantes`.
> Versión **1**, 2026-10-12. Si un nombre o un tipo no coincide, la app no
> falla: sigue usando el búho y el medidor dibujados en Flutter, y el test
> `test/rive_contrato_test.dart` dice qué falta.

## 1. Qué hay que entregar

| Archivo | Ruta en el proyecto | Artboard | Máquina de estados | View model |
|---|---|---|---|---|
| Búho | `assets/rive/buho.riv` | `Buho` | `Buho` | `Buho` |
| Medidor | `assets/rive/medidor.riv` | `Medidor` | `Medidor` | `Medidor` |

- Exporta el archivo para runtime (**File → Export → for runtime**, `.riv`).
- Cada view model debe estar **asignado al artboard** (Data → *Bind view
  model*), con una instancia por defecto. La app se enlaza a esa instancia y
  cambia sus propiedades.
- Solo formas vectoriales: **sin imágenes ni fuentes incrustadas** y **sin
  texto**. Los textos los pone la app (no se animan nunca y los lee el lector
  de pantalla).
- Tamaño de cada `.riv`: **≤ 150 KB** (se descargan también en la web).
- Mayúsculas, minúsculas y tildes cuentan: `Buho` sin tilde, `animo` sin
  tilde.

## 2. El búho

**Artboard `Buho`:** cuadrado, **256 × 256**. La app lo enseña entre **48 y
120 px** de lado: tiene que entenderse a 48 px (formas simples, ojos grandes,
líneas de al menos 6 px en el artboard).

**View model `Buho`:**

| Propiedad | Tipo | Valores | Qué hace |
|---|---|---|---|
| `animo` | enum | `atento`, `pensando`, `preocupado`, `contento`, `celebrando` | La expresión. La app la cambia cuando cambia lo que dice el búho |
| `quieto` | boolean | `true` / `false` | "Reducir movimiento" del sistema. Con `true`: cambios de expresión **instantáneos**, sin parpadeo ni movimiento en reposo |
| `plumas` | color | — | Cuerpo y alas. La app lo calcula a partir del tema |
| `barriga` | color | — | Barriga y cara |
| `ojo` | color | — | Blanco de los ojos |
| `pupila` | color | — | Pupilas y contornos finos |
| `pico` | color | — | Pico y patas |

El enum `animo` debe tener **exactamente** esos 5 valores, con esos nombres.
Los colores no se fijan en el diseño: enlaza los rellenos a estas propiedades
(la app manda los del tema Noche o Expediente). Los valores por defecto del
view model solo se ven en el editor.

**Expresiones** (las mismas que el búho actual):

| `animo` | Cuándo sale | Idea |
|---|---|---|
| `atento` | Por defecto, al dar consejos | Ojos abiertos, mirada al frente |
| `pensando` | Turno del rival, una pista | Mirada hacia arriba o de lado, ala en la barbilla |
| `preocupado` | Riesgo alto, ronda perdida, poco tiempo | Cejas inclinadas, ojos algo más pequeños |
| `contento` | Acierto, ronda ganada | Ojos en arco (sonriendo) |
| `celebrando` | Rescate logrado, subida de nivel | Alas arriba, un salto pequeño |

## 3. El medidor de riesgo

**Artboard `Medidor`:** **400 × 200** (2:1), un semicírculo de 0 a 100 %
con la base abajo, como el actual.

**View model `Medidor`:**

| Propiedad | Tipo | Rango | Qué hace |
|---|---|---|---|
| `probabilidad` | number | 0–100 | El riesgo estimado: mueve la aguja |
| `objetivo` | number | 0–100 | Dónde va la marca del objetivo (hoy, 50). Por debajo, zona verde; por encima, roja |
| `quieto` | boolean | — | Con `true`, la aguja salta al valor sin animación |
| `ok` | color | — | Zona por debajo del objetivo (verde del tema) |
| `riesgo` | color | — | Zona por encima del objetivo (rojo del tema) |
| `aguja` | color | — | Aguja y marca del objetivo |
| `fondo` | color | — | Arco sin rellenar |

**Hueco para el texto:** la app escribe el porcentaje («49 %») y «riesgo según
el modelo» centrados en el artboard, en una zona de **45 % del ancho × 40 %
del alto**, centrada en el punto (50 %, 78 %). Deja esa zona libre: la aguja
puede pasar por encima, pero ningún adorno fijo.

## 4. Reglas de movimiento (PROPUESTA §2.4)

- **Una sola animación protagonista** en cada momento. El búho y el medidor
  acompañan: no compiten con el giro de la carta del duelo ni con la
  celebración.
- **Cambio de expresión: ≤ 400 ms.** Aguja: **≤ 400 ms**, con freno al final
  (*ease out*).
- `celebrando`: un único gesto de **≤ 1,2 s**, sin bucle; después queda en
  pose de contento.
- **En reposo, como mucho un parpadeo** cada 4–6 s (≤ 150 ms). Nada más se
  mueve solo.
- Nada que parpadee más de 3 veces por segundo, sin destellos de pantalla
  completa.
- Con `quieto = true`: transiciones de duración 0 y sin parpadeo. Es lo que
  pide la persona en su sistema y es obligatorio.
- Nada dura más de **1,5 s**.

## 5. Cómo lo usa la app

- `lib/laboratorio/apariencia_rive.dart` carga los dos archivos al arrancar.
  Si un archivo falta o no cumple este contrato, ese elemento se sigue
  dibujando con Flutter: se puede entregar primero el búho y después el
  medidor.
- La app cambia las propiedades (`animo`, `probabilidad`, colores…) y deja
  que la máquina de estados anime. Para todo lo que se lee usa
  `Semantics` propios («Búho guía (contento)», «Riesgo estimado por el
  modelo: 49 %…»).
- Los colores salen del tema: en Noche, plumas cálidas sobre fondo oscuro; en
  Expediente, sobre papel. Son los mismos que usa hoy el búho dibujado en
  Flutter. Prueba el diseño con estos dos juegos (los valores reales):

| Propiedad | Noche | Expediente |
|---|---|---|
| `plumas` | `#BB925E` | `#616173` |
| `barriga` | `#80754D` | `#E2ECF9` |
| `ojo` | `#FFFFFF` | `#FFFFFF` |
| `pupila` | `#212121` | `#212121` |
| `pico` | `#F2A33A` | `#F2A33A` |
| `ok` | `#6EE7A8` | `#2E7D32` |
| `riesgo` | `#FF7B7B` | `#B3261E` |
| `aguja` | `#EEF0FF` | `#2A2622` |
| `fondo` | `#303865` | `#E8D9B8` |

Fondo de la pantalla detrás del búho: Noche, azul muy oscuro; Expediente,
papel claro. El búho debe leerse sobre los dos.

- **En la web**, el motor de Rive (WASM, unos 3 MB sin comprimir) se descarga
  la primera vez que hace falta, es decir, solo cuando existen los `.riv`.

## 6. Comprobar un `.riv` antes de entregarlo

Copia los archivos a `assets/rive/` y ejecuta:

```bash
flutter test test/rive_contrato_test.dart
```

El test abre cada archivo y dice, en español, qué falta o qué tipo no
coincide (por ejemplo «Buho: falta la propiedad `quieto` (boolean)»). Si
pasa, la app ya los usa.
