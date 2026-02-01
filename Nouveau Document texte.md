# CSV Cleaner Lite 🚀

**Version :** 1.0.0
**Status :** Production Ready
**Engine :** PowerShell 5.1+ (Cross-Platform Compatible)

Un outil autonome et robuste de nettoyage et de standardisation de fichiers CSV. Conçu pour traiter de gros volumes de données avec une empreinte mémoire minimale.

---

## 📋 Fonctionnalités Clés

* **Streaming Pipeline :** Traitement ligne par ligne (Zéro surcharge RAM, même sur des fichiers de 10 Go).
* **Renommage Sécurisé :** Mapping des en-têtes via configuration externe.
* **Gestion des Collisions :** Si une colonne renommée existe déjà, elle n'est jamais écrasée (création automatique de `_2`, `_3`).
* **Atomicité :** Écriture via fichiers temporaires (`.tmp`) pour éviter la corruption de données en cas d'interruption.
* **Fail Fast :** Vérification stricte de l'environnement (Dossiers, Config) avant tout traitement.
* **Universel :** Compatible Windows PowerShell 5.1 (Legacy) et PowerShell 7+ (Core).

---

## 📂 Architecture

Le projet suit l'architecture **Context Engineering** :

```text
Root/
├── _context/               # Documentation Technique & Standards R&D
├── config/
│   ├── settings.json       # Paramètres globaux (Délimiteurs, Chemins)
│   └── mapping.csv         # Dictionnaire de renommage (Source -> Target)
├── core/
│   └── engine.ps1          # Moteur de traitement (Ne pas modifier)
├── data/
│   ├── input/              # Déposez vos fichiers sales ici
│   └── output/             # Récupérez vos fichiers propres ici
├── dist/
│   └── run.bat             # Lanceur (Double-cliquer pour exécuter)
└── logs/                   # Journaux d'exécution