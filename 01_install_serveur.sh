#!/usr/bin/env bash
# 01_install_serveur.sh : installe PostgreSQL, règle les logs, pg_hba et le pare-feu
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Erreur : lance ce script avec sudo." >&2
  exit 1
fi

PGVER=18
CONF=/etc/postgresql/$PGVER/main
LAN=192.168.100.0/24
VM_IP=192.168.100.10

echo "[1/5] Installation des paquets..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-client ufw

echo "[2/5] Réglages PostgreSQL..."
cat > "$CONF/conf.d/99-novabank.conf" <<EOF
listen_addresses = 'localhost,$VM_IP'
password_encryption = 'scram-sha-256'
log_connections = on
log_disconnections = on
log_statement = 'ddl'
EOF

echo "[3/5] pg_hba.conf..."
[[ -f "$CONF/pg_hba.conf.orig" ]] || cp "$CONF/pg_hba.conf" "$CONF/pg_hba.conf.orig"
cat > "$CONF/pg_hba.conf" <<EOF
# TYPE  DATABASE  USER                                      ADDRESS        METHOD
# (1) administrateur local : par le fichier-socket
local   all       postgres                                                 peer
# (2) propriétaire et appli : depuis la VM seulement
local   bankdb    bank_owner,bank_app                                      scram-sha-256
host    bankdb    bank_owner,bank_app                       127.0.0.1/32   scram-sha-256
# (3) analystes, support, auditeurs : depuis le réseau d'administration
host    bankdb    +grp_analyste,+grp_support,+grp_auditeur  $LAN           scram-sha-256
# (4) tout le reste est refusé
host    all       all                                       0.0.0.0/0      reject
EOF

echo "[4/5] Pare-feu..."
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$LAN" to any port 22 proto tcp
ufw allow from "$LAN" to any port 5432 proto tcp
ufw --force enable

echo "[5/5] Redémarrage de PostgreSQL..."
systemctl restart postgresql
pg_lsclusters
echo "Terminé."
