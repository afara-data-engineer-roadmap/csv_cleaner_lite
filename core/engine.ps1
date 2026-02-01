<#
.SYNOPSIS
    Moteur de nettoyage CSV pour CSV Cleaner Lite.
    Applique le mapping d'en-têtes et gère les doublons de colonnes.

.DESCRIPTION
    Lit les configurations JSON et CSV.
    Traite les fichiers du dossier input en streaming.
    Gère les collisions de noms de colonnes via suffixe.
    Écrit de manière atomique (.tmp -> .csv).

.NOTES
    Version: 1.0
    Standards: 2.4 (Idempotent & Data Safe)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # -------------------------------------------------------------------------
    # 1. INITIALISATION & PATHING
    # -------------------------------------------------------------------------
    Write-Verbose "Initialisation de l'environnement..."

    # Ancrage au script et calcul de la racine du projet
    $ScriptPath = $PSScriptRoot
    $ProjectRoot = Split-Path -Parent $ScriptPath

    # Définition des chemins absolus selon l'Architecture
    $ConfigDir  = Join-Path -Path $ProjectRoot -ChildPath "config"
    $InputDir   = Join-Path -Path $ProjectRoot -ChildPath "data\input"
    $OutputDir  = Join-Path -Path $ProjectRoot -ChildPath "data\output"
    
    $SettingsPath = Join-Path -Path $ConfigDir -ChildPath "settings.json"
    $MappingPath  = Join-Path -Path $ConfigDir -ChildPath "mapping.csv"

    # Fail Fast : Vérification des dossiers et fichiers critiques
    $CriticalPaths = @($ConfigDir, $InputDir, $OutputDir, $SettingsPath, $MappingPath)
    foreach ($Path in $CriticalPaths) {
        if (-not (Test-Path -Path $Path)) {
            Throw "Ressource critique manquante : $Path"
        }
    }

    # -------------------------------------------------------------------------
    # 2. CHARGEMENT DE LA CONFIGURATION
    # -------------------------------------------------------------------------
    Write-Verbose "Chargement de la configuration..."

    # Lecture Settings (JSON) pour le délimiteur
    try {
        $JsonContent = Get-Content -Path $SettingsPath -Raw -ErrorAction Stop
        $Settings = $JsonContent | ConvertFrom-Json
        $Delimiter = $Settings.CsvDelimiter
        
        if ([string]::IsNullOrWhiteSpace($Delimiter)) {
            Throw "Le paramètre 'CsvDelimiter' est vide ou absent dans settings.json."
        }
        Write-Verbose "Délimiteur détecté : '$Delimiter'"
    }
    catch {
        Throw "Erreur lors de la lecture de settings.json : $_"
    }

    # Lecture Mapping (CSV)
    # Création d'une Hashtable pour lookup rapide (Source -> Target)
    $MapRules = @{}
    try {
        # Array Forcing sur l'import du mapping
        $MappingData = @(Import-Csv -Path $MappingPath -Delimiter ",") 
        
        foreach ($Rule in $MappingData) {
            if (-not [string]::IsNullOrWhiteSpace($Rule.Source) -and -not [string]::IsNullOrWhiteSpace($Rule.Target)) {
                $MapRules[$Rule.Source] = $Rule.Target
            }
        }
        Write-Verbose "Règles de mapping chargées : $($MapRules.Count)"
    }
    catch {
        Throw "Erreur lors de la lecture de mapping.csv : $_"
    }

    # -------------------------------------------------------------------------
    # 3. TRAITEMENT DES FICHIERS (STREAMING)
    # -------------------------------------------------------------------------
    # Array Forcing sur la liste des fichiers
    $InputFiles = @(Get-ChildItem -Path $InputDir -Filter "*.csv" -File)

    if ($InputFiles.Count -eq 0) {
        Write-Warning "Aucun fichier CSV trouvé dans $InputDir."
        return
    }

    foreach ($File in $InputFiles) {
        Write-Output "Traitement du fichier : $($File.Name)"
        
        $TempOutputPath = Join-Path -Path $OutputDir -ChildPath "$($File.BaseName).tmp"
        $FinalOutputPath = Join-Path -Path $OutputDir -ChildPath "$($File.Name)"

        try {
            # A. ANALYSE DES EN-TÊTES (PRE-FLIGHT CHECK)
            # Lecture de la première ligne uniquement pour déterminer les headers sans charger le fichier
            $HeaderLine = Get-Content -Path $File.FullName -TotalCount 1
            if ([string]::IsNullOrWhiteSpace($HeaderLine)) {
                Write-Warning "Fichier vide ou en-tête manquant : $($File.Name)"
                continue
            }

            # Découpage des headers sources
            # Note : On utilise le délimiteur configuré
            $SourceHeaders = $HeaderLine -split $Delimiter

            # B. CONSTRUCTION DE LA LOGIQUE DE SÉLECTION (COLLISION HANDLING)
            $SelectProperties = @()
            $UsedTargetNames = @{} # Compteur pour gérer les suffixes (Phone, Phone_2)

            foreach ($ColName in $SourceHeaders) {
                # Nettoyage basique du nom de colonne (trim quotes éventuelles)
                $CleanColName = $ColName.Trim('"').Trim()

                # 1. Déterminer le nom cible (Mapping ou Original)
                $TargetName = if ($MapRules.ContainsKey($CleanColName)) { 
                    $MapRules[$CleanColName] 
                } else { 
                    $CleanColName 
                }

                # 2. Gestion des doublons (Collision Strategy)
                if ($UsedTargetNames.ContainsKey($TargetName)) {
                    $UsedTargetNames[$TargetName]++
                    $FinalName = "${TargetName}_$($UsedTargetNames[$TargetName])"
                }
                else {
                    $UsedTargetNames[$TargetName] = 1
                    $FinalName = $TargetName
                }

                # 3. Création de la propriété calculée pour Select-Object
                # On capture $CleanColName dans une closure pour l'utiliser dans le pipeline
                $PropertyHash = @{
                    Name       = $FinalName
                    Expression = [scriptblock]::Create("`$_.'$CleanColName'")
                }
                $SelectProperties += $PropertyHash
            }

            # C. EXÉCUTION DU PIPELINE (STREAMING)
            # Import -> Select (Renommage) -> Export (Temp)
            Import-Csv -Path $File.FullName -Delimiter $Delimiter |
                Select-Object -Property $SelectProperties |
                Export-Csv -Path $TempOutputPath -Delimiter $Delimiter -NoTypeInformation -Encoding UTF8
            
            # D. ATOMICITÉ (RENAME)
            if (Test-Path -Path $TempOutputPath) {
                Move-Item -Path $TempOutputPath -Destination $FinalOutputPath -Force
                Write-Verbose "Succès : $FinalOutputPath généré."
            }
        }
        catch {
            Write-Warning "Échec du traitement pour $($File.Name) : $_"
            # Nettoyage fichier temporaire en cas d'erreur
            if (Test-Path -Path $TempOutputPath) {
                Remove-Item -Path $TempOutputPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Output "Traitement terminé avec succès."
}
catch {
    Write-Error "Arrêt critique du moteur : $_"
    exit 1
}