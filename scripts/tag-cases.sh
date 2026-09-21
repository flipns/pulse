#!/usr/bin/env bash
# Crea las etiquetas capN-bug / capN-fix que cita el libro.
# Uso: scripts/tag-cases.sh 3
# La variante bug es el mismo código compilado con -DPULSE_BUG; la etiqueta apunta a un commit
# que activa ese flag en Package.swift para que `swift test` en ese commit reproduzca el fallo.
set -euo pipefail
N="${1:?número de capítulo}"
git tag -f "cap${N}-fix" HEAD
git checkout -q -b "tmp/cap${N}-bug"
grep -q "// PULSE_BUG_FLAG" Package.swift || {
  echo "ERROR: falta el marcador // PULSE_BUG_FLAG en Package.swift."
  echo "Sin él, la etiqueta cap${N}-bug compilaría la variante correcta."
  git checkout -q -; git branch -qD "tmp/cap${N}-bug"; exit 1
}
sed -i "" "s|// PULSE_BUG_FLAG|.define(\"PULSE_BUG\"),|" Package.swift
git commit -qam "cap${N}: variante bug (PULSE_BUG activo)"
git tag -f "cap${N}-bug" HEAD
git checkout -q -
git branch -qD "tmp/cap${N}-bug"
echo "Etiquetas cap${N}-bug y cap${N}-fix creadas."
