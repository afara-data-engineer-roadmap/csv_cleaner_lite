# ARCHITECTURE PROJET : CSV CLEANER LITE (REALITY CHECK)
Type : Standalone PowerShell Tool
Status : Active Development

## 📂 STRUCTURE DES DOSSIERS (SOURCE OF TRUTH)
Root/ (C:\Dev\Products\csv_cleaner_lite)
├── _context/               # Cerveau R&D : Bundles, Chunks, Prompts
├── config/
│   ├── settings.json       # Config (Chemins relatifs, Délimiteurs)
│   └── mapping.csv         # Règles métier (Source -> Target)
├── core/
│   └── engine.ps1          # Agent 1 : Moteur PowerShell (Streaming)
├── data/
│   ├── input/              # Zone de dépôt (Fichiers sales)
│   └── output/             # Zone de retrait (Fichiers propres)
├── dist/
│   └── run.bat             # Launcher Utilisateur (remplace deployment/)
├── logs/                   # Journaux d'exécution (Verbose/Error)
├── src/                    # (Optionnel) Sources brutes ou scripts annexes
└── test_data/              # Jeux de données statiques pour tests unitaires

## 🔄 FLUX DE DONNÉES (DATA FLOW)
1. User dépose CSV dans `data/input`.
2. User lance `dist/run.bat`.
3. `run.bat` appelle `../core/engine.ps1`.
4. `engine.ps1` lit `../config/settings.json`.
5. `engine.ps1` traite le flux vers `../data/output`.