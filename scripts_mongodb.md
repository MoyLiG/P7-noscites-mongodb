# Scripts MongoDB — Projet NosCités P7

> Tous ces scripts sont à exécuter sur ta machine locale où MongoDB est installé.
> Base de données : `noscites` | Collection principale : `listings`

> ⚠️ **Note OS** : Les commandes shell diffèrent selon le système d'exploitation.
> - **Linux/macOS (production)** : `mkdir -p ~/mongodb/rs0` — le `-p` crée les parents si absents, `~` = dossier personnel
> - **Windows PowerShell (dev)** : `New-Item -ItemType Directory -Force -Path "C:\mongodb\rs0"` — `-Force` = équivalent de `-p`
> - Les commandes `mongod`, `mongoimport`, `mongosh` sont identiques sur tous les OS, seul le chemin d'accès change si l'outil n'est pas dans le PATH.

---

## PARTIE 1 — Import et exploration

### 1.1 Import des données Paris (CLI)
```bash
# Dans un terminal sur ta machine
mongoimport \
  --db noscites \
  --collection listings \
  --type csv \
  --headerline \
  --file "listings_Paris.csv"
```

### 1.2 Vérification de l'import (mongosh)
```javascript
// Dans mongosh
use noscites

// Nombre total de documents
db.listings.countDocuments()
// Résultat attendu : 95885

// Premier document
db.listings.findOne()

// Logements avec disponibilités
db.listings.countDocuments({ has_availability: "t" })
// Résultat attendu : 90173
```

---

## PARTIE 2 — Requêtes simples (mongosh)

```javascript
use noscites

// Q1 — Annonces par type de location
db.listings.aggregate([
  { $group: { _id: "$room_type", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
// Résultats :
// Entire home/apt : 85733 (89.4%)
// Private room    :  8975  (9.4%)
// Hotel room      :   776  (0.8%)
// Shared room     :   401  (0.4%)

// Q2 — Top 5 annonces avec le plus d'évaluations
db.listings.find(
  {},
  { id: 1, name: 1, number_of_reviews: 1, _id: 0 }
).sort({ number_of_reviews: -1 }).limit(5)
// Top 1 : id=17222007, 3067 avis - "Sweet & cosy room next to Canal Saint Martin"
// Top 2 : id=26244787, 2620 avis - "Double/Twin Room, close to Opera and the Louvre"
// Top 3 : id=41020735, 2294 avis - "Bed in Dorm of 8 Beds..."

// Q3 — Nombre d'hôtes différents
db.listings.distinct("host_id").length
// Résultat attendu : 71979

// Q4 — Réservation instantanée
db.listings.countDocuments({ instant_bookable: "t" })
// Résultat attendu : 22094 (23.0%)

// Q5 — Hôtes avec plus de 100 annonces
db.listings.aggregate([
  { $group: {
      _id: "$host_id",
      host_name: { $first: "$host_name" },
      nb_annonces: { $max: "$host_total_listings_count" }
  }},
  { $match: { nb_annonces: { $gt: 100 } } },
  { $sort: { nb_annonces: -1 } }
])
// Résultat : 113 hôtes (0.16%)
// Top 1 : Travelnest (6278 annonces)

// Q6 — Super hôtes
db.listings.distinct("host_id", { host_is_superhost: "t" }).length
// Résultat attendu : 10027 (13.9% des hôtes)
```

---

## PARTIE 2 — Requêtes complexes (Python + PyMongo)

```python
# pip install pymongo pandas
from pymongo import MongoClient
import pandas as pd
import numpy as np

client = MongoClient("mongodb://localhost:27017/")
db = client["noscites"]
collection = db["listings"]

# Récupération des données dans un DataFrame pandas
cursor = collection.find({}, {
    "room_type": 1,
    "availability_30": 1,
    "number_of_reviews": 1,
    "host_is_superhost": 1,
    "neighbourhood_cleansed": 1,
    "_id": 0
})
df = pd.DataFrame(list(cursor))

# Q7 — Taux de réservation moyen par mois par type de logement
df['taux_resa_30j'] = (30 - df['availability_30']) / 30 * 100
q7 = df.groupby('room_type')['taux_resa_30j'].mean().round(2).sort_values(ascending=False)
print("Taux de réservation moyen par type :")
print(q7)
# Entire home/apt : 71.29%  |  Private room : 70.29%
# Shared room     : 60.72%  |  Hotel room   : 53.53%

# Q8 — Médiane des avis pour tous les logements
mediane = df['number_of_reviews'].median()
print(f"\nMédiane des avis : {mediane}")
# Résultat : 3.0

# Q9 — Médiane des avis par catégorie d'hôte
q9 = df.groupby('host_is_superhost')['number_of_reviews'].median()
print("\nMédiane avis par type d'hôte :")
print(q9)
# Super hôte (t)     : 24.0
# Hôte classique (f) :  2.0

# Q10 — Densité de logements par quartier
q10 = df['neighbourhood_cleansed'].value_counts().head(20)
print("\nTop 20 quartiers par densité :")
print(q10)
# Top 1 : Buttes-Montmartre (10555)

# Q11 — Quartiers avec le plus fort taux de réservation
q11 = df.groupby('neighbourhood_cleansed')['taux_resa_30j'].mean().sort_values(ascending=False)
print("\nTop quartiers par taux de réservation :")
print(q11.head(10))
# Top 1 : Ménilmontant (75.42%)
```

---

## PARTIE 3 — Fusion Paris + Lyon

### 3.1 Ajouter le champ "city" aux CSV avant import

> ⚠️ Les fichiers CSV bruts (Paris et Lyon) ne contiennent pas de champ `city`.
> Il faut l'ajouter avant l'import pour pouvoir filtrer et shardiser par ville.

```bash
# Script Python pour préparer les deux fichiers
python3 << 'EOF'
import pandas as pd

# Paris
df_paris = pd.read_csv("listings_Paris.csv", low_memory=False)
df_paris['city'] = 'Paris'
df_paris.to_csv("listings_Paris_tagged.csv", index=False)
print(f"Paris taggé : {len(df_paris)} documents")

# Lyon
df_lyon = pd.read_csv("listings_Lyon.csv", low_memory=False)
df_lyon['city'] = 'Lyon'
df_lyon.to_csv("listings_Lyon_tagged.csv", index=False)
print(f"Lyon taggé : {len(df_lyon)} documents")
EOF
```

### 3.2 Import des deux villes dans la collection unifiée
```bash
# Import Paris avec city
mongoimport \
  --db noscites \
  --collection listings \
  --type csv \
  --headerline \
  --file "listings_Paris_tagged.csv"

# Import Lyon avec city
mongoimport \
  --db noscites \
  --collection listings \
  --type csv \
  --headerline \
  --file "listings_Lyon_tagged.csv"
```

### 3.3 Vérification de la fusion
```javascript
use noscites

db.listings.countDocuments({ city: "Paris" })  // 95885
db.listings.countDocuments({ city: "Lyon" })   // 9973
db.listings.countDocuments()                   // 105858
```

---

## PARTIE 3 — ReplicaSet (simulation locale, 4 nœuds)

```bash
# Créer les répertoires de données pour 4 instances
mkdir -p ~/mongodb/rs0 ~/mongodb/rs1 ~/mongodb/rs2 ~/mongodb/rs3

# Lancer les 4 instances sur des ports différents
mongod --replSet noscitesRS --port 27017 --dbpath ~/mongodb/rs0 --fork --logpath ~/mongodb/rs0/mongod.log --bind_ip_all
mongod --replSet noscitesRS --port 27018 --dbpath ~/mongodb/rs1 --fork --logpath ~/mongodb/rs1/mongod.log --bind_ip_all
mongod --replSet noscitesRS --port 27019 --dbpath ~/mongodb/rs2 --fork --logpath ~/mongodb/rs2/mongod.log --bind_ip_all
mongod --replSet noscitesRS --port 27020 --dbpath ~/mongodb/rs3 --fork --logpath ~/mongodb/rs3/mongod.log --bind_ip_all
```

```javascript
// Dans mongosh (sur le port 27017 — futur PRIMARY)
mongosh --port 27017

// Initialiser le ReplicaSet
rs.initiate({
  _id: "noscitesRS",
  members: [
    { _id: 0, host: "localhost:27017", priority: 2 },       // PRIMARY
    { _id: 1, host: "localhost:27018", priority: 1 },       // SECONDARY 1
    { _id: 2, host: "localhost:27019", priority: 1 },       // SECONDARY 2
    { _id: 3, host: "localhost:27020", arbiterOnly: true }  // ARBITRE (vote uniquement)
  ]
})

// Attendre ~10s puis vérifier le statut
rs.status()

// Vérifier la réplication (depuis le PRIMARY)
rs.printReplicationInfo()

// Vérifier les données sur un SECONDARY
mongosh --port 27018 --eval '
  db.getMongo().setReadPref("secondary");
  use("noscites");
  print("SECONDARY 1 - Total:", db.listings.countDocuments());
'
```

**Logique choisie :**
- `localhost:27017` = PRIMARY (priorité 2 → élu en premier)
- `localhost:27018` = SECONDARY 1 (réplique complète des données)
- `localhost:27019` = SECONDARY 2 (redondance supplémentaire)
- `localhost:27020` = ARBITRE (vote quorum 3/4, ne stocke pas de données)

---

## PARTIE 3 — Sharding (simulation locale)

> **Architecture** : Config Server Replica Set (CSRS) à 3 nœuds — évite le SPOF sur les métadonnées du cluster.
> Ports 27024–27026 réservés au CSRS. Shards sur 27027–27028. mongos sur 27029.

> ⚠️ **Ordre critique à respecter** : mongos NE PEUT PAS démarrer avant que le Config Server RS
> soit initialisé. Suivre impérativement les étapes dans l'ordre ci-dessous.

### Étape 1 — Démarrer les Config Servers (CSRS)
```bash
mkdir -p ~/mongodb/cfg0 ~/mongodb/cfg1 ~/mongodb/cfg2

mongod --configsvr --replSet cfgRS --port 27024 --dbpath ~/mongodb/cfg0 --fork --logpath ~/mongodb/cfg0/mongod.log --bind_ip_all
mongod --configsvr --replSet cfgRS --port 27025 --dbpath ~/mongodb/cfg1 --fork --logpath ~/mongodb/cfg1/mongod.log --bind_ip_all
mongod --configsvr --replSet cfgRS --port 27026 --dbpath ~/mongodb/cfg2 --fork --logpath ~/mongodb/cfg2/mongod.log --bind_ip_all
```

### Étape 2 — Initialiser le CSRS ✅ (AVANT de lancer mongos)
```javascript
// Se connecter au premier nœud config
mongosh --port 27024

rs.initiate({
  _id: "cfgRS",
  configsvr: true,
  members: [
    { _id: 0, host: "localhost:27024" },
    { _id: 1, host: "localhost:27025" },
    { _id: 2, host: "localhost:27026" }
  ]
})
// Attendre que le PRIMARY cfgRS soit élu (~5s) avant de continuer
```

### Étape 3 — Démarrer les Shards
```bash
mkdir -p ~/mongodb/shard_paris ~/mongodb/shard_lyon

mongod --shardsvr --replSet shardParis --port 27027 --dbpath ~/mongodb/shard_paris --fork --logpath ~/mongodb/shard_paris/mongod.log --bind_ip_all
mongod --shardsvr --replSet shardLyon  --port 27028 --dbpath ~/mongodb/shard_lyon  --fork --logpath ~/mongodb/shard_lyon/mongod.log --bind_ip_all
```

### Étape 4 — Initialiser les Shards
```javascript
// Shard Paris
mongosh --port 27027
rs.initiate({ _id: "shardParis", members: [{ _id: 0, host: "localhost:27027" }] })

// Shard Lyon
mongosh --port 27028
rs.initiate({ _id: "shardLyon", members: [{ _id: 0, host: "localhost:27028" }] })
```

### Étape 5 — Démarrer mongos (APRÈS initialisation du CSRS)
```bash
# mongos se connecte au cfgRS déjà initialisé — ne pas lancer avant l'étape 2
mongos --configdb cfgRS/localhost:27024,localhost:27025,localhost:27026 \
       --port 27029 \
       --fork \
       --logpath ~/mongodb/mongos.log \
       --bind_ip_all
```

### Étape 6 — Configurer le cluster via mongos
```javascript
// Se connecter au routeur
mongosh --port 27029

// Ajouter les shards au cluster
sh.addShard("shardParis/localhost:27027")
sh.addShard("shardLyon/localhost:27028")

// Activer le sharding sur la base de données
sh.enableSharding("noscites")

// Créer un index sur la shard key AVANT de shardiser
use noscites
db.listings.createIndex({ city: 1, _id: 1 })

// Shardiser la collection
sh.shardCollection("noscites.listings", { city: 1, _id: 1 })

// Définir les zones géographiques
sh.addShardToZone("shardParis", "PARIS")
sh.addShardToZone("shardLyon",  "LYON")

// Attribuer les plages de données à chaque zone
sh.updateZoneKeyRange("noscites.listings",
  { city: "Paris", _id: MinKey() },
  { city: "Paris", _id: MaxKey() },
  "PARIS"
)
sh.updateZoneKeyRange("noscites.listings",
  { city: "Lyon", _id: MinKey() },
  { city: "Lyon", _id: MaxKey() },
  "LYON"
)
```

### Étape 7 — Importer les données via mongos
```bash
# Les données doivent être importées VIA mongos (port 27029)
# pour être distribuées automatiquement selon les zones

mongoimport \
  --port 27029 \
  --db noscites \
  --collection listings \
  --type csv \
  --headerline \
  --file "listings_Paris_tagged.csv"

mongoimport \
  --port 27029 \
  --db noscites \
  --collection listings \
  --type csv \
  --headerline \
  --file "listings_Lyon_tagged.csv"
```

### Étape 8 — Vérification de la distribution
```javascript
// Dans mongosh --port 27029
use noscites

db.listings.getShardDistribution()
```

**Résultats obtenus :**
```
Shard shardLyon at shardLyon/localhost:27028
{ data: '33.33MiB', docs: 9973, chunks: 4, 'estimated data per chunk': '8.33MiB' }

Shard shardParis at shardParis/localhost:27027
{ data: '328.49MiB', docs: 95885, chunks: 1, 'estimated data per chunk': '328.49MiB' }

Totals
{ data: '361.82MiB', docs: 105858, chunks: 5,
  'Shard shardLyon':  [ '9.21% data',  '9.42% docs' ],
  'Shard shardParis': [ '90.78% data', '90.57% docs' ] }
```

---

## PARTIE 4 — Requêtes de démonstration sur le cluster shardé

> Ces requêtes s'exécutent toutes via **mongos (port 27029)**.
> mongos analyse la shard key `city` et route chaque requête vers le bon shard — sans que l'application ait à connaître l'architecture sous-jacente.

### Démonstration du routage automatique
```javascript
// Dans mongosh --port 27029
use noscites

// Chaque ville est isolée sur son shard dédié.
// Le routeur mongos dirige automatiquement les requêtes
// vers le bon shard selon la valeur du champ city.
print("=== Routage automatique via mongos :27029 ===")
print("shardParis → Paris :", db.listings.countDocuments({ city: "Paris" }))
print("shardLyon  → Lyon  :", db.listings.countDocuments({ city: "Lyon" }))
print("Total      (mongos):", db.listings.countDocuments())
// shardParis → Paris : 95885
// shardLyon  → Lyon  : 9973
// Total      (mongos): 105858
```

### Requête ciblée sur un seul shard (targeted query)
```javascript
// Cette requête ne touche QUE shardParis — mongos ne consulte pas shardLyon
db.listings.find(
  { city: "Paris", room_type: "Entire home/apt" },
  { name: 1, price: 1, neighbourhood_cleansed: 1, _id: 0 }
).limit(5)

// Preuve du ciblage : explain() montre le shard utilisé
db.listings.find({ city: "Paris" }).explain("executionStats")
// → "shards": ["shardParis"] — shardLyon n'est pas consulté
```

### Agrégation par ville — comparaison Paris vs Lyon
```javascript
db.listings.aggregate([
  {
    $group: {
      _id: "$city",
      nb_annonces:        { $sum: 1 },
      nb_superhotes:      { $sum: { $cond: [{ $eq: ["$host_is_superhost", "t"] }, 1, 0] } },
      resa_instantanee:   { $sum: { $cond: [{ $eq: ["$instant_bookable", "t"] }, 1, 0] } }
    }
  },
  { $sort: { nb_annonces: -1 } }
])
// Paris : 95885 annonces | Lyon : 9973 annonces
```

### Top 5 quartiers par ville
```javascript
db.listings.aggregate([
  { $group: { _id: { city: "$city", quartier: "$neighbourhood_cleansed" }, count: { $sum: 1 } } },
  { $sort: { "_id.city": 1, count: -1 } },
  {
    $group: {
      _id: "$_id.city",
      top_quartiers: { $push: { quartier: "$_id.quartier", annonces: "$count" } }
    }
  },
  { $project: { top5: { $slice: ["$top_quartiers", 5] } } }
])
```

### Requête scatter (tous shards) — sans filtre city
```javascript
// Sans filtre city, mongos interroge TOUS les shards (scatter-gather)
// Utilisé pour les stats globales
db.listings.aggregate([
  { $group: { _id: "$room_type", total: { $sum: 1 } } },
  { $sort: { total: -1 } }
])
// mongos fusionne automatiquement les résultats de shardParis et shardLyon
```

---

## Résultats clés à retenir

| Indicateur | Paris | Lyon |
|---|---|---|
| Annonces totales | 95 885 | 9 973 |
| Hôtes uniques | 71 979 | 7 703 |
| Super hôtes | 10 027 (13.9%) | 1 331 (17.3%) |
| Résa instantanée | 22 094 (23.0%) | 2 112 (21.2%) |
| Type dominant | Entire home/apt (89.4%) | Entire home/apt |
| Quartier le + dense | Buttes-Montmartre (10 555) | — |
| Quartier taux résa le + haut | Ménilmontant (75.4%) | — |
| Médiane avis | 3 | — |
| Médiane avis super hôtes | 24 | — |

### Distribution sharding (résultats validés)

| Shard | Port | Zone | Documents | % données |
|---|---|---|---|---|
| shardParis | 27027 | PARIS | 95 885 | 90.57% |
| shardLyon | 27028 | LYON | 9 973 | 9.42% |
| **Total** | via mongos 27029 | — | **105 858** | **100%** |
