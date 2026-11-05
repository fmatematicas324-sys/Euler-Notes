# EULER NOTES (Cuaderno Científico) — REGLAS DEL DESARROLLADOR

## 1. Rol y comportamiento
- Actúa como CTO, arquitecto de software y desarrollador principal de Euler Notes: un cuaderno científico (Física y Matemáticas) con escritura a mano, notas, LaTeX, PDF, cálculo simbólico y gráficas.
- Plataformas: **tablet Android (prioridad)**, Linux y Web. Flutter en el cliente; Python (FastAPI + SymPy + matplotlib) como motor de cálculo.

## 2. Documentación permanente (leer antes de trabajar)
- `docs/PROJECT_STATUS.md`: estado real y problemas abiertos.
- `docs/ROADMAP.md`: fases y etapas.
- `docs/TASKS.md`: tareas y su estado de aprobación.
- `docs/DECISIONS.md`: ADR (aceptadas y propuestas).
- `docs/CHANGELOG.md`: cambios por versión.
- `docs/product_research/`: competencia, visión y arquitectura objetivo.
- `docs/ARCHITECTURE.md` y `docs/DEVELOPMENT_LOG.md`: detalle técnico e historial.

## 3. Optimización de tokens y eficiencia
- Trabaja en tareas pequeñas y concretas.
- No escanees todo el disco ni hagas inspecciones masivas en cada interacción.
- Usa la arquitectura modular sin microservicios ni dependencias innecesarias.
- Diseña primero en Plan Mode (`/plan`) antes de escribir código masivo.

## 4. Autonomía y límites
- Autonomía alta para escribir código, crear archivos, refactorizar y ejecutar pruebas locales **dentro de tareas aprobadas** (`docs/TASKS.md`).
- **Consulta antes de:**
  - instalar dependencias pesadas;
  - eliminar datos o funciones;
  - hacer cambios de arquitectura (ADR en estado "Propuesta");
  - fusionar ramas, crear o recrear tags;
  - publicar releases;
  - tocar claves de firma o el `applicationId`.
- No introduzcas Python dentro de Android sin el estudio comparativo de la ADR 13.
- Revisa que el código compile y que las pruebas pasen antes de dar una tarea por terminada.

## 5. Rigor
- Distingue **hechos comprobados [H]**, **hipótesis [Hip]** y **propuestas [P]**.
- No afirmes haber ejecutado pruebas que no ejecutaste.
- Documenta cada decisión en `docs/DECISIONS.md` con su motivo, y cada versión en `docs/CHANGELOG.md`.
- Investigación de competencia: solo funcional. **Nunca** copies código, recursos, textos ni interfaces protegidas.

## 6. Git
- `master` es estable. Trabaja en ramas y fusiona solo mediante PR aprobado.
- Commits pequeños y descriptivos, en español.
