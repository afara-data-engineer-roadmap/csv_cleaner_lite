<#
.SYNOPSIS
    Suite de tests d'intégration (Native - No Dependencies).
    Valide le cycle complet : Config -> Input -> Engine -> Output.
    VERSION ROBUSTE : Isole la configuration de mapping.
#>
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnginePath  = Join-Path $ProjectRoot "core\engine.ps1"

# Chemins des données de test
$TestInput   = Join-Path $ProjectRoot "data\input\_test_fara.csv"
$TestOutput  = Join-Path $ProjectRoot "data\output\_test_fara.csv"

# Chemins de configuration
$RealMapping = Join-Path $ProjectRoot "config\mapping.csv"
$BakMapping  = Join-Path $ProjectRoot "config\mapping.csv.bak"

Write-Host "`n[TEST] Démarrage de la suite de tests..." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. SETUP ENVIRONNEMENT (Injection de Config)
# -----------------------------------------------------------------------------
try {
    # On sauvegarde le vrai mapping s'il existe
    if (Test-Path $RealMapping) {
        Rename-Item -Path $RealMapping -NewName "mapping.csv.bak" -Force
    }

    # On injecte le mapping SPÉCIFIQUE au test (Tel -> Phone)
    @"
Source,Target
Client_Ref,ClientID
Tel,Phone
"@ | Out-File -FilePath $RealMapping -Encoding UTF8

    # Nettoyage préalable des fichiers de données
    if (Test-Path $TestInput)  { Remove-Item $TestInput -Force }
    if (Test-Path $TestOutput) { Remove-Item $TestOutput -Force }

    # -------------------------------------------------------------------------
    # 2. GÉNÉRATION DES DONNÉES PIÈGES
    # -------------------------------------------------------------------------
    # Scénario : 'Tel' devient 'Phone', mais 'Phone' existe déjà -> Collision
    $CsvContent = @"
Client_Ref;Tel;Phone;Montant_HT
TEST-001;0600000000;FixedLine;100
"@
    $CsvContent | Out-File $TestInput -Encoding UTF8
    Write-Host "[SETUP] Config injectée et fichier test généré." -ForegroundColor Gray

    # -------------------------------------------------------------------------
    # 3. EXÉCUTION DU MOTEUR
    # -------------------------------------------------------------------------
    Write-Host "[EXEC] Lancement de l'Engine..." -ForegroundColor Yellow
    
    # Appel du script Engine
    & $EnginePath | Out-Null

    # -------------------------------------------------------------------------
    # 4. ASSERTIONS (Vérifications)
    # -------------------------------------------------------------------------
    if (-not (Test-Path $TestOutput)) {
        Throw "[FAIL] Le fichier de sortie n'a pas été créé."
    }

    $Result = Import-Csv -Path $TestOutput -Delimiter ";"
    $Columns = $Result.PSObject.Properties.Name

    # Vérification 1 : Renommage basique
    if ('ClientID' -in $Columns) {
        Write-Host "[PASS] Mapping simple (Client_Ref -> ClientID)" -ForegroundColor Green
    } else {
        Write-Error "[FAIL] Mapping simple échoué. Colonnes : $($Columns -join ', ')"
    }

    # Vérification 2 : Gestion des Collisions (Phone + Phone_2)
    if ('Phone' -in $Columns -and 'Phone_2' -in $Columns) {
        Write-Host "[PASS] Gestion des collisions (Phone_2 créé)" -ForegroundColor Green
    } else {
        Write-Error "[FAIL] Collision mal gérée. Colonnes trouvées : $($Columns -join ', ')"
        # On ne throw pas ici pour laisser le finally restaurer la config
    }

}
catch {
    Write-Error "[CRITICAL] Erreur inattendue pendant le test : $_"
}
finally {
    # -------------------------------------------------------------------------
    # 5. TEARDOWN (Nettoyage & Restauration)
    # -------------------------------------------------------------------------
    Write-Host "[CLEANUP] Restauration de la configuration..." -ForegroundColor Gray
    
    # Suppression du mapping de test
    if (Test-Path $RealMapping) { Remove-Item $RealMapping -Force }
    
    # Restauration du vrai mapping
    if (Test-Path $BakMapping) {
        Rename-Item -Path $BakMapping -NewName "mapping.csv" -Force
    }

    # Suppression des fichiers de données
    Remove-Item $TestInput -Force -ErrorAction SilentlyContinue
    Remove-Item $TestOutput -Force -ErrorAction SilentlyContinue
}