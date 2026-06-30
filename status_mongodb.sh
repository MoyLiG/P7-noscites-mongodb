#!/bin/bash
# =============================================================
# status_mongodb.sh — État de l'infrastructure MongoDB P7
# Projet NosCités | ReplicaSet + Sharding
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

up=0
down=0

check_port() {
    local port=$1
    local name=$2
    local role=$3
    if mongosh --port "$port" --eval "db.adminCommand('ping')" \
        --quiet 2>/dev/null | grep -q "1"; then
        echo -e "  ${GREEN}✅ UP${NC}   $name  (port $port)  — $role"
        up=$((up+1))
    else
        echo -e "  ${RED}❌ DOWN${NC} $name  (port $port)  — $role"
        down=$((down+1))
    fi
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MongoDB NosCités P7 — Statut des services         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

echo ""
echo -e "${YELLOW}── ReplicaSet noscitesRS ──────────────────────────────${NC}"
check_port 27017 "rs0" "PRIMARY    (priorité 2)"
check_port 27018 "rs1" "SECONDARY 1"
check_port 27019 "rs2" "SECONDARY 2"
check_port 27020 "rs3" "ARBITRE    (vote seul)"

echo ""
echo -e "${YELLOW}── Config Server RS (cfgRS) ───────────────────────────${NC}"
check_port 27024 "cfg0" "cfgRS nœud 0 — PRIMARY"
check_port 27025 "cfg1" "cfgRS nœud 1"
check_port 27026 "cfg2" "cfgRS nœud 2"

echo ""
echo -e "${YELLOW}── Shards ─────────────────────────────────────────────${NC}"
check_port 27027 "shardParis" "zone PARIS  — 95 885 docs"
check_port 27028 "shardLyon " "zone LYON   —  9 973 docs"

echo ""
echo -e "${YELLOW}── Routeur ────────────────────────────────────────────${NC}"
check_port 27029 "mongos    " "Point d'entrée sharding"

echo ""
echo -e "${BLUE}── Résumé ─────────────────────────────────────────────${NC}"
total=$((up+down))
echo -e "  Services actifs  : ${GREEN}$up / $total${NC}"
if [ "$down" -gt 0 ]; then
    echo -e "  Services inactifs: ${RED}$down / $total${NC}"
    echo ""
    echo "  Pour démarrer les services manquants :"
    echo "    bash start_mongodb.sh"
fi

# Affiche le nombre de processus MongoDB réels
PROC=$(pgrep -x mongod 2>/dev/null | wc -l)
MONG=$(pgrep -x mongos 2>/dev/null | wc -l)
echo ""
echo -e "  Processus système : ${BLUE}$PROC mongod + $MONG mongos${NC}"
echo ""
