# =============================================================================
# Watcher de triggers de NiFi para refresh automático del SSAS
#
# Estrategia: polling cada 1 segundo (más robusto que FileSystemWatcher en
# scripts long-running ejecutados desde Task Scheduler).
#
# Uso:
#   .\scripts\watch_and_refresh.ps1
#
# Qué hace (loop infinito):
#   1. Cada 1 segundo, busca archivos *.flag en nifi-triggers\
#   2. Si hay alguno: espera 1 seg más (por si NiFi sigue escribiendo)
#   3. Ejecuta refresh_ssas.ps1
#   4. Borra el flag
#   5. Vuelve a esperar
#
# Cómo programarlo en Task Scheduler:
#   Trigger: "Al iniciar el sistema"
#   Acción:  powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File
#            "C:\Users\crist\...\PROYECTOBD\scripts\watch_and_refresh.ps1"
#   Marcar "Ejecutar tanto si el usuario está conectado como si no".
# =============================================================================

$ErrorActionPreference = "Continue"

# --- Rutas ---
$WatchPath     = Join-Path $PSScriptRoot "..\nifi-triggers"
$WatchPath     = (Resolve-Path $WatchPath).Path
$RefreshScript = Join-Path $PSScriptRoot "refresh_ssas.ps1"
$LogDir        = Join-Path $PSScriptRoot "..\logs"
$LogPath       = Join-Path $LogDir "watcher.log"

# --- Asegurar carpetas ---
foreach ($dir in @($WatchPath, $LogDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Logger ---
function Write-WatcherLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try { Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue } catch {}
    Write-Host $line
}

Write-WatcherLog "===== Watcher arrancado (polling cada 1s) ====="
Write-WatcherLog "Carpeta vigilada: $WatchPath"
Write-WatcherLog "Refresh script:   $RefreshScript"

# --- Loop principal de polling ---
while ($true) {
    try {
        $flags = Get-ChildItem -Path $WatchPath -Filter "*.flag" -File -ErrorAction SilentlyContinue

        if ($flags) {
            foreach ($flag in $flags) {
                Write-WatcherLog "Trigger detectado: $($flag.Name)"

                # Pequeña espera por si NiFi todavía está escribiendo el archivo
                Start-Sleep -Milliseconds 500

                Write-WatcherLog "Disparando refresh_ssas.ps1..."
                $process = Start-Process -FilePath "powershell.exe" `
                    -ArgumentList @("-ExecutionPolicy", "Bypass", "-File", $RefreshScript) `
                    -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    Write-WatcherLog "Refresh OK (exit code 0)."
                } else {
                    Write-WatcherLog "Refresh FALLO (exit code $($process.ExitCode))." "ERROR"
                }

                # Borrar el flag
                try {
                    Remove-Item -Path $flag.FullName -Force -ErrorAction Stop
                    Write-WatcherLog "Flag borrado: $($flag.Name)"
                } catch {
                    Write-WatcherLog "No se pudo borrar el flag $($flag.Name): $_" "WARN"
                }
            }
        }
    } catch {
        Write-WatcherLog "Excepcion en loop: $_" "ERROR"
    }

    Start-Sleep -Seconds 1
}
