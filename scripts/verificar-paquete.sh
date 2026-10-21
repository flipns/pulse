#!/usr/bin/env bash
# Comprueba que el repositorio y el manuscrito cuentan la misma historia.
# Verifica CONTENIDO, no la forma de escribirlo: si mañana el CI se reescribe de otra manera
# pero sigue exigiendo las seis suites y sus causas, este script debe seguir dando verde.
set -uo pipefail
fallo=0
d() { echo "❌ $1"; fallo=1; }

CI=.github/workflows/ci.yml
LIBRO=docs/libro

# --- Manuscrito
ESPERADAS_APENDICE=58
reales=$(grep -c '^- \*\*' "$LIBRO/Apéndice_A_Antipatrones.md" 2>/dev/null || echo 0)
[ "$reales" = "$ESPERADAS_APENDICE" ] || d "El apéndice tiene $reales entradas y deberían ser $ESPERADAS_APENDICE (¿copia vieja en $LIBRO?)"
grep -q "Seis de ellos" "$LIBRO/Capítulo_01.md" 2>/dev/null || d "El capítulo 1 de $LIBRO no es la versión con seis casos"
if grep -rqF "cuatro llamadas por pase" "$LIBRO" Tests Sources 2>/dev/null; then
  d "Queda la cifra retirada de §7.9 en: $(grep -rlF 'cuatro llamadas por pase' "$LIBRO" Tests Sources | tr '\n' ' ')"
fi

# --- CI: las seis suites, por nombre
for suite in \
  "Identidad en ForEach" \
  "Ownership del modelo de checkout" \
  "FeatureFlags en el entorno" \
  "Mediciones del FlowLayout" \
  "FeedModel" \
  "Orden de respuestas de búsqueda"
do
  grep -qF "$suite" "$CI" || d "El CI no menciona la suite: $suite"
done

# --- CI: las seis huellas de causa (el criterio del libro no es el color del test)
for causa in 'A→Promoción' 'RegistroCheckout.enUso == primero' 'SIGTRAP' 'mide en cada llamada' 'notificado → true' 'resultados = \["q-za"\]'
do
  grep -qF "$(printf '%b' "${causa//\\/}")" "$CI" 2>/dev/null || grep -qF "$causa" "$CI" || d "El CI no comprueba la causa: $causa"
done

grep -q "runs-on: xcode-27\|runs-on: macos-26" "$CI" || d "El CI no usa un runner con macOS 26 (el paquete exige .macOS(.v26))"

# El CI ha llegado incompleto varias veces porque `.github` es una carpeta oculta y no se copia
# desde el Finder. Se comprueba cada job que la documentación afirma que existe.
for job in entorno fix estabilidad bug; do
  grep -qE "^  $job:$" "$CI" || d "Al CI le falta el job '$job' (¿se copió .github desde el Finder?)"
done

# --- Evidencia: nombres fijos, y cada log citado existe
for f in docs/evidencia/test-fix.log docs/evidencia/test-bug.log; do
  [ -f "$f" ] || d "Falta la evidencia vigente: $f"
done
numerados=$(grep -rnoE "test-(fix|bug)[0-9]+\.log|build[0-9]+\.log" README.md docs/VERIFICACIONES.md Package.swift .github Sources Tests docs/libro 2>/dev/null || true)
[ -z "$numerados" ] || d "Se citan logs numerados (deben citarse test-fix.log / test-bug.log): $numerados"
for citado in $(grep -rhoE "docs/evidencia/[A-Za-z0-9_./-]+\.log" README.md docs/VERIFICACIONES.md 2>/dev/null | sort -u); do
  [ -f "$citado" ] || d "Se cita un log que no existe: $citado"
done
[ -f docs/evidencia/test-fix.log ] && ! grep -q "Test run with .* passed" docs/evidencia/test-fix.log && d "test-fix.log no termina en verde"

# --- Repositorios anidados: git archive no incluye su contenido
if git rev-parse --git-dir >/dev/null 2>&1; then
  anidados=$(git ls-files -s | awk '$1 == "160000" {print $4}')
  [ -z "$anidados" ] || d "Hay repositorios anidados que no entrarán en el paquete: $anidados"
fi

# --- Paquete
grep -q "// PULSE_BUG_FLAG" Package.swift || d "Falta el marcador PULSE_BUG_FLAG en Package.swift"
grep -q 'exact:' Package.swift || d "Las dependencias no están fijadas a versión exacta"
[ -f Package.resolved ] || d "Falta Package.resolved"
if git rev-parse --git-dir >/dev/null 2>&1; then
  git diff --quiet && git diff --cached --quiet || d "Hay cambios sin commitear"
else
  echo "ℹ️  No es un repositorio git: me salto la comprobación de commits"
fi

[ $fallo -eq 0 ] && echo "✅ Paquete coherente" || echo "Revisa lo anterior antes de etiquetar"
exit $fallo
