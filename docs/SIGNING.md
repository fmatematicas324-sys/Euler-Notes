# Firma del APK — estado actual y procedimiento

> Estado: **documento informativo**. No se ha generado ni cambiado ninguna clave. `build.gradle.kts` no se ha modificado.
> Marcas: **[H]** hecho comprobado · **[Hip]** hipótesis · **[P]** propuesta pendiente de aprobación.

## 1. Estado actual

| Aspecto | Valor | Cómo se comprobó |
|---|---|---|
| Configuración de la build `release` | `signingConfig = signingConfigs.getByName("debug")` | **[H]** `app/android/app/build.gradle.kts`, línea 36 |
| Dónde se compiló el APK v0.4.0 | Runner de GitHub Actions, run `42020254153` (11:35:52–11:44:21 UTC, 2026-11-05) | **[H]** API de GitHub Actions |
| Esquema de firma | APK Signature Scheme **v2** (sin firma v1 JAR) | **[H]** bloque de firma del APK de la release (identificador `0x7109871a`) |
| Certificado | `CN=Android Debug, O=Android, C=US` | **[H]** extraído del APK publicado |
| Validez | 2026-11-05 11:43:35 UTC → 2056-10-28 | **[H]** ídem |
| Huella SHA-256 | `32:A4:5E:CC:41:65:27:64:9E:EF:6E:2B:14:0B:18:46:05:01:97:B7:02:E0:E2:28:4C:8D:4A:78:20:9A:41:E9` | **[H]** `openssl x509 -fingerprint -sha256` |

### ¿Se puede recuperar la clave de la v0.4.0?
**No.** Motivos:
1. **[H]** El certificado se creó a las 11:43:35, **durante** la compilación. La clave debug se generó en el runner en ese momento; no venía de ningún archivo del repositorio ni de un secreto.
2. **[H]** El workflow de la v0.4.0 no guardaba `~/.android/debug.keystore`: no había caché ni artefacto.
3. **[C]** Los runners alojados de GitHub son máquinas virtuales efímeras que se destruyen al terminar el trabajo.
4. **[H]** El repositorio no contiene ningún `*.keystore` ni `*.jks`, y `.gitignore` los excluye.

### Consecuencias
- **[H]** Cada ejecución de CI genera una clave debug **distinta**. Por eso un APK de comprobación nuevo **no se instala encima** del anterior: Android exige la misma firma para actualizar.
- **[Hip]** Habrá que desinstalar la v0.4.0 una vez, cuando llegue un APK firmado con una clave estable. Hoy eso no pierde datos (están en el PC); solo se pierden la URL del servidor y, en el futuro, el token guardados en el dispositivo.
- Por eso conviene fijar la clave **antes** de que exista almacenamiento local (Etapa 2).

## 2. Procedimiento propuesto [P] — no ejecutado

### 2.1 Generar la clave (en tu PC, nunca en CI ni en esta sesión)
```bash
keytool -genkeypair -v -keystore euler-notes-upload.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias upload
keytool -list -v -keystore euler-notes-upload.jks -alias upload   # anotar la huella SHA-256
```
- Contraseñas largas y únicas, guardadas en un gestor de contraseñas.
- Anotar en este documento **solo la huella SHA-256 pública**, nunca la clave ni las contraseñas.

### 2.2 Copias de seguridad (las tres)
1. USB o disco **desconectado**, guardado en un lugar físico seguro.
2. Gestor de contraseñas: el `.jks` como adjunto, más las contraseñas y el alias.
3. Copia cifrada en otra ubicación (p. ej. `gpg -c euler-notes-upload.jks` en tu nube personal).

Verificación periódica: comprobar con `keytool -list` que cada copia abre y que su huella coincide.

### 2.3 Uso en CI (requiere aprobación y un cambio en `build.gradle.kts`)
- Secretos del repositorio: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`.
- Solo `release.yml` los usaría; `ci.yml` seguiría con la firma debug.
- El job crea `key.properties` y el `.jks` en el runner, y los borra al terminar. Ambos ya están en `.gitignore`.
- Gradle usa `key.properties` si existe y, si no, la firma debug (así las compilaciones locales y de PR siguen funcionando).

### 2.4 Recuperación
| Situación | Qué hacer |
|---|---|
| Se pierde una copia | Restaurar desde otra y rehacer la copia perdida |
| Se pierden **todas** y la app se distribuye por APK | Generar una clave nueva; todos los usuarios deben desinstalar y reinstalar (**perderían los datos locales** tras la Etapa 2, salvo exportación previa) |
| La app está en Google Play con Play App Signing | La clave pública de la app la custodia Google; se pide a Google restablecer la **clave de subida** |
| Se filtra la clave | Generar una clave nueva y revocar los secretos. **[P]** Valorar Play App Signing |

## 3. Migración a la clave estable [P] — no ejecutada

**Punto de partida [H]:** la v0.4.0 instalada está firmada con una clave debug que ya no existe. Android **no permite** instalar encima un APK con otra firma: muestra "La app no se ha instalado" o "conflicto con un paquete existente" **[C]**. No hay forma de "migrar" la firma de una app instalada sin la clave original (la rotación de claves de APK Signature Scheme v3 necesita la clave antigua para firmar el certificado nuevo **[C]**).

**Por tanto, la primera versión con la clave estable exige desinstalar una vez.** Procedimiento:

1. **Antes de publicar** la versión firmada (p. ej. `v0.4.1+5`):
   - Comprobar la huella del APK del borrador: `apksigner verify --print-certs euler-notes-0.4.1.apk` debe mostrar la huella anotada en §2.1.
   - Avisar en las notas de la release: "Esta versión cambia la firma: desinstala la anterior primero".
2. **En cada dispositivo:**
   1. Anotar la dirección del servidor y el token (Servidor → Token, botón "Mostrar"), o tenerlos a mano en el PC (`backend/data/api_token`).
   2. Desinstalar Euler Notes (Ajustes → Aplicaciones → Euler Notes → Desinstalar).
   3. Instalar el APK nuevo.
   4. Volver a configurar el servidor y el token.
3. **Qué se pierde:** solo la configuración del dispositivo (URL y token). Los cuadernos, notas, dibujos y PDF están en el PC **[H]** y no se tocan.
4. **A partir de ahí**, todas las versiones firmadas con la misma clave se instalan encima, sin desinstalar, siempre que `N` (versionCode) sea mayor.

**Cuándo hacerlo:** antes de la Etapa 2. Cuando los datos vivan en el dispositivo, desinstalar los borraría.

## 4. Pendiente de decisión
- Aprobar la generación de la clave (la generas tú) y el cambio en `build.gradle.kts`.
- Decidir si se publicará en Google Play. Si es así, conviene Play App Signing desde el principio.
