# Euler Notes — App Flutter

Interfaz de Euler Notes (Cuaderno Científico): tablet Android, Linux y Web.

## Ejecutar
Arranca primero el backend (`backend/`, puerto 8000) y después:

```bash
flutter run -d chrome   # Web
flutter run -d linux    # Escritorio Linux
```

Otra URL de backend: `--dart-define=API_BASE_URL=http://127.0.0.1:9000`.

## Estructura
- `lib/core/`: configuración, cliente HTTP, errores, tema, estado del backend.
- `lib/features/{notebooks,notes,compute}/{data,domain,presentation}`.

## Calidad
```bash
flutter analyze
flutter test
```
