#!/bin/bash
# =============================================================
# stop_mongodb.sh — Arrêt propre de l'infrastructure MongoDB P7
# Projet NosCités | ReplicaSet + Sharding
# =============================================================
# Usage : bash stop_mongodb.sh [replicaset|sharding|all]
#   all         → arrête tout (défaut)
#   replicaset  → arrête uniquement le ReplicaSet noscitesRS
#   sharding    → arrête uniquement le cluster shardé
# =============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MODE=${1:-all}

ok()     { echo -e "  ${GREEN}✅ $1 arrêté${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠  $1 — déjà arrêté ou non disponible${NC}"; }
header() { echo -e "\n${YELLOW}[$1] $2${NC}"; }

# Arrête proprement un nœud MongoDB via la commande shutdown
shutdown_node() {
    local port=$1
    local name=$2
    mongosh --port "$port" --eval "db.adminCommand({shutdown: 1, force: true})" \
        --quiet 2>/dev/null
    sleep 1
    # Vérifie si le processus est bien arrêté
    if ! ss -tlnp 2>/dev/null | grep -q ":$port "; then
        ok "$name (port $port)"
    else
        warn "$name (port $port)"
    fi
}

echo ""
echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   MongoDB NosCités P7 — Arrêt               ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠  L'ordre d'arrêt est important pour éviter les erreurs${NC}"

# ─────────────────────────────────────────────
# ARRÊT CLUSTER SHARDÉ
# Ordre : mongos → shards → cfgRS
# ─────────────────────────────────────────────
stop_sharding() {
    # 1. mongos en premier (routeur)
    header "1/3" "Arrêt mongos (port 27029)"
    shutdown_node 27029 "mongos"
    sleep 2

    # 2. Shards
    header "2/3" "Arrêt des shards"
    shutdown_node 27027 "shardParis"
    shutdown_node 27028 "shardLyon"
    sleep 2

    # 3. Config Server RS en dernier
    header "3/3" "Arrêt du Config Server RS (cfgRS)"
    shutdown_node 27024 "cfgRS nœud 0"
    shutdown_node 27025 "cfgRS nœud 1"
    shutdown_node 27026 "cfgRS nœud 2"
    sleep 2
}

# ─────────────────────────────────────────────
# ARRÊT REPLICASET
# Ordre : SECONDAIRES → ARBITRE → PRIMARY (pour éviter une réélection inutile)
# ─────────────────────────────────────────────
stop_replicaset() {
    header "RS" "Arrêt du ReplicaSet noscitesRS"
    shutdown_node 27019 "SECONDARY 2"
    shutdown_node 27018 "SECONDARY 1"
    shutdown_node 27020 "ARBITRE"
    shutdown_node 27017 "PRIMARY"
    sleep 2
}

# ─────────────────────────────────────────────
# EXÉCUTION SELON LE MODE
# ─────────────────────────────────────────────
case "$MODE" in
    replicaset)
        stop_replicaset
        ;;
    sharding)
        stop_sharding
        ;;
    all|*)
        stop_sharding
        stop_replicaset
        ;;
esac

# ─────────────────────────────────────────────
# VÉRIFICATION FINALE
# ─────────────────────────────────────────────
echo ""
sleep 2
MONGOD=$(pgrep -x mongod 2>/dev/null | wc -l)
MONGOS=$(pgrep -x mongos 2>/dev/null | wc -l)

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Arrêt terminé — Vérification              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ "$MONGOD" -eq 0 ] && [ "$MONGOS" -eq 0 ]; then
    echo -e "  ${GREEN}✅ Aucun processus MongoDB actif — arrêt complet${NC}"
else
    echo -e "  ${YELLOW}⚠  Processus restants : $MONGOD mongod, $MONGOS mongos${NC}"
    echo ""
    echo "  Si des processus persistent, forcer l'arrêt :"
    echo "    kill \$(pgrep -x mongod) 2>/dev/null"
    echo "    kill \$(pgrep -x mongos) 2>/dev/null"
    echo ""
    echo "  Ou vérifier avec : bash status_mongodb.sh"
fi

echo ""
echo "  Pour redémarrer : bash start_mongodb.sh"
echo ""
