# =============================================================
# Projet NosCités — Partie 2 : Requêtes complexes
# Outils : PyMongo (connexion MongoDB) + Polars (statistiques)
# =============================================================

from pymongo import MongoClient
import polars as pl

# ----- Connexion à MongoDB -----
client = MongoClient("mongodb://localhost:27017/")
collection = client["noscites"]["listings"]

print("Connexion à MongoDB réussie.")
print("Récupération des données en cours...\n")

# On récupère uniquement les champs nécessaires pour les calculs
data = list(collection.find({}, {
    "room_type":               1,
    "availability_30":         1,
    "number_of_reviews":       1,
    "host_is_superhost":       1,
    "neighbourhood_cleansed":  1,
    "_id":                     0
}))

# Chargement dans un DataFrame Polars
df = pl.DataFrame(data)
print(f"Documents chargés : {len(df):,}")
print(f"Colonnes          : {df.columns}\n")
print("=" * 60)


# ----- Q7 — Taux de réservation moyen par mois par type de logement -----
# Logique : availability_30 = jours DISPONIBLES sur les 30 prochains jours
# Donc jours réservés = 30 - availability_30
# Taux = (30 - availability_30) / 30 * 100

print("\nQ7 — Taux de réservation moyen par mois par type de logement")
print("-" * 60)

q7 = (
    df
    .with_columns(
        ((30 - pl.col("availability_30")) / 30 * 100).alias("taux_resa")
    )
    .group_by("room_type", maintain_order=False)
    .agg(
        pl.col("taux_resa").mean().round(2).alias("taux_moyen_%"),
        pl.col("taux_resa").median().round(2).alias("taux_median_%"),
        pl.len().alias("nb_annonces")
    )
    .unique(subset=["room_type"])
    .sort("taux_moyen_%", descending=True)
)
print(q7)


# ----- Q8 — Médiane des avis pour tous les logements -----
print("\nQ8 — Médiane des nombre d'avis (tous logements)")
print("-" * 60)

mediane_globale = df["number_of_reviews"].median()
moyenne_globale = df["number_of_reviews"].mean()
print(f"  Médiane  : {mediane_globale}")
print(f"  Moyenne  : {moyenne_globale:.2f}")
print(f"  Maximum  : {df['number_of_reviews'].max()}")
print()
print("Interprétation : la médiane à 3 signifie que 50% des logements")
print("ont 3 avis ou moins — beaucoup d'annonces très peu actives.")


# ----- Q9 — Médiane des avis par catégorie d'hôte -----
print("\nQ9 — Médiane des avis par catégorie d'hôte")
print("-" * 60)

q9 = (
    df
    .group_by("host_is_superhost", maintain_order=False)
    .agg(
        pl.col("number_of_reviews").median().alias("mediane_avis"),
        pl.col("number_of_reviews").mean().round(2).alias("moyenne_avis"),
        pl.len().alias("nb_logements")
    )
    .unique(subset=["host_is_superhost"])
    .sort("mediane_avis", descending=True)
)
q9 = q9.with_columns(
    pl.col("host_is_superhost")
    .replace({"t": "Super hôte", "f": "Hôte classique"})
    .alias("categorie")
).select(["categorie", "mediane_avis", "moyenne_avis", "nb_logements"])
print(q9)
print()
print("Interprétation : les super hôtes ont une médiane 12x plus élevée")
print("— ils sont beaucoup plus actifs et génèrent plus de réservations.")


# ----- Q10 — Densité de logements par quartier -----
print("\nQ10 — Top 20 quartiers par densité de logements")
print("-" * 60)

q10 = (
    df
    .group_by("neighbourhood_cleansed", maintain_order=False)
    .agg(pl.len().alias("nb_logements"))
    .sort("nb_logements", descending=True)
    .head(20)
)
print(q10)


# ----- Q11 — Quartiers avec le plus fort taux de réservation -----
print("\nQ11 — Top 20 quartiers par taux de réservation moyen")
print("-" * 60)

q11 = (
    df
    .with_columns(
        ((30 - pl.col("availability_30")) / 30 * 100).alias("taux_resa")
    )
    .group_by("neighbourhood_cleansed", maintain_order=False)
    .agg(
        pl.col("taux_resa").mean().round(2).alias("taux_moyen_%"),
        pl.len().alias("nb_logements")
    )
    .sort("taux_moyen_%", descending=True)
    .head(20)
)
print(q11)


# ----- Fermeture de la connexion -----
client.close()
print("\n" + "=" * 60)
print("Analyse terminée. Connexion MongoDB fermée.")
