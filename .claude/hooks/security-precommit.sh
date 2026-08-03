#!/usr/bin/env bash
# .claude/hooks/security-precommit.sh
#
# Hook PreToolUse (matcher Bash) : quand Claude Code s'apprête à lancer un
# `git commit` dont le diff indexé touche du code sensible (modèles, controllers,
# policies, migrations), on exécute le garde-fou déterministe `bin/pii-guard` et
# on rappelle l'existence de l'agent d'audit.
#
# Ce que ce hook NE fait PAS : lancer l'agent security-rgpd-expert. Un hook ne
# peut pas invoquer un agent — il exécute un contrôle et affiche un message.
# L'audit approfondi reste une invocation manuelle de l'agent.
#
# Contrat de sortie attendu par Claude Code :
#   exit 0 → la commande passe (stdout est affiché en contexte)
#   exit 2 → la commande est bloquée, stderr est renvoyé à Claude

set -uo pipefail

# Le payload JSON de l'appel d'outil arrive sur stdin.
payload="$(cat)"

# On ne s'intéresse qu'aux `git commit`. Pas de dépendance à jq : grep suffit.
if ! grep -q 'git commit' <<<"$payload"; then
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo_root" || exit 0

# Fichiers indexés (à défaut, rien à contrôler).
staged="$(git diff --cached --name-only 2>/dev/null)"
[ -z "$staged" ] && exit 0

if ! grep -qE '^(app/models/|app/controllers/|app/policies/|db/migrate/|db/schema\.rb)' <<<"$staged"; then
  exit 0
fi

if [ ! -x bin/pii-guard ]; then
  exit 0
fi

if output="$(bin/pii-guard 2>&1)"; then
  echo "🔐 pii-guard OK. Ce commit touche du code sensible (modèles / controllers / policies / migrations)."
  echo "   Pour un audit approfondi : lancer l'agent security-rgpd-expert."
  exit 0
else
  {
    echo "🔐 bin/pii-guard a échoué — commit interrompu."
    echo
    echo "$output"
    echo
    echo "Corrige le problème (voir docs/SECURITE-RGPD.md) avant de committer."
  } >&2
  exit 2
fi
