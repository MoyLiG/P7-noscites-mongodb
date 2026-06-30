# NosCités — Base de données NoSQL distribuée (MongoDB)

Conception d'une base **MongoDB** distribuée pour des annonces de logement
(données Airbnb Paris + Lyon), avec justification argumentée du choix NoSQL.

## Problème

Stocker et interroger des annonces hétérogènes — schéma variable, listes
imbriquées (`amenities`, `host.verifications`) — avec une perspective de montée
en charge multi-villes, là où un schéma relationnel imposerait des colonnes
NULL ou un pattern EAV et des migrations à chaque évolution.

## Architecture

Deux briques MongoDB :

- **Replica set** `noscitesRS` — haute disponibilité (PRIMARY + secondaires +
  arbitre).
- **Cluster shardé** — partitionnement horizontal par ville (`city` comme shard
  key, zones dédiées), routeur `mongos` et config servers.

```
ReplicaSet noscitesRS : rs0 (PRIMARY) | rs1 | rs2 | rs3 (arbitre)

Cluster shardé : cfgRS (config servers) → mongos (routeur)
   ├── shardParis → 95 885 docs Paris (90,8 %)
   └── shardLyon  →  9 973 docs Lyon  ( 9,2 %)
```

## Stack

MongoDB (replica set, sharding, config servers, mongos) · WSL2 · Tableau ·
Python (requêtes).

## Résultats

- **105 858 annonces** réparties par sharding (95 885 Paris / 9 973 Lyon).
- Choix NoSQL justifié sur 5 axes (schéma variable, imbrication native,
  évolutivité sans migration, sharding natif, alignement modèle requête /
  application).
- Requêtes analytiques et requêtes adaptées au sharding
  (`requetes_complexes.py`, `requetes_complexes_sharding.py`).
- Restitution Tableau (`Classeur1.twb`) et dictionnaire de données.

## Contenu

```
scripts_mongodb.md / README_scripts.md   gestion de l'infra MongoDB
start|status|stop_mongodb.sh             cycle de vie du cluster local
requetes_complexes*.py                   requêtes MongoDB (dont sharding)
schemas_mongodb.html                     schémas des collections
Data+Dictionary+(1).xlsx                 dictionnaire de données
rapport_projet_P7_v4.docx                rapport du projet
```

> Les jeux de données (CSV Airbnb, plusieurs centaines de Mo) ne sont pas
> versionnés. Sources : Inside Airbnb (Paris, Lyon).

---

*Projet OpenClassrooms — Data Engineer (P7).*
