#!/usr/bin/env bash
# refaire_tout.sh : supprime puis reconstruit tout le projet NovaBank
# Usage : sudo bash refaire_tout.sh   (PostgreSQL doit déjà être installé : 01_install_serveur.sh)
set -euo pipefail
export LC_ALL=C

if [[ $EUID -ne 0 ]]; then
  echo "Erreur : lance ce script avec sudo." >&2
  exit 1
fi
cd "$(dirname "$0")"
PSQL="sudo -u postgres psql -X -v ON_ERROR_STOP=1"

echo "ATTENTION : la base bankdb et les rôles du projet vont être SUPPRIMÉS."
read -rp "Tape OUI pour continuer : " reponse
[[ "$reponse" == "OUI" ]] || { echo "Annulé."; exit 1; }

echo "[1/4] Suppression de la base et des rôles..."
$PSQL -d postgres -c "DROP DATABASE IF EXISTS bankdb WITH (FORCE);"
for r in analyste_1 support_1 auditeur_1 bank_app grp_analyste grp_support grp_auditeur bank_owner; do
  $PSQL -d postgres -c "DROP ROLE IF EXISTS $r;"
done

echo "[2/4] Rejeu des fichiers SQL dans l'ordre de leurs numéros..."
shopt -s nullglob
for f in [0-8][0-9]*.sql; do
  echo "  -> $f"
  # 00_ crée les rôles et la base (postgres) ; les autres tournent dans bankdb (SET ROLE bank_owner à l'intérieur)
  if [[ "$f" == 00_* ]]; then db=postgres; else db=bankdb; fi
  $PSQL -d "$db" < "$f"
done

echo "[3/4] Mots de passe des comptes (tapés ici, jamais stockés dans Git)..."
for r in bank_owner bank_app analyste_1 support_1 auditeur_1; do
    until sudo -u postgres psql -X -d postgres -c "\password $r"; do
    echo "Les mots de passe diffèrent, recommence."
  done
done

echo "[4/4] Tests (les sorties sont gardées dans des fichiers .log)..."
sudo -u postgres psql -X -d bankdb < 91_tests_base.sql 2>&1 | tee tests_base.log
sudo -u postgres psql -X -d bankdb < 90_tests.sql      2>&1 | tee tests_E6_E7.log
echo "Terminé."
