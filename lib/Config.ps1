<#
.SYNOPSIS
    Configuration helper module for SimGolf facility management

.DESCRIPTION
    Provides Get-SimGolfConfig function that merges shared and bay-specific
    configuration from JSON files.

    Configuration is loaded from:
    1. config/shared.json - Settings that apply to all bays
    2. config/bays.json - Bay-specific overrides keyed by hostname

    Bay-specific settings override shared settings.

.EXAMPLE
    . "$PSScriptRoot\..\lib\Config.ps1"
    $config = Get-SimGolfConfig
    Write-Host "Logical bay: $($config.logicalBay)"
#>

function Get-SimGolfConfig {
    <#
    .SYNOPSIS
        Loads and merges shared and bay-specific configuration

    .DESCRIPTION
        Reads shared.json and bays.json, merges them with bay-specific
        settings overriding shared settings. Returns a merged config object.

    .OUTPUTS
        PSCustomObject - Merged configuration object

    .EXAMPLE
        $config = Get-SimGolfConfig
        Write-Host "Repository path: $($config.repoPath)"
    #>

    [CmdletBinding()]
    param()

    # Determine config directory path relative to this script
    # This script is in lib/, config is in config/
    $scriptRoot = $PSScriptRoot
    $repoRoot = Split-Path $scriptRoot -Parent
    $configDir = Join-Path $repoRoot "config"

    $sharedConfigPath = Join-Path $configDir "shared.json"
    $baysConfigPath = Join-Path $configDir "bays.json"

    # Initialize empty config object
    $config = [PSCustomObject]@{}

    # Load shared config
    if (Test-Path $sharedConfigPath) {
        try {
            $sharedJson = Get-Content $sharedConfigPath -Raw | ConvertFrom-Json
            Write-Verbose "Loaded shared config from: $sharedConfigPath"

            # Copy all properties from shared config
            $sharedJson.PSObject.Properties | ForEach-Object {
                $config | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
            }
        } catch {
            Write-Warning "Failed to load shared config from $sharedConfigPath : $_"
        }
    } else {
        Write-Warning "Shared config not found at: $sharedConfigPath"
    }

    # Load bay-specific config
    if (Test-Path $baysConfigPath) {
        try {
            $baysJson = Get-Content $baysConfigPath -Raw | ConvertFrom-Json
            $hostname = $env:COMPUTERNAME

            Write-Verbose "Looking for bay config for hostname: $hostname"

            # Check if this hostname has a specific config
            $bayConfig = $baysJson.PSObject.Properties | Where-Object { $_.Name -eq $hostname } | Select-Object -First 1

            if ($bayConfig) {
                Write-Verbose "Found bay-specific config for: $hostname"

                # Merge bay-specific settings (override shared settings)
                $bayConfig.Value.PSObject.Properties | ForEach-Object {
                    # If property exists, overwrite it; otherwise add it
                    if ($config.PSObject.Properties.Name -contains $_.Name) {
                        $config.($_.Name) = $_.Value
                        Write-Verbose "  Override: $($_.Name) = $($_.Value)"
                    } else {
                        $config | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
                        Write-Verbose "  Added: $($_.Name) = $($_.Value)"
                    }
                }
            } else {
                Write-Verbose "No bay-specific config found for hostname: $hostname (using shared config only)"
            }
        } catch {
            Write-Warning "Failed to load bays config from $baysConfigPath : $_"
        }
    } else {
        Write-Warning "Bays config not found at: $baysConfigPath"
    }

    # Add computed properties
    $config | Add-Member -NotePropertyName "_hostname" -NotePropertyValue $env:COMPUTERNAME -Force
    $config | Add-Member -NotePropertyName "_loadedAt" -NotePropertyValue (Get-Date) -Force

    return $config
}

function Test-SimGolfConfig {
    <#
    .SYNOPSIS
        Tests and displays the current configuration

    .DESCRIPTION
        Loads the config and displays all properties. Useful for debugging.

    .EXAMPLE
        Test-SimGolfConfig
    #>

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  SimGolf Configuration Test" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    $config = Get-SimGolfConfig

    Write-Host "Hostname: $env:COMPUTERNAME" -ForegroundColor Green
    Write-Host ""
    Write-Host "Configuration Properties:" -ForegroundColor Yellow
    Write-Host ""

    $config.PSObject.Properties | Sort-Object Name | ForEach-Object {
        $name = $_.Name
        $value = $_.Value

        # Format value for display
        if ($value -is [string]) {
            $displayValue = "`"$value`""
        } elseif ($value -is [bool]) {
            $displayValue = $value.ToString().ToLower()
        } elseif ($null -eq $value) {
            $displayValue = "null"
        } else {
            $displayValue = $value.ToString()
        }

        Write-Host "  $name : " -NoNewline -ForegroundColor Cyan
        Write-Host $displayValue -ForegroundColor White
    }

    Write-Host ""
}

# Export functions
Export-ModuleMember -Function Get-SimGolfConfig, Test-SimGolfConfig
