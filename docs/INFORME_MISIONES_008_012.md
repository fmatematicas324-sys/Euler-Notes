# Informe de trabajo — Misiones 008 a 012

> Fecha: 2026-11-05. Rama: `misiones-009-012` (la 008 ya está en `master`, PR #3).
> Marcas: **[H]** comprobado · **[Hip]** sin comprobar · **[P]** propuesta.

## 1. Resumen

| Misión | Qué consigue | Estado |
|---|---|---|
| **008** Superficies 3D | z = f(x, y) en 3D con curvas de nivel | ✅ En `master`; probado en la tablet [H] |
| **009** Documentación | Auditoría actual y análisis de experiencia (con Obsidian) | ✅ |
| **010** Firma estable | Que cada APK nuevo se instale encima sin desinstalar | ◐ Código listo y probado en CI [H]; **falta tu clave** |
| **011** Conexión cómoda | Dirección y token con QR; backend que arranca solo | ◐ Código listo; **falta instalarlo en Fedora** |
| **012** Más figuras | Curvas de nivel, campos vectoriales y curvas 3D | ✅ CI en verde [H]; **falta verlas en la tablet** |

## 2. Qué se hizo

### Misión 008 — Superficies 3D (PR #3, fusionado)
- **Diagnóstico corregido [H]:** el aviso «solo puede depender de x (contiene y)» venía del **backend**, no del validador de Flutter como decía el resumen anterior.
- Nuevo tipo `surface` en `POST /diagram` y bloque ` ```diagram ` con `tipo: superficie`.
- El diagrama de función sugiere «tipo: superficie» cuando hay una segunda variable.
- Archivos: `backend/app/services/diagrams.py`, `backend/app/domain/models.py`, `app/lib/features/plot/domain/diagram_spec.dart` y sus pruebas. ADR 18.

### Misión 009 — Documentación
- `docs/product_research/AUDIT_REPORT.md`: estado del código, los 9 problemas de la Misión 002 (6 resueltos o casi), seguridad verificada en el código y riesgos priorizados.
- `docs/product_research/ONENOTE_ANALYSIS.md`: síntesis de OneNote, MyScript Notes (Nebo), Goodnotes, Flexcil y **Obsidian** (nuevo), con principios de experiencia y funciones priorizadas para un cuaderno científico privado y ligero. No repite los informes de la Misión 002, los resume.

### Misión 010 — Firma estable del APK
- **Causa [H]:** cada ejecución de CI creaba una clave de firma nueva; por eso Android decía «conflicto con un paquete».
- `app/android/app/build.gradle.kts`: firma con `android/key.properties` si existe; si no, con la clave debug (las compilaciones locales siguen funcionando).
- `.github/workflows/ci.yml` y `release.yml`: crean la clave a partir de los secretos `ANDROID_*`, muestran la **huella SHA-256** del APK y borran la clave al terminar. Sin secretos, avisan y siguen como antes (comprobado en CI [H]).
- `docs/SIGNING.md` §0: tus pasos, con comandos. ADR 15 pasa a **Aceptada**.

### Misión 011 — Conexión cómoda
- `python -m app.pair`: muestra la **dirección** de tu compu en la red y el **token como QR** para escanearlo con la cámara de la tablet. `--rotar` crea un token nuevo.
- El token ya no se escribe nunca en los registros del servidor (ADR 19).
- `tool/install_service.sh`: instala el backend como **servicio de systemd** (arranca solo, se reinicia si se cae; sin sudo).
- `docs/CONEXION.md`: guía completa, IP fija y tabla de problemas frecuentes (los que viviste hoy).
- Dependencia nueva: `segno` (QR, Python puro, sin dependencias).

### Misión 012 — Figuras científicas nuevas (ADR 20)
Tres tipos nuevos en `/diagram`, con bloques, plantillas en el editor y pruebas:

````
```diagram
tipo: curvas de nivel
f: x^2 - y^2
x: -3, 3
y: -3, 3
niveles: 12          ← opcional (3 a 40)
relleno: no          ← opcional: solo líneas
```

```diagram
tipo: campo vectorial
P: -y
Q: x
x: -3, 3
y: -3, 3
modo: lineas         ← opcional: líneas de campo en vez de flechas
```

```diagram
tipo: curva 3d
x: cos(t)
y: sin(t)
z: t/5
t: 0, 4pi
```
````

- El **campo vectorial** muestra además ∇·F y (∇×F)_z calculados con SymPy. Ejemplo: F = (−y, x) da divergencia 0 y rotacional 2 (está en las pruebas).
- Todas usan el mismo recorte por percentiles, así que campos como el de una carga puntual (x/r³, y/r³) se ven bien.

## 3. Verificación

| Comprobación | Resultado |
|---|---|
| CI completo (ruff, pytest 3.12 y 3.13, flutter analyze, flutter test, versiones, APK) en `33650b6` | ✅ [H] |
| Pasos de firma sin secretos: aviso visible y huella del APK impresa | ✅ [H] |
| `ruff check` y `ruff format --check` en local antes de cada commit | ✅ [H] |
| Superficie 3D en la tablet | ✅ [H] (captura del 2026-11-05) |
| Figuras de la Misión 012 en la tablet | ⏳ Pendiente (necesita el APK de esta rama) |
| `python -m app.pair` y el servicio en tu Fedora | ⏳ Pendiente [Hip]: probado solo con pytest en CI |

## 4. Lo que te toca hacer (en este orden)

1. **Aprobar y fusionar** el PR de esta rama (o pedirme cambios).
2. **Actualizar Fedora:**
   ```bash
   cd ~/DESARROLLO/CUADERNO_CIENTIFICO
   git checkout master && git pull origin master
   cd backend && .venv/bin/pip install -e ".[dev]"
   ```
3. **Servicio y emparejamiento** (cierra antes cualquier `uvicorn` abierto con `Ctrl+C`):
   ```bash
   cd ~/DESARROLLO/CUADERNO_CIENTIFICO && tool/install_service.sh
   cd backend && .venv/bin/python -m app.pair --rotar
   systemctl --user restart euler-notes
   .venv/bin/python -m app.pair
   ```
   Escanea el QR con la cámara de la tablet. `--rotar` cambia el token que se compartió en el chat.
4. **Reservar la IP** de tu compu en el router (`docs/CONEXION.md` §4).
5. **Clave de firma** (`docs/SIGNING.md` §0): generarla, **guardar dos copias** y subir los cuatro secretos.
6. **Última desinstalación:** cuando el CI muestre tu huella, desinstala la app una vez e instala ese APK. Desde ahí, todos se instalan encima.
7. **Probar las figuras nuevas** con las plantillas «Curvas de nivel», «Campo vectorial» y «Curva 3D (hélice)».

## 5. Commits

| Commit | Contenido |
|---|---|
| `1fb4c6c`, `a0a18a5`, `7cf93fd` → merge `8168e67` | Misión 008 (PR #3) |
| `ab39fbe` | Misión 010: firma estable |
| `44a2bf4` | Misión 011: emparejamiento y servicio |
| `33650b6` | Misión 012: figuras nuevas |
| `e075957` | Misión 009: documentación, TASKS, ADR 19–20, CHANGELOG |

## 6. Siguiente paso recomendado [P]

Con la firma y la conexión resueltas, la decisión grande es la **Etapa 2: funcionar sin el PC** (ver `AUDIT_REPORT.md` §6 y `ONENOTE_ANALYSIS.md` §5). El primer paso propuesto es un prototipo de un día con Drift en la tablet, para decidir con datos.
