<#
.SYNOPSIS
    csv_cleaner_lite - Engine
.DESCRIPTION
    Loads config (../config/settings.json), validates Input/Output folders,
    loads mapping.csv into a hashtable, then processes CSV files from Input to Output (streaming).
.NOTES
    Standards enforced (v2.3): CmdletBinding, param typed, fail-fast, anchored paths, no Write-Host,
    explicit delimiters, UTF8 export, streaming pipeline, PS 5.1 array forcing.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ProjectRootPath
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectRoot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProjectRootPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ProjectRootPath)) {
        return (Resolve-Path -Path $ProjectRootPath).Path
    }

    # engine.ps1 expected under /core (or similar). Root = parent of $PSScriptRoot.
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-Settings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }

    $JsonText = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
    try {
        return ($JsonText | ConvertFrom-Json)
    }
    catch {
        throw "Invalid JSON in config file: $ConfigPath. Details: $($_.Exception.Message)"
    }
}

function Assert-FolderExists {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "$Label folder missing: $Path"
    }
}

function Get-DelimiterChar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Settings
    )

    # Defaults to ';' to match common FR/Excel export; enforce explicit delimiter always.
    $DelimiterValue = $Settings.Delimiter
    if ([string]::IsNullOrWhiteSpace($DelimiterValue)) {
        return ';'
    }

    if ($DelimiterValue.Length -ne 1) {
        throw "Config 'Delimiter' must be a single character. Current value: '$DelimiterValue'"
    }

    return [char]$DelimiterValue
}

function Import-MappingAsHashtable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MappingPath,

        [Parameter(Mandatory = $true)]
        [char]$Delimiter
    )

    if (-not (Test-Path -Path $MappingPath -PathType Leaf)) {
        throw "Mapping file not found: $MappingPath"
    }

    $Map = @{}
    $RowIndex = 0

    Import-Csv -Path $MappingPath -Delimiter $Delimiter |
        ForEach-Object {
            $RowIndex++

            # Accept either explicit columns (From/To or Source/Target) or fallback to the first 2 columns.
            $From = $null
            $To   = $null

            if ($_.PSObject.Properties.Name -contains 'From' -and $_.PSObject.Properties.Name -contains 'To') {
                $From = $_.From
                $To   = $_.To
            }
            elseif ($_.PSObject.Properties.Name -contains 'Source' -and $_.PSObject.Properties.Name -contains 'Target') {
                $From = $_.Source
                $To   = $_.Target
            }
            else {
                $PropertyNames = @($_.PSObject.Properties.Name)
                if ($PropertyNames.Count -ge 2) {
                    $From = $_.$($PropertyNames[0])
                    $To   = $_.$($PropertyNames[1])
                }
            }

            if ([string]::IsNullOrWhiteSpace($From) -or [string]::IsNullOrWhiteSpace($To)) {
                Write-Warning "mapping.csv: ignoring invalid row #$RowIndex (missing From/To)."
                return
            }

            # Last one wins if duplicates.
            $Map[$From] = $To
        }

    return $Map
}

function Convert-RowWithHeaderMapping {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Row,

        [Parameter(Mandatory = $true)]
        [hashtable]$HeaderMap
    )

    $Out = [ordered]@{}
    foreach ($Prop in $Row.PSObject.Properties) {
        $OldName = $Prop.Name
        $NewName = $OldName

        if ($HeaderMap.ContainsKey($OldName)) {
            $NewName = [string]$HeaderMap[$OldName]
        }

        # If mapping creates collisions, keep the first and warn once per collision occurrence.
        if ($Out.Contains($NewName)) {
            Write-Warning "Header collision after mapping: '$OldName' -> '$NewName' already exists. Keeping first value."
            continue
        }

        $Out[$NewName] = $Prop.Value
    }

    return [pscustomobject]$Out
}

try {
    $ProjectRoot = Resolve-ProjectRoot -ProjectRootPath $ProjectRootPath

    $ConfigPath  = Join-Path $ProjectRoot 'config\settings.json'
    $Settings    = Get-Settings -ConfigPath $ConfigPath
    $Delimiter   = Get-DelimiterChar -Settings $Settings

    # Allow config override; otherwise default to conventional folders under project root.
    $InputPath  = if ([string]::IsNullOrWhiteSpace($Settings.InputFolder))  { Join-Path $ProjectRoot 'Input' }  else { Join-Path $ProjectRoot $Settings.InputFolder }
    $OutputPath = if ([string]::IsNullOrWhiteSpace($Settings.OutputFolder)) { Join-Path $ProjectRoot 'Output' } else { Join-Path $ProjectRoot $Settings.OutputFolder }

    Assert-FolderExists -Path $InputPath  -Label 'Input'
    Assert-FolderExists -Path $OutputPath -Label 'Output'

    $MappingPath = if ([string]::IsNullOrWhiteSpace($Settings.MappingFile)) { Join-Path $ProjectRoot 'config\mapping.csv' } else { Join-Path $ProjectRoot $Settings.MappingFile }
    $HeaderMap   = Import-MappingAsHashtable -MappingPath $MappingPath -Delimiter $Delimiter

    Write-Verbose "Config loaded: $ConfigPath"
    Write-Verbose "Input : $InputPath"
    Write-Verbose "Output: $OutputPath"
    Write-Verbose "Mapping: $MappingPath (entries: $($HeaderMap.Count))"
    Write-Verbose "Delimiter: '$Delimiter'"

    $InputFiles = @(Get-ChildItem -Path $InputPath -Filter '*.csv' -File)

    if ($InputFiles.Count -eq 0) {
        Write-Warning "No CSV files found in Input folder: $InputPath"
        return
    }

    foreach ($File in $InputFiles) {
        $InputFilePath = $File.FullName
        $OutputFilePath = Join-Path $OutputPath $File.Name
        $TempOutputPath = Join-Path $OutputPath ($File.BaseName + '.tmp' + $File.Extension)

        Write-Verbose "Processing: $InputFilePath -> $OutputFilePath"

        try {
            if (Test-Path -Path $TempOutputPath -PathType Leaf) {
                Remove-Item -Path $TempOutputPath -Force
            }

            Import-Csv -Path $InputFilePath -Delimiter $Delimiter |
                ForEach-Object {
                    Convert-RowWithHeaderMapping -Row $_ -HeaderMap $HeaderMap
                } |
                Export-Csv -Path $TempOutputPath -Delimiter $Delimiter -NoTypeInformation -Encoding UTF8

            if (Test-Path -Path $OutputFilePath -PathType Leaf) {
                Remove-Item -Path $OutputFilePath -Force
            }

            Move-Item -Path $TempOutputPath -Destination $OutputFilePath -Force
            Write-Verbose "Done: $OutputFilePath"
        }
        catch {
            Write-Warning "Failed processing file '$InputFilePath'. Details: $($_.Exception.Message)"

            if (Test-Path -Path $TempOutputPath -PathType Leaf) {
                Remove-Item -Path $TempOutputPath -Force
            }

            throw
        }
    }
}
catch {
    Write-Error "Engine failed: $($_.Exception.Message)"
    throw
}
