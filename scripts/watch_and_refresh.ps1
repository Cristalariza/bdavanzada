# =============================================================================
# Watcher de triggers de NiFi para refresh automático del SSAS
#
# Uso:
#   .\scripts\watch_and_refresh.ps1
#
# Qué hace:
#   1. Monta un FileSystemWatcher sobre nifi-triggers\ (volumen Docker compartido).
#   2. Cuando NiFi (Pipeline 2) termina y deja un archivo .flag, lo detecta.
#   3. Ejecuta refresh_ssas.ps1 → procesa el modelo Northwind_Semantico.
#   4. Borra el archivo .flag y vuelve a esperar.
#
# Cómo programarlo en producción (1 sola vez):
#   Task Scheduler → Crear tarea → Trigger "Al iniciar el sistema"
#       Acción: powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File
#               "C:\Users\crist\...\PROYECTOBD\scripts\watch_and_refresh.ps1"
#   Marca "Ejecutar con permisos más altos".
#
# Cómo probarlo manualmente:
#   1. Abre PowerShell en C:\Users\crist\...\PROYECTOBD
#   2. .\scripts\watch_and_refresh.ps1
#   3. En otra ventana, simula NiFi escribiendo el .flag:
#        echo "test" > nifi-triggers\refresh-test.flag
#   4. Verifica logs\ssas_refresh.log para confirmar que se disparó.
#
# Prerrequisitos:
#   - Módulo SqlServer instalado (refresh_ssas.ps1 lo instala si falta).
#   - Servicio SSAS Tabular en estado Running.
# =============================================================================

$ErrorActionPreference = "Continue"

# --- Configuración ---
$WatchPath    = Join-Path $PSScriptRoot "..\nifi-triggers"
$WatchPath    = (Resolve-Path $WatchPath).Path
$RefreshScript = Join-Path $PSScriptRoot "refresh_ssas.ps1"
$LogPath      = Join-Path $PSScriptRoot "..\logs\watcher.log"

# --- Asegurar carpetas ---
foreach ($dir in @($WatchPath, (Split-Path $LogPath -Parent))) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Logger ---
function Write-WatcherLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

Write-WatcherLog "===== Watcher arrancado =====" "INFO"
Write-WatcherLog "Carpeta vigilada: $WatchPath" "INFO"
Write-WatcherLog "Refresh script: $RefreshScript" "INFO"

# --- Crear FileSystemWatcher ---
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchPath
$watcher.Filter = "*.flag"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

# --- Acción al detectar archivo nuevo ---
$onCreated = {
    param($sender, $eventArgs)

    # Importar funciones del script (re-declaramos locales por el scope de Register-ObjectEvent)
    $LogPath       = Join-Path (Split-Path -Parent $eventArgs.FullPath) "..\logs\watcher.log"
    $RefreshScript = Join-Path (Split-Path -Parent $eventArgs.FullPath) "..\scripts\refresh_ssas.ps1"

    function Write-WL([string]$msg, [string]$lvl = "INFO") {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogPath -Value "[$ts] [$lvl] $msg"
    }

    $flagFile = $eventArgs.FullPath
    Write-WL "Trigger detectado: $flagFile" "INFO"

    # Espera 1 segundo por si NiFi todavía está escribiendo
    Start-Sleep -Seconds 1

    try {
        Write-WL "Ejecutando $RefreshScript ..." "INFO"
        & powershell.exe -ExecutionPolicy Bypass -File $RefreshScript
        if ($LASTEXITCODE -eq 0) {
            Write-WL "Refresh OK. Borrando flag." "INFO"
        } else {
            Write-WL "Refresh FALLO (exit code $LASTEXITCODE). Borrando flag de todos modos." "ERROR"
        }
    } catch {
        Write-WL "Excepcion al ejecutar refresh: $_" "ERROR"
    } finally {
        if (Test-Path $flagFile) {
            Remove-Item -Path $flagFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Register-ObjectEvent $watcher "Created" -Action $onCreated | Out-Null

Write-WatcherLog "Watcher escuchando. Ctrl+C para detener." "INFO"

# --- Loop infinito para mantener el script vivo ---
try {
    while ($true) {
        Start-Sleep -Seconds 60
    }
} finally {
    $watcher.Dispose()
    Write-WatcherLog "===== Watcher detenido =====" "INFO"
}
