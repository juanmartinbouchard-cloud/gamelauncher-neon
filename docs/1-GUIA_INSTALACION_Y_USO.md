# Guía de Instalación, Uso y Desinstalación — GameLauncher Neon

## 1. Cómo abrir GameLauncher sin complicaciones (Modo Directo)
1. **Descomprime el archivo ZIP** completo en cualquier carpeta de tu ordenador (por ejemplo, en `Mis Documentos\GameLauncher_Neon` o en el `Escritorio`).
2. Entra en la carpeta descomprimida y haz **doble clic** en:
   `ABRIR_GAMELAUNCHER.bat`
3. **¿Qué hace este archivo?**
   - Comprueba si ya existe `GameLauncher.exe` en tu carpeta.
   - Si es la primera vez que lo abres, utiliza el compilador oficial de Microsoft que ya viene integrado dentro de Windows 10 y Windows 11 (`csc.exe`) para crear `GameLauncher.exe` directamente en tu ordenador en menos de 2 segundos y lo abre automáticamente.
   - A partir de ese instante, verás el archivo `GameLauncher.exe` con su icono neón en la carpeta y podrás abrirlo directamente siempre que quieras.
4. Si quieres tener el acceso directo en tu Escritorio de Windows, haz doble clic en `CREAR_ACCESO_DIRECTO_ESCRITORIO.bat`.

## 2. Cómo gestionar tu Biblioteca de Juegos
- **Añadir un juego:** Pulsa el botón `+ AÑADIR JUEGO`, haz clic en `Examinar .exe...` y selecciona el archivo ejecutable del juego. El nombre y el icono oficial se cargarán automáticamente. Opcionalmente puedes asignarle una imagen de carátula (`.png` o `.jpg`).
- **Jugar:** Pulsa `▶ JUGAR` en la tarjeta del juego.
- **Editar o actualizar ruta:** Si moviste un juego de carpeta o de disco duro, su tarjeta mostrará `● Ruta no disponible`. Pulsa el botón `✎` para indicar dónde está ahora el archivo `.exe`.
- **Quitar de la biblioteca:** Pulsa el icono de papelera (`🗑`). Esto solo quita la tarjeta del lanzador; **jamás borra ni modifica los archivos originales de tus juegos**.
- **Copias de seguridad:** En la pestaña `Configuración y Datos`, puedes exportar toda tu biblioteca a un archivo `.json` o importarla en otro ordenador.

## 3. Ubicación de los Datos y Privacidad
- Todos tus datos se guardan localmente en:
  `%LocalAppData%\GameLauncherNeon\library.json`
- El registro de eventos y errores se guarda en:
  `%LocalAppData%\GameLauncherNeon\logspp.log`
- La aplicación no se conecta a Internet, no recopila telemetría y no solicita permisos de Administrador.
