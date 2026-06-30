#!/bin/bash
# =============================================================
# start_mongodb.sh — Démarrage de l'infrastructure MongoDB P7
# Projet NosCités | ReplicaSet + Sharding
# =============================================================
# Usage : bash start_mongodb.sh [replicaset|sharding|all]
#   all         → démarre tout (défaut)
#   replicaset  → démarre uniquement le ReplicaSet noscitesRS
#   sharding    → démarre uniquement le cluster shardé
# =============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE=${1:-all}

ok()     { echo -e "  ${GREEN}✅ $1${NC}"; }
info()   { echo -e "  ${BLUE}ℹ  $1${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠  $1${NC}"; }
header() { echo -e "\n${YELLOW}[$1] $2${NC}"; }

# Vérifie si un port est déjà occupé
port_in_use() {
    ss -tlnp 2>/dev/null | grep -q ":$1 " && return 0
    return 1
}

# Attend qu'un port réponde (max N secondes)
wait_for_port() {
    local port=$1
    local max=$2
    local i=0
    while [ $i -lt $max ]; do
        mongosh --port "$port" --eval "db.adminCommand('ping')" --quiet 2>/dev/null | grep -q "1" && return 0
        sleep 1
        i=$((i+1))
    done
    return 1
}

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   MongoDB NosCités P7 — Démarrage           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

# ─────────────────────────────────────────────
# PARTIE A — REPLICASET noscitesRS (27017-27020)
# ─────────────────────────────────────────────
start_replicaset() {
    header "1/2" "ReplicaSet noscitesRS (ports 27017-27020)"

    for port in 27017 27018 27019 27020; do
        if port_in_use $port; then
            warn "Port $port déjà utilisé — ignoré"
        fi
    done

    mongod --replSet noscitesRS --port 27017 --dbpath ~/mongodb/rs0 \
        --fork --logpath ~/mongodb/rs0/mongod.log --bind_ip_all 2>/dev/null
    mongod --replSet noscitesRS --port 27018 --dbpath ~/mongodb/rs1 \
        --fork --logpath ~/mongodb/rs1/mongod.log --bind_ip_all 2>/dev/null
    mongod --replSet noscitesRS --port 27019 --dbpath ~/mongodb/rs2 \
        --fork --logpath ~/mongodb/rs2/mongod.log --bind_ip_all 2>/dev/null
    mongod --replSet noscitesRS --port 27020 --dbpath ~/mongodb/rs3 \
        --fork --logpath ~/mongodb/rs3/mongod.log --bind_ip_all 2>/dev/null

    info "Attente du PRIMARY noscitesRS (15s max)..."
    if wait_for_port 27017 15; then
        ok "ReplicaSet noscitesRS opérationnel"
        ok "PRIMARY  → localhost:27017"
        ok "SECONDARY1 → localhost:27018"
        ok "SECONDARY2 → localhost:27019"
        ok "ARBITRE  → localhost:27020"
    else
        warn "noscitesRS lent à démarrer — vérifier avec : mongosh --port 27017"
    fi
}

# ─────────────────────────────────────────────
# PARTIE B — CLUSTER SHARDÉ (cfgRS + shards + mongos)
# ─────────────────────────────────────────────
start_sharding() {
    header "2/2" "Cluster Shardé"

    # Config Server RS (DOIT démarrer AVANT mongos)
    echo "  → Config Server RS cfgRS (ports 27024-27026)..."
    mongod --configsvr --replSet cfgRS --port 27024 --dbpath ~/mongodb/cfg0 \
        --fork --logpath ~/mongodb/cfg0/mongod.log --bind_ip_all 2>/dev/null
    mongod --configsvr --replSet cfgRS --port 27025 --dbpath ~/mongodb/cfg1 \
        --fork --logpath ~/mongodb/cfg1/mongod.log --bind_ip_all 2>/dev/null
    mongod --configsvr --replSet cfgRS --port 27026 --dbpath ~/mongodb/cfg2 \
        --fork --logpath ~/mongodb/cfg2/mongod.log --bind_ip_all 2>/dev/null

    # Attente élection PRIMARY cfgRS — CRITIQUE avant de lancer mongos
    info "Attente élection PRIMARY cfgRS (15s max)..."
    if wait_for_port 27024 15; then
        ok "cfgRS PRIMARY élu sur port 27024"
    else
        warn "cfgRS lent — attente supplémentaire 5s..."
        sleep 5
    fi

    # Shards (peuvent démarrer en parallèle de cfgRS)
    echo "  → Shards (ports 27027-27028)..."
    mongod --shardsvr --replSet shardParis --port 27027 --dbpath ~/mongodb/shard_paris \
        --fork --logpath ~/mongodb/shard_paris/mongod.log --bind_ip_all 2>/dev/null
    mongod --shardsvr --replSet shardLyon  --port 27028 --dbpath ~/mongodb/shard_lyon \
        --fork --logpath ~/mongodb/shard_lyon/mongod.log --bind_ip_all 2>/dev/null

    sleep 3

    # mongos — UNIQUEMENT après initialisation cfgRS
    echo "  → Routeur mongos (port 27029)..."
    mongos --configdb cfgRS/localhost:27024,localhost:27025,localhost:27026 \
        --port 27029 \
        --fork \
        --logpath ~/mongodb/mongos.log \
        --bind_ip_all 2>/dev/null

    info "Attente du routeur mongos (10s max)..."
    if wait_for_port 27029 10; then
        ok "Cluster shardé opérationnel"
        ok "cfgRS     → localhost:27024-27026"
        ok "shardParis → localhost:27027"
        ok "shardLyon  → localhost:27028"
        ok "mongos    → localhost:27029"
    else
        warn "mongos lent à démarrer — vérifier avec : mongosh --port 27029"
    fi
}

# ─────────────────────────────────────────────
# EXÉCUTION SELON LE MODE
# ─────────────────────────────────────────────
case "$MODE" in
    replicaset)
        start_replicaset
        ;;
    sharding)
        start_sharding
        ;;
    all|*)
        start_replicaset
        start_sharding
        ;;
esac

# ─────────────────────────────────────────────
# RÉSUMÉ FINAL
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Démarrage terminé — Récapitulatif                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Connexion ReplicaSet  : mongosh --port 27017"
echo "  Connexion Sharding    : mongosh --port 27029"
echo ""
echo "  Commandes utiles :"
echo "    Vérifier RS    : mongosh --port 27017 --eval 'rs.status()'"
echo "    Vérifier Shard : mongosh --port 27029 --eval 'sh.status()'"
echo "    Distribution   : mongosh --port 27029 --eval 'use(\"noscites\"); db.listings.getShardDistribution()'"
echo ""
echo "  Pour arrêter : bash stop_mongodb.sh"
echo ""
