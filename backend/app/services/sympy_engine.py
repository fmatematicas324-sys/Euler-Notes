"""Motor de cálculo simbólico seguro sobre SymPy.

Nunca se usa `eval`/`sympify` sobre texto sin filtrar. Defensa en capas:
1. Lista blanca de caracteres (sin comillas, corchetes, `_`, `;`, ...).
2. Puntos solo como separador decimal (bloquea acceso a atributos).
3. Identificadores: ni palabras clave de Python ni nombres demasiado largos.
4. `parse_expr` con un `global_dict` mínimo y `__builtins__` vacío.
El aislamiento por tiempo y memoria lo añade `app.services.compute`.
"""

import keyword
import re
from dataclasses import dataclass

import sympy as sp
from sympy.parsing.sympy_parser import (
    convert_xor,
    implicit_multiplication,
    parse_expr,
    standard_transformations,
)

MAX_EXPR_LENGTH = 500
MAX_IDENTIFIER_LENGTH = 20
OPERATIONS = ("simplify", "diff", "integrate", "solve")

_ALLOWED_CHARS = re.compile(r"^[A-Za-z0-9+\-*/^().,=\s]*$")
_DECIMAL_POINT = re.compile(r"\d\.\d")
_IDENTIFIER = re.compile(r"[A-Za-z][A-Za-z0-9]*")
_TRANSFORMATIONS = (*standard_transformations, implicit_multiplication, convert_xor)

_FUNCTION_NAMES = (
    "sin", "cos", "tan", "cot", "sec", "csc",
    "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
    "exp", "log", "sqrt", "Abs", "factorial", "floor", "ceiling", "Min", "Max", "gamma",
)  # fmt: skip
_SAFE_GLOBALS: dict[str, object] = {
    **{name: getattr(sp, name) for name in _FUNCTION_NAMES},
    "ln": sp.log,
    "pi": sp.pi,
    "E": sp.E,
    "I": sp.I,
    "oo": sp.oo,
    # Nombres que generan las transformaciones de parse_expr.
    "Integer": sp.Integer,
    "Float": sp.Float,
    "Rational": sp.Rational,
    "Symbol": sp.Symbol,
    "Function": sp.Function,
}
_RESERVED = {"True", "False", "None"}


class ExpressionError(ValueError):
    """La expresión no es válida o no está permitida (error del usuario)."""


@dataclass(frozen=True)
class ComputeResult:
    latex: str
    text: str


def validate(expr: str, op: str) -> None:
    """Comprueba la expresión sin interpretarla. Lanza ExpressionError si no es segura."""
    if op not in OPERATIONS:
        raise ExpressionError(f"Operación no soportada: {op}")
    if not expr.strip():
        raise ExpressionError("La expresión está vacía")
    if len(expr) > MAX_EXPR_LENGTH:
        raise ExpressionError(f"La expresión supera {MAX_EXPR_LENGTH} caracteres")
    if not _ALLOWED_CHARS.match(expr):
        raise ExpressionError("La expresión contiene caracteres no permitidos")
    if "." in _DECIMAL_POINT.sub("0", expr):
        raise ExpressionError("El punto solo se admite como separador decimal (p. ej. 2.5)")
    for name in _IDENTIFIER.findall(expr):
        if keyword.iskeyword(name) or name in _RESERVED:
            raise ExpressionError(f"Nombre no permitido: {name}")
        if len(name) > MAX_IDENTIFIER_LENGTH:
            raise ExpressionError(f"Nombre demasiado largo: {name[:MAX_IDENTIFIER_LENGTH]}…")
    equals = expr.count("=")
    if equals and op != "solve":
        raise ExpressionError("El signo '=' solo se admite en la operación solve")
    if equals > 1:
        raise ExpressionError("Una ecuación solo puede tener un signo '='")


def _parse(text: str) -> sp.Basic:
    global_dict = {"__builtins__": {}, **_SAFE_GLOBALS}
    try:
        parsed = parse_expr(
            text, local_dict={}, global_dict=global_dict, transformations=_TRANSFORMATIONS
        )
    except (SyntaxError, TypeError, ValueError, AttributeError, sp.SympifyError) as exc:
        raise ExpressionError("No se pudo interpretar la expresión") from exc
    except Exception as exc:  # tokenize.TokenError y otros errores del parser
        raise ExpressionError("No se pudo interpretar la expresión") from exc
    if not isinstance(parsed, sp.Basic):
        raise ExpressionError("La expresión debe ser un único valor matemático")
    return parsed


def evaluate(expr: str, op: str, var: str = "x") -> ComputeResult:
    """Valida, interpreta y calcula. Puede tardar: ejecutar con límite de tiempo."""
    validate(expr, op)
    symbol = sp.Symbol(var)

    if op == "solve":
        lhs, _, rhs = expr.partition("=")
        target = _parse(lhs) - _parse(rhs) if rhs.strip() else _parse(lhs)
        result: object = sp.solve(target, symbol)
    else:
        parsed = _parse(expr)
        if op == "simplify":
            result = sp.simplify(parsed)
        elif op == "diff":
            result = sp.diff(parsed, symbol)
        else:
            result = sp.integrate(parsed, symbol)

    return ComputeResult(latex=sp.latex(result), text=sp.sstr(result))
