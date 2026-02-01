Markdown
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
⚙️ Configuration
1. Paramètres Généraux (config/settings.json)
JSON
{
    "AppName": "CSV Cleaner Lite",
    "InputFolder": "data\\input",
    "OutputFolder": "data\\output",
    "MappingFile": "config\\mapping.csv",
    "CsvDelimiter": ";",          <-- IMPORTANT : Définit le séparateur (Input & Output)
    "Encoding": "UTF8"
}
2. Règles de Mapping (config/mapping.csv)
Définit comment renommer les colonnes.

Format : Source,Target (Séparateur virgule obligatoire pour ce fichier de config).

Règle : Insensible à la casse (nom et Nom seront traités pareil).

Exemple :

Extrait de code
Source,Target
Client_Ref,ClientID
Date_Facture,InvoiceDate
Montant_HT,Amount
🚀 Utilisation
Dépôt : Placez vos fichiers .csv dans le dossier data/input.

Exécution : Double-cliquez sur le fichier dist/run.bat.

Résultat : Une fenêtre s'ouvre, affiche la progression, et se ferme.

Récupération : Vos fichiers nettoyés sont dans data/output.

🛠️ Espace Développeur
Ce projet a été généré en utilisant la méthodologie Context Engineering.

Standards de Code (Bundle)
Toute modification du code dans core/engine.ps1 doit respecter les règles strictes définies dans _context/core_powershell_standards.md :

Naming : PascalCase pour variables et fonctions.

Robustesse : Usage obligatoire de [CmdletBinding()] et $ErrorActionPreference = 'Stop'.

Sécurité Mémoire : Interdiction stricte de charger Import-Csv dans une variable ($rows = ... ❌). Toujours utiliser le pipeline (| ✅).

Compatibilité : Forçage de tableau @(...) pour les retours de commandes.

Commandes Manuelles
Pour exécuter le moteur sans le run.bat (pour debug) :

PowerShell
# Depuis la racine du projet
PowerShell.exe -ExecutionPolicy Bypass -File "core/engine.ps1" -Verbose
Licence : Usage Interne Uniquement. Contact Support : [Votre Nom/Équipe]