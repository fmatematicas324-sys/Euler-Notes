"""Módulo que precarga el forkserver de `sandbox`: importa todo lo que usan las
tareas aisladas y deja matplotlib listo. No importarlo desde el servidor."""

from app.services import compute  # noqa: F401  (SymPy, numpy, matplotlib)
from app.services.plotting import warm_up

warm_up()
