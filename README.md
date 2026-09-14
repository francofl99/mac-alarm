# MacAlarm

Alarma anti-manoseo para macOS. Se arma con un atajo global y, si alguien toca el teclado, suena,
tapa las pantallas con un mensaje y bloquea el teclado hasta que la desactives.

> Menu bar app for macOS: arm it with a global shortcut and it alarms — sound, fullscreen message and
> keyboard lockout — on the next keystroke. Spanish UI.

Sirve para dejar la Mac desatendida un rato sin bloquear la sesión: si el gato, un compañero de
oficina o un hermano menor tocan una tecla, se enteran.

## Cómo funciona

1. Activás con `⌃⌥⌘A` (configurable) o desde el menú del ícono.
2. Arranca una cuenta regresiva (20 s por defecto) para que puedas soltar el teclado.
3. Queda armada: el mouse no la dispara, cualquier tecla sí.
4. Al dispararse: audio en loop o repetido cada N segundos, pantalla negra con el texto en grande en
   todos los monitores, teclado bloqueado.

Se corta con el atajo o con **Desactivar alarma** en el menú del ícono; la pantalla no lo anuncia.
El overlay queda por debajo del nivel de la barra de estado a propósito: el mouse es siempre la
salida de emergencia.

| Ícono | Estado |
|-------|--------|
| 🔕 | inactiva |
| ⏱ N | armándose |
| 🔔 | armada |
| 🔔〰 | sonando |

## Requisitos

- macOS 13 o superior
- Swift 5.9+ (Xcode Command Line Tools)

## Instalación

```bash
git clone https://github.com/francofl99/mac-alarm.git
cd mac-alarm
./build.sh
open MacAlarm.app
```

Después, conceder **Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → MacAlarm**. Sin
ese permiso la app no puede leer ni bloquear el teclado.

Para que arranque con la sesión: Ajustes del Sistema → General → Ítems de inicio → `+` → `MacAlarm.app`.

## Configuración

Menú del ícono → **Configuración…** (delay, mensaje, sonido con botón *Probar*, repetición, volumen,
bloqueo de teclado y grabador de atajo).

Si el ícono no aparece en la barra, la misma ventana se abre desde la terminal:

```bash
MacAlarm.app/Contents/MacOS/MacAlarm --settings
```

El archivo vive en `~/Library/Application Support/MacAlarm/config.json`:

```json
{
  "delaySeconds": 20,
  "message": "NO TOQUES EL TECLADO",
  "soundPath": "/System/Library/Sounds/Sosumi.aiff",
  "repeatIntervalSeconds": 3,
  "blockKeyboard": true,
  "volume": 1,
  "hotKey": { "key": "A", "modifiers": ["control", "option", "command"] }
}
```

- `repeatIntervalSeconds: 0` → el audio suena en loop continuo.
- `soundPath` acepta cualquier formato que lea AVFoundation (aiff, wav, mp3, m4a).
- `blockKeyboard: false` → suena y muestra el mensaje, pero te deja seguir escribiendo.

## Arquitectura

| Archivo | Responsabilidad |
|---------|-----------------|
| `AppDelegate.swift` | ícono de estado, menú, ciclo de vida, instancia única |
| `AlarmController.swift` | máquina de estados (inactiva → armándose → armada → sonando) y audio |
| `KeyWatcher.swift` | `CGEventTap` de sesión: detecta teclas y las traga mientras suena |
| `HotKeyCenter.swift` | atajo global vía Carbon `RegisterEventHotKey` |
| `Overlay.swift` | ventanas negras a pantalla completa en cada monitor |
| `SettingsWindowController.swift` | ventana de configuración en AppKit |
| `Config.swift` | modelo JSON y mapa de keycodes |

Mientras la alarma suena el atajo no llega a Carbon (el tap se lo come antes), así que en ese estado
lo resuelve el propio `KeyWatcher`.

## Seguridad y límites

- El bloqueo de teclado vive dentro del proceso: si matás MacAlarm desde Monitor de Actividad, el
  teclado vuelve al instante. No hay forma de quedar encerrado sin mouse.
- No bloquea el mouse, a propósito.
- No es un reemplazo del bloqueo de pantalla: no protege datos, solo avisa y molesta.
- La app no hace red ni telemetría; el único archivo que escribe es su `config.json`.

## Desarrollo

```bash
swift build -c release   # compila
./build.sh               # compila + arma MacAlarm.app + firma
```

`build.sh` firma ad-hoc por defecto, lo que cambia el cdhash en cada build y hace que macOS deje de
reconocer el permiso de Accesibilidad aunque el toggle siga encendido. El script detecta el cambio,
resetea esa autorización y la app la vuelve a pedir.

Para evitarlo, creá un certificado de tipo *Code Signing* en Acceso a Llaveros y buildeá con él:

```bash
MACALARM_IDENTITY="MacAlarm Dev" ./build.sh
```

El permiso queda atado al certificado y sobrevive recompilaciones.

## Licencia

MIT — ver [LICENSE](LICENSE).
