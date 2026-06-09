# =============================================================================
# Refresh automático del modelo semántico SSAS Tabular
#
# Uso:
#   .\scripts\refresh_ssas.ps1
#
# Qué hace:
#   1. Conecta al servidor SSAS (localhost\TABULAR).
#   2. Ejecuta el script XMLA de Process Full sobre Northwind_Semantico.
#   3. Loguea inicio/fin/error con timestamp.
#
# Cómo programarlo (producción):
#   Ver: docs/AUTOMATIZACION_REFRESH.md
#
# Prerrequisitos (una sola vez):
#   PowerShell como Administrador:
#       Install-Module -Name SqlServer -Force -AllowClobber
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Configuración ---
$ServerName  = "localhost\TABULAR"
$DatabaseName = "Northwind_Semantico"
$ScriptPath  = Join-Path $PSScriptRoot "..\ssas\02_procesar_modelo.xmla"
$LogPath     = Join-Path $PSScriptRoot "..\logs\ssas_refresh.log"

# --- Asegurar carpeta de logs ---
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# --- Función de log ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

# --- Verificar módulo SqlServer ---
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Log "Modulo SqlServer no instalado. Instalando..." "WARN"
    try {
        Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
        Write-Log "Modulo SqlServer instalado OK." "INFO"
    } catch {
        Write-Log "Fallo al instalar modulo SqlServer: $_" "ERROR"
        exit 1
    }
}

Import-Module SqlServer

# --- Ejecutar refresh ---
Write-Log "===== Iniciando refresh =====" "INFO"
Write-Log "Servidor: $ServerName" "INFO"
Write-Log "Base de datos: $DatabaseName" "INFO"
Write-Log "Script: $ScriptPath" "INFO"

$startTime = Get-Date

try {
    if (-not (Test-Path $ScriptPath)) {
        throw "No se encuentra el archivo XMLA en $ScriptPath"
    }

    Invoke-ASCmd `
        -Server $ServerName `
        -InputFile $ScriptPath `
        -ErrorAction Stop | Out-Null

    $duration = (Get-Date) - $startTime
    Write-Log "Refresh completado en $($duration.TotalSeconds) segundos." "INFO"
    Write-Log "===== Fin refresh OK =====" "INFO"
    exit 0

} catch {
    $duration = (Get-Date) - $startTime
    Write-Log "ERROR despues de $($duration.TotalSeconds)s : $_" "ERROR"
    Write-Log "===== Fin refresh CON FALLO =====" "ERROR"
    exit 1
}
