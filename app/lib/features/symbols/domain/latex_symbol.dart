import 'package:flutter/foundation.dart';

/// Símbolo o plantilla LaTeX del teclado científico.
@immutable
class LatexSymbol {
  const LatexSymbol(
    this.name,
    this.label, [
    String? snippet,
    this.display = false,
  ]) : snippet = snippet ?? label;

  /// Marca la posición del cursor tras insertar (y dónde va la selección).
  static const caret = '‸';

  /// Nombre para la ayuda contextual (tooltip).
  final String name;

  /// LaTeX que se dibuja en el botón.
  final String label;

  /// LaTeX que se inserta; puede contener [caret].
  final String snippet;

  /// Si es `true`, fuera de una fórmula se inserta como bloque `$$...$$`.
  final bool display;
}

class SymbolCategory {
  const SymbolCategory(this.name, this.symbols);

  final String name;
  final List<LatexSymbol> symbols;
}

const _c = LatexSymbol.caret;

/// Catálogo del teclado científico.
const symbolCatalog = <SymbolCategory>[
  SymbolCategory('Cálculo', [
    LatexSymbol('Derivada parcial', r'\partial'),
    LatexSymbol(
      'Derivada parcial de f',
      r'\frac{\partial f}{\partial x}',
      '\\frac{\\partial $_c}{\\partial x}',
    ),
    LatexSymbol(
      'Segunda derivada parcial',
      r'\frac{\partial^2 f}{\partial x^2}',
      '\\frac{\\partial^2 $_c}{\\partial x^2}',
    ),
    LatexSymbol(
      'Derivada cruzada',
      r'\frac{\partial^2 f}{\partial x \partial y}',
      '\\frac{\\partial^2 $_c}{\\partial x \\partial y}',
    ),
    LatexSymbol('Derivada', r'\frac{df}{dx}', '\\frac{d$_c}{dx}'),
    LatexSymbol('Operador derivada', r'\frac{d}{dx}', '\\frac{d}{dx}$_c'),
    LatexSymbol('Integral', r'\int f\,dx', '\\int $_c \\, dx'),
    LatexSymbol(
      'Integral definida',
      r'\int_a^b f\,dx',
      '\\int_{a}^{b} $_c \\, dx',
    ),
    LatexSymbol('Integral doble', r'\iint_D f\,dA', '\\iint_{D} $_c \\, dA'),
    LatexSymbol('Integral triple', r'\iiint_V f\,dV', '\\iiint_{V} $_c \\, dV'),
    LatexSymbol(
      'Integral de línea cerrada',
      r'\oint_C \vec{F}\cdot d\vec{r}',
      '\\oint_{C} $_c \\cdot d\\vec{r}',
    ),
    LatexSymbol('Límite', r'\lim_{x \to a}', '\\lim_{x \\to $_c}'),
    LatexSymbol(
      'Sumatoria',
      r'\sum_{n=1}^{\infty}',
      '\\sum_{n=1}^{\\infty} $_c',
    ),
    LatexSymbol('Productorio', r'\prod_{i=1}^{n}', '\\prod_{i=1}^{n} $_c'),
    LatexSymbol('Infinito', r'\infty'),
    LatexSymbol('Fracción', r'\frac{a}{b}', '\\frac{$_c}{}'),
    LatexSymbol('Raíz cuadrada', r'\sqrt{x}', '\\sqrt{$_c}'),
    LatexSymbol('Raíz n-ésima', r'\sqrt[n]{x}', '\\sqrt[n]{$_c}'),
    LatexSymbol('Potencia', r'x^{n}', '^{$_c}'),
    LatexSymbol('Subíndice', r'x_{i}', '_{$_c}'),
  ]),
  SymbolCategory('Vectores', [
    LatexSymbol('Nabla', r'\nabla'),
    LatexSymbol('Gradiente', r'\nabla f', '\\nabla $_c'),
    LatexSymbol(
      'Divergencia',
      r'\nabla \cdot \vec{F}',
      '\\nabla \\cdot \\vec{$_c}',
    ),
    LatexSymbol(
      'Rotacional',
      r'\nabla \times \vec{F}',
      '\\nabla \\times \\vec{$_c}',
    ),
    LatexSymbol('Laplaciano', r'\nabla^2 f', '\\nabla^2 $_c'),
    LatexSymbol('Vector', r'\vec{v}', '\\vec{$_c}'),
    LatexSymbol('Vector unitario', r'\hat{n}', '\\hat{$_c}'),
    LatexSymbol('Norma', r'\|\vec{v}\|', '\\|$_c\\|'),
    LatexSymbol('Producto escalar', r'\vec{a} \cdot \vec{b}'),
    LatexSymbol('Producto vectorial', r'\vec{a} \times \vec{b}'),
    LatexSymbol('Punto', r'\cdot'),
    LatexSymbol('Por', r'\times'),
    LatexSymbol('Diferencial de posición', r'd\vec{r}'),
  ]),
  SymbolCategory('Matrices', [
    LatexSymbol(
      'Matriz 2×2',
      r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
      '\\begin{pmatrix} $_c & b \\\\ c & d \\end{pmatrix}',
      true,
    ),
    LatexSymbol(
      'Matriz 3×3',
      r'\begin{bmatrix} a & b & c \\ d & e & f \\ g & h & i \end{bmatrix}',
      '\\begin{bmatrix} $_c & b & c \\\\ d & e & f \\\\ g & h & i \\end{bmatrix}',
      true,
    ),
    LatexSymbol(
      'Determinante 2×2',
      r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}',
      '\\begin{vmatrix} $_c & b \\\\ c & d \\end{vmatrix}',
      true,
    ),
    LatexSymbol(
      'Identidad 3×3',
      r'\begin{pmatrix} 1 & 0 & 0 \\ 0 & 1 & 0 \\ 0 & 0 & 1 \end{pmatrix}',
      null,
      true,
    ),
    LatexSymbol(
      'Vector columna',
      r'\begin{pmatrix} x \\ y \\ z \end{pmatrix}',
      '\\begin{pmatrix} $_c \\\\ y \\\\ z \\end{pmatrix}',
      true,
    ),
    LatexSymbol(
      'Sistema de ecuaciones',
      r'\begin{cases} x + y = 1 \\ x - y = 0 \end{cases}',
      '\\begin{cases} $_c \\\\  \\end{cases}',
      true,
    ),
    LatexSymbol('Transpuesta', r'A^{T}', '^{T}'),
    LatexSymbol('Inversa', r'A^{-1}', '^{-1}'),
    LatexSymbol('Determinante', r'\det(A)', '\\det($_c)'),
  ]),
  SymbolCategory('Griegas', [
    LatexSymbol('alfa', r'\alpha'),
    LatexSymbol('beta', r'\beta'),
    LatexSymbol('gamma', r'\gamma'),
    LatexSymbol('delta', r'\delta'),
    LatexSymbol('épsilon', r'\varepsilon'),
    LatexSymbol('theta', r'\theta'),
    LatexSymbol('lambda', r'\lambda'),
    LatexSymbol('mu', r'\mu'),
    LatexSymbol('nu', r'\nu'),
    LatexSymbol('pi', r'\pi'),
    LatexSymbol('rho', r'\rho'),
    LatexSymbol('sigma', r'\sigma'),
    LatexSymbol('tau', r'\tau'),
    LatexSymbol('phi', r'\varphi'),
    LatexSymbol('psi', r'\psi'),
    LatexSymbol('omega', r'\omega'),
    LatexSymbol('Gamma', r'\Gamma'),
    LatexSymbol('Delta', r'\Delta'),
    LatexSymbol('Theta', r'\Theta'),
    LatexSymbol('Lambda', r'\Lambda'),
    LatexSymbol('Sigma', r'\Sigma'),
    LatexSymbol('Phi', r'\Phi'),
    LatexSymbol('Psi', r'\Psi'),
    LatexSymbol('Omega', r'\Omega'),
  ]),
  SymbolCategory('Relaciones', [
    LatexSymbol('Menor o igual', r'\leq'),
    LatexSymbol('Mayor o igual', r'\geq'),
    LatexSymbol('Distinto', r'\neq'),
    LatexSymbol('Aproximadamente', r'\approx'),
    LatexSymbol('Equivalente', r'\equiv'),
    LatexSymbol('Proporcional', r'\propto'),
    LatexSymbol('Más menos', r'\pm'),
    LatexSymbol('Tiende a', r'\to'),
    LatexSymbol('Implica', r'\Rightarrow'),
    LatexSymbol('Si y solo si', r'\Leftrightarrow'),
    LatexSymbol('Pertenece', r'\in'),
    LatexSymbol('Subconjunto', r'\subseteq'),
    LatexSymbol('Unión', r'\cup'),
    LatexSymbol('Intersección', r'\cap'),
    LatexSymbol('Para todo', r'\forall'),
    LatexSymbol('Existe', r'\exists'),
    LatexSymbol('Vacío', r'\emptyset'),
    LatexSymbol('Reales', r'\mathbb{R}'),
    LatexSymbol('Complejos', r'\mathbb{C}'),
  ]),
  SymbolCategory('Física', [
    LatexSymbol('h barra', r'\hbar'),
    LatexSymbol('Grados', r'^{\circ}'),
    LatexSymbol('Segunda ley de Newton', r'\vec{F} = m\vec{a}'),
    LatexSymbol('Energía en reposo', r'E = mc^2'),
    LatexSymbol('Ket', r'|\psi\rangle', '|$_c\\rangle'),
    LatexSymbol('Bra', r'\langle\psi|', '\\langle $_c|'),
    LatexSymbol('Valor esperado', r'\langle \psi | \hat{H} | \psi \rangle'),
    LatexSymbol(
      'Ecuación de Schrödinger',
      r'i\hbar \frac{\partial \psi}{\partial t} = \hat{H}\psi',
    ),
    LatexSymbol(
      'Ley de Gauss',
      r'\nabla \cdot \vec{E} = \frac{\rho}{\varepsilon_0}',
    ),
    LatexSymbol(
      'Ecuación de onda',
      r'\frac{\partial^2 u}{\partial t^2} = c^2 \nabla^2 u',
    ),
    LatexSymbol('Unidades', r'\,\mathrm{m/s^2}', '\\,\\mathrm{$_c}'),
  ]),
];
