#!/usr/bin/env bash
# sauvegarde.sh : sauvegarde bankdb, la restaure dans une base temporaire, compare les comptages
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Erreur : lance ce script avec sudo." >&2; exit 1; fi

DIR=/var/backups/novabank
DUMP="$DIR/bankdb_$(date +%Y%m%d_%H%M%S).dump"
TMPDB=bankdb_restore_test
PG="sudo -u postgres"
install -d -o postgres -g postgres "$DIR"

echo "[1/4] Sauvegarde (format custom)..."
$PG pg_dump -Fc -d bankdb -f "$DUMP"
ls -lh "$DUMP"

echo "[2/4] Restauration dans une base temporaire..."
$PG dropdb --if-exists "$TMPDB"
$PG createdb "$TMPDB"
$PG pg_restore -d "$TMPDB" "$DUMP"

echo "[3/4] Comparaison des comptages..."
ok=1
for t in core.customers core.accounts core.transfers core.transactions core.fraud_alerts audit.audit_log; do
  a=$($PG psql -X -At -d bankdb -c "SELECT count(*) FROM $t")
  b=$($PG psql -X -At -d "$TMPDB" -c "SELECT count(*) FROM $t")
  if [[ "$a" == "$b" ]]; then s="OK"; else s="DIFFERENT"; ok=0; fi
  printf '%-20s original=%-8s restauré=%-8s %s\n' "$t" "$a" "$b" "$s"
done

echo "[4/4] Nettoyage..."
$PG dropdb "$TMPDB"
[[ $ok -eq 1 ]] && echo "Sauvegarde vérifiée." || { echo "ERREUR : comptages différents" >&2; exit 1; }
