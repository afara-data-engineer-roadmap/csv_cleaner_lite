<#
engine.ps1 — csv_cleaner_lite (Engine)
Version: 1.4 (Final - Delimiter Support Restored)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Assert-DirectoryExists {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Fail Fast: dossier introuvable ($Label) : '$Path'"
    }
}

function Assert-FileExists {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fail Fast: fichier introuvable ($Label) : '$Path'"
    }
}

function Get-ResolvedMappingTarget {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][hashtable]$Mapping,
        [Parameter(Mandatory = $true)][string]$SourceName
    )
    if ($Mapping.ContainsKey($SourceName) -and -not [string]::IsNullOrWhiteSpace([string]$Mapping[$SourceName])) {
        return [string]$Mapping[$SourceName]
    }
    return $SourceName
}

function Get-UniqueName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][hashtable]$UsedNames,
        [Parameter(Mandatory = $true)][string]$Candidate
    )
    if (-not $UsedNames.ContainsKey($Candidate)) {
        $UsedNames[$Candidate] = $true
        return $Candidate
    }
    $Index = 2
    while ($true) {
        $Alt = "{0}_{1}" -f $Candidate, $Index
        if (-not $UsedNames.ContainsKey($Alt)) {
            $UsedNames[$Alt] = $true
            return $Alt
        }
        $Index++
    }
}

try {
    # --- Pathing & anchoring ---
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $ConfigPath  = Join-Path $ProjectRoot 'config\settings.json'

    Write-Verbose "ProjectRoot: $ProjectRoot"
    Assert-FileExists -Path $ConfigPath -Label 'settings.json'

    # --- Load settings.json ---
    $Settings = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    $DefaultInputPath  = Join-Path $ProjectRoot 'Input'
    $DefaultOutputPath = Join-Path $ProjectRoot 'Output'

    # Fallback robuste pour les dossiers
    $InputPath  = if ($Settings.PSObject.Properties.Name -contains 'InputFolder'  -and $Settings.InputFolder)  { [string]$Settings.InputFolder }  else { $DefaultInputPath }
    $OutputPath = if ($Settings.PSObject.Properties.Name -contains 'OutputFolder' -and $Settings.OutputFolder) { [string]$Settings.OutputFolder } else { $DefaultOutputPath }
    
    # --- FIX: Récupération du Délimiteur ---
    $Delimiter = if ($Settings.PSObject.Properties.Name -contains 'CsvDelimiter') { [string]$Settings.CsvDelimiter } else { ',' }

    # Ancrage des chemins relatifs
    if (-not [System.IO.Path]::IsPathRooted($InputPath))  { $InputPath  = Join-Path $ProjectRoot $InputPath }
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $ProjectRoot $OutputPath }

    # mapping.csv : logique de recherche
    $MappingCandidates = @()
    if ($Settings.PSObject.Properties.Name -contains 'MappingFile' -and $Settings.MappingFile) {
        $Candidate = [string]$Settings.MappingFile
        if (-not [System.IO.Path]::IsPathRooted($Candidate)) { $Candidate = Join-Path $ProjectRoot $Candidate }
        $MappingCandidates += $Candidate
    }
    $MappingCandidates += (Join-Path $ProjectRoot 'config\mapping.csv')
    $MappingCandidates += (Join-Path $ProjectRoot 'mapping.csv')

    $MappingPath = $null
    foreach ($Candidate in $MappingCandidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $MappingPath = $Candidate
            break
        }
    }
    if (-not $MappingPath) {
        throw "Fail Fast: mapping.csv introuvable."
    }

    Write-Verbose "InputPath  : $InputPath"
    Write-Verbose "OutputPath : $OutputPath"
    Write-Verbose "MappingPath: $MappingPath"
    Write-Verbose "Delimiter  : '$Delimiter'"

    Assert-DirectoryExists -Path $InputPath  -Label 'Input'
    Assert-DirectoryExists -Path $OutputPath -Label 'Output'

    # --- Load mapping.csv ---
    $Mapping = @{}
    # On force le délimiteur ici aussi au cas où le mapping serait en CSV point-virgule
    # Mais souvent mapping.csv est standard. Utilisons l'auto-détection ou virgule par défaut pour le mapping
    # Note: Si ton mapping.csv utilise des points-virgules, change le delimiter ici.
    Import-Csv -LiteralPath $MappingPath | ForEach-Object {
        if ($null -eq $_) { return }
        $Source = [string]$_.Source
        $Target = [string]$_.Target

        if ([string]::IsNullOrWhiteSpace($Source)) { return }
        $Mapping[$Source] = $Target
    }

    # --- Process CSV files ---
    $InputFiles = @(Get-ChildItem -LiteralPath $InputPath -File -Filter '*.csv')
    
    if ($InputFiles.Count -eq 0) {
        Write-Warning "Aucun fichier .csv trouvé dans '$InputPath'."
        return
    }

    foreach ($File in $InputFiles) {
        $InPath  = $File.FullName
        $OutPath = Join-Path $OutputPath $File.Name

        Write-Verbose "Traitement: '$InPath'"

        if ($WhatIf) {
            Write-Verbose "WhatIf: SKIP '$InPath'"
            continue
        }

        # Streaming transform avec Délimiteur
        Import-Csv -LiteralPath $InPath -Delimiter $Delimiter |
            ForEach-Object {
                $UsedNames = @{}
                $OutRow = [ordered]@{}

                foreach ($Prop in $_.PSObject.Properties) {
                    $SourceName = [string]$Prop.Name
                    $TargetName = Get-ResolvedMappingTarget -Mapping $Mapping -SourceName $SourceName
                    
                    # Gestion collisions
                    $UniqueTarget = Get-UniqueName -UsedNames $UsedNames -Candidate $TargetName
                    
                    $OutRow[$UniqueTarget] = $Prop.Value
                }

                [pscustomobject]$OutRow
            } |
            Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

        Write-Verbose "OK -> '$OutPath'"
    }
}
catch {
    Write-Error "Echec engine.ps1: $($_.Exception.Message)"
    throw
}