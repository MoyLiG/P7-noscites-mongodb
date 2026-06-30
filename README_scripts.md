# Scripts de gestion MongoDB — Projet NosCités P7

> Ces scripts gèrent l'intégralité de l'infrastructure MongoDB locale (WSL2).
> Ils sont conçus pour être utilisés après chaque redémarrage du PC.

---

## Architecture gérée

```
┌──────────────────────────────────────────────────────────┐
│  ReplicaSet noscitesRS                                   │
│  rs0 :27017 (PRIMARY) | rs1 :27018 | rs2 :27019 | rs3 :27020 (ARBITRE)
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  Cluster Shardé                                          │
│                                                          │
│  cfgRS (Config Server RS)                                │
│  cfg0 :27024 | cfg1 :27025 | cfg2 :27026                │
│                                                          │
│  mongos :27029 (routeur)                                 │
│  ├── shardParis :27027  →  95 885 docs Paris (90,78%)   │
│  └── shardLyon  :27028  →   9 973 docs Lyon  ( 9,21%)   │
└──────────────────────────────────────────────────────────┘
```

---

## Scripts disponibles

| Script | Rôle |
|--------|------|
| `start_mongodb.sh` | Démarre tous les services dans le bon ordre |
| `stop_mongodb.sh` | Arrête tous les services proprement |
| `status_mongodb.sh` | Vérifie l'état de chaque service |

---

## Utilisation rapide

### Après un redémarrage du PC

```bash
# 1. Ouvrir WSL2 et se placer dans le dossier P7
cd /mnt/c/Users/moymo/OC/P7

# 2. Démarrer tous les services
bash start_mongodb.sh

# 3. Vérifier que tout est UP
bash status_mongodb.sh
```

### Avant d'éteindre le PC

```bash
bash stop_mongodb.sh
```

### Vérifier l'état sans rien changer

```bash
bash status_mongodb.sh
```

---

## Options avancées

Chaque script accepte un argument pour cibler un sous-ensemble :

```bash
# Démarrer uniquement le ReplicaSet
bash start_mongodb.sh replicaset

# Démarrer uniquement le cluster shardé
bash start_mongodb.sh sharding

# Arrêter uniquement le cluster shardé
bash stop_mongodb.sh sharding

# Arrêter uniquement le ReplicaSet
bash stop_mongodb.sh replicaset
```

---

## Ordre de démarrage (critique)

> ⚠️ L'ordre est imposé par MongoDB — le non-respect cause des erreurs de connexion.

```
1. cfgRS (Config Server RS)      ← démarre en premier
2. Attente élection PRIMARY cfgRS ← obligatoire avant mongos
3. shardParis + shardLyon         ← peuvent démarrer en parallèle de cfgRS
4. mongos                         ← UNIQUEMENT après cfgRS initialisé
5. ReplicaSet noscitesRS          ← indépendant, peut démarrer en parallèle
```

**Pourquoi mongos ne peut pas démarrer avant cfgRS ?**
mongos se connecte au Config Server pour lire les métadonnées du cluster (quels chunks sont sur quels shards). Si cfgRS n'est pas encore élu, mongos ne peut pas lire ces métadonnées et échoue au démarrage.

---

## Ordre d'arrêt (critique)

> ⚠️ L'ordre inverse est important pour éviter la perte de données.

```
1. mongos                         ← arrêt du routeur en premier
2. shardParis + shardLyon         ← arrêt des shards
3. cfgRS                          ← arrêt du Config Server en dernier
4. ReplicaSet (SECONDARY → ARBITRE → PRIMARY)
```

**Pourquoi arrêter les SECONDARY avant le PRIMARY ?**
Si on arrête le PRIMARY en premier, les SECONDARY déclenchent immédiatement une élection (processus RAFT), ce qui génère des logs d'erreur inutiles et un délai. Arrêter les SECONDARY d'abord est plus propre.

---

## Connexions de référence

```bash
# ReplicaSet (données brutes, importées via mongoimport standard)
mongosh --port 27017

# Cluster shardé (point d'entrée pour toutes les requêtes de prod)
mongosh --port 27029

# Connexion directe à un shard (maintenance uniquement)
mongosh --port 27027   # shardParis
mongosh --port 27028   # shardLyon
```

---

## Commandes de vérification post-démarrage

```javascript
// Vérifier le ReplicaSet
mongosh --port 27017 --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'

// Vérifier le cluster shardé
mongosh --port 27029 --eval 'sh.status()'

// Vérifier la distribution des données
mongosh --port 27029 --eval 'use("noscites"); db.listings.getShardDistribution()'

// Compter les documents par ville via mongos
mongosh --port 27029 --eval '
  use("noscites");
  print("Paris :", db.listings.countDocuments({city:"Paris"}));
  print("Lyon  :", db.listings.countDocuments({city:"Lyon"}));
  print("Total :", db.listings.countDocuments());
'
```

---

## Résolution de problèmes courants

### "Address already in use" au démarrage

Un processus MongoDB tourne déjà. Vérifier avec :
```bash
bash status_mongodb.sh
# ou
ps aux | grep mongod
```
Si les services sont déjà UP, pas besoin de relancer.

### mongos ne démarre pas

Le Config Server RS (cfgRS) n'est pas encore prêt. Attendre 10-15 secondes après le démarrage de cfgRS, puis relancer :
```bash
bash start_mongodb.sh sharding
```

### Les données ont disparu après redémarrage

Les données sont persistées dans `~/mongodb/` — elles ne disparaissent pas au redémarrage. Si les collections semblent vides, vérifier qu'on se connecte au bon port :
```bash
# ✅ Données dans le cluster shardé → port 27029
mongosh --port 27029

# ❌ Ne pas confondre avec le ReplicaSet standalone → port 27017
# (qui contient les données de la Partie 1 uniquement)
```

### Force kill en dernier recours

```bash
# Tuer tous les processus MongoDB
kill $(pgrep -x mongod) 2>/dev/null
kill $(pgrep -x mongos) 2>/dev/null
```
