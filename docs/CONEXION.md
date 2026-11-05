# Conectar la tablet con el servidor

Guía práctica (Misión 011). Todo se hace en Fedora, desde la carpeta del repositorio.

## 1. Primera vez

```bash
cd backend
.venv/bin/pip install -e ".[dev]"     # instala segno (QR) si aún no está
cd ..
tool/install_service.sh               # el backend arranca solo y se reinicia si se cae
```

Si tenías un `uvicorn` abierto a mano, ciérralo antes con `Ctrl+C`: el script avisa si el puerto 8000 está ocupado.

## 2. Datos para la tablet

```bash
cd backend && .venv/bin/python -m app.pair
```

Muestra la **dirección** (`http://192.168.x.x:8000`) y el **token**, también como **código QR**.
En la tablet: abre la cámara (o Google Lens), apunta al QR, toca «Copiar texto» y pégalo en Servidor → Token.

El token **no** aparece en los registros del servidor a propósito: con systemd quedaría guardado en el journal.

## 3. Cambiar el token (si lo compartiste por error)

```bash
cd backend && .venv/bin/python -m app.pair --rotar
systemctl --user restart euler-notes
```

Después pon el token nuevo en la tablet (QR del paso 2). El anterior deja de valer al reiniciar.

## 4. Que la IP no cambie

El router puede dar otra IP a la compu tras reiniciar, y la tablet dejaría de conectar. Opciones, de mejor a peor:

1. **Reserva DHCP en el router (recomendada).** En la página del router (suele ser `192.168.x.1`), busca *DHCP*, *LAN* o *Reserva de direcciones*, elige tu compu por su nombre o MAC y fija su IP actual. Para ver la MAC: `ip link` (la de tu Wi-Fi, `link/ether …`).
2. **Nombre en vez de IP [Hip].** Fedora anuncia su nombre en la red con Avahi (`hostname` + `.local`, p. ej. `fedora.local`). Prueba en el navegador de la tablet `http://fedora.local:8000/health`: si responde, usa `http://fedora.local:8000` en la app y la IP dará igual. No todas las versiones de Android resuelven `.local`.
3. **IP fija en Fedora** (Configuración → Wi-Fi → tu red → IPv4 → Manual). Funciona, pero puede chocar con otro equipo si el router asigna esa IP a otro.

## 5. Problemas frecuentes

| Mensaje en la app | Causa probable | Qué hacer |
|---|---|---|
| «No se pudo conectar con el backend» | Servidor apagado, IP cambiada o redes Wi-Fi distintas | `systemctl --user status euler-notes`; comprobar la IP con `python -m app.pair`; abrir `http://IP:8000/health` en el navegador de la tablet |
| «Token de acceso incorrecto» | Token viejo o con espacios | Repetir el paso 2 y pegarlo sin espacios |
| La app no se instala («conflicto con un paquete») | APK firmado con otra clave | Ver `docs/SIGNING.md` §0 y §3 |

## 6. Comandos útiles

```bash
systemctl --user status euler-notes      # ¿está corriendo?
systemctl --user restart euler-notes     # reiniciar (tras git pull)
journalctl --user -u euler-notes -f      # registros en vivo
tool/install_service.sh --quitar         # desinstalar el servicio
```
