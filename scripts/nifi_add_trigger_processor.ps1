# =============================================================================
# Agregar PutFile "Trigger SSAS Refresh" al final del Pipeline 2 vía REST API.
#
# Lo que hace:
#   1. Autentica contra NiFi con admin/NifiAdmin2026!
#   2. Encuentra el Process Group "Pipeline 2 - Staging a DW"
#   3. Encuentra el procesador "LOAD fact_ventas + dim_metas"
#   4. Crea un nuevo PutFile con la config necesaria
#   5. Crea la conexión LOAD → PutFile (relación success)
#   6. Inicia el PutFile
# =============================================================================

$ErrorActionPreference = "Stop"

# Aceptar certificado autofirmado de NiFi
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$NiFiBase = "https://localhost:8443/nifi-api"
$Username = "admin"
$Password = "NifiAdmin2026!"

function Write-Step($msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# --- 1. Login y obtener token JWT ---
Write-Step "Autenticando..."
$tokenBody = "username=$Username&password=$Password"
$token = Invoke-RestMethod -Uri "$NiFiBase/access/token" `
    -Method Post `
    -Body $tokenBody `
    -ContentType "application/x-www-form-urlencoded"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}
Write-Host "    Token OK"

# --- 2. Encontrar el root Process Group y luego Pipeline 2 ---
Write-Step "Buscando Process Group 'Pipeline 2 - Staging a DW'..."
$rootPG = Invoke-RestMethod -Uri "$NiFiBase/flow/process-groups/root" -Headers $headers
$rootId = $rootPG.processGroupFlow.id

$children = $rootPG.processGroupFlow.flow.processGroups
$pipeline2 = $children | Where-Object { $_.component.name -like "*Pipeline 2*" -or $_.component.name -like "*Staging a DW*" }

if (-not $pipeline2) {
    Write-Host "ERROR: No se encontro Pipeline 2 entre los hijos del root." -ForegroundColor Red
    Write-Host "Hijos encontrados:"
    $children | ForEach-Object { Write-Host "  - $($_.component.name)" }
    exit 1
}

$pipeline2Id = $pipeline2.id
Write-Host "    Pipeline 2 ID: $pipeline2Id"

# --- 3. Encontrar el procesador "LOAD fact_ventas + dim_metas" ---
Write-Step "Buscando procesador 'LOAD fact_ventas + dim_metas'..."
$pg2Flow = Invoke-RestMethod -Uri "$NiFiBase/flow/process-groups/$pipeline2Id" -Headers $headers
$processors = $pg2Flow.processGroupFlow.flow.processors

$loadProc = $processors | Where-Object { $_.component.name -like "*LOAD fact_ventas*" -or $_.component.name -like "*fact_ventas + dim_metas*" }

if (-not $loadProc) {
    Write-Host "ERROR: No se encontro 'LOAD fact_ventas + dim_metas'." -ForegroundColor Red
    Write-Host "Procesadores encontrados:"
    $processors | ForEach-Object { Write-Host "  - $($_.component.name)" }
    exit 1
}

$loadProcId = $loadProc.id
$loadPos    = $loadProc.position
Write-Host "    LOAD fact_ventas ID: $loadProcId"
Write-Host "    Posicion: x=$($loadPos.x), y=$($loadPos.y)"

# --- 4. Verificar si ya existe el PutFile (para evitar duplicados) ---
$existing = $processors | Where-Object { $_.component.name -eq "Trigger SSAS Refresh" }
if ($existing) {
    Write-Host "    YA EXISTE 'Trigger SSAS Refresh' (ID: $($existing.id)). Salto creacion." -ForegroundColor Yellow
    $putFileId = $existing.id
} else {
    # --- 5. Crear el PutFile ---
    Write-Step "Creando procesador PutFile..."

    # Posicion: a la derecha del LOAD
    $newX = $loadPos.x + 400
    $newY = $loadPos.y

    $createBody = @{
        revision = @{
            clientId = [Guid]::NewGuid().ToString()
            version  = 0
        }
        component = @{
            type = "org.apache.nifi.processors.standard.PutFile"
            bundle = @{
                group    = "org.apache.nifi"
                artifact = "nifi-standard-nar"
                version  = "2.0.0"
            }
            name = "Trigger SSAS Refresh"
            position = @{
                x = $newX
                y = $newY
            }
            config = @{
                properties = @{
                    "Directory"                       = "/opt/nifi/nifi-current/triggers"
                    "Conflict Resolution Strategy"    = "replace"
                    "Create Missing Directories"      = "true"
                    "Maximum File Count"              = "-1"
                }
                autoTerminatedRelationships = @("success", "failure")
                schedulingPeriod   = "0 sec"
                schedulingStrategy = "TIMER_DRIVEN"
                executionNode      = "ALL"
                penaltyDuration    = "30 sec"
                yieldDuration      = "1 sec"
                bulletinLevel      = "WARN"
            }
        }
    } | ConvertTo-Json -Depth 10

    $newProc = Invoke-RestMethod -Uri "$NiFiBase/process-groups/$pipeline2Id/processors" `
        -Method Post `
        -Headers $headers `
        -Body $createBody

    $putFileId = $newProc.id
    Write-Host "    PutFile creado, ID: $putFileId" -ForegroundColor Green
}

# --- 6. Verificar si ya existe la conexion LOAD -> PutFile ---
Write-Step "Verificando conexiones existentes..."
$connections = $pg2Flow.processGroupFlow.flow.connections
$existingConn = $connections | Where-Object {
    $_.component.source.id -eq $loadProcId -and $_.component.destination.id -eq $putFileId
}

if ($existingConn) {
    Write-Host "    Conexion ya existe (ID: $($existingConn.id)). Salto creacion." -ForegroundColor Yellow
} else {
    Write-Step "Creando conexion LOAD -> PutFile..."

    $connBody = @{
        revision = @{
            clientId = [Guid]::NewGuid().ToString()
            version  = 0
        }
        component = @{
            name = ""
            source = @{
                id      = $loadProcId
                type    = "PROCESSOR"
                groupId = $pipeline2Id
            }
            destination = @{
                id      = $putFileId
                type    = "PROCESSOR"
                groupId = $pipeline2Id
            }
            selectedRelationships = @("success")
            backPressureObjectThreshold     = 10000
            backPressureDataSizeThreshold   = "1 GB"
            flowFileExpiration              = "0 sec"
        }
    } | ConvertTo-Json -Depth 10

    try {
        $newConn = Invoke-RestMethod -Uri "$NiFiBase/process-groups/$pipeline2Id/connections" `
            -Method Post `
            -Headers $headers `
            -Body $connBody
        Write-Host "    Conexion creada OK, ID: $($newConn.id)" -ForegroundColor Green
    } catch {
        Write-Host "    AVISO: no se pudo crear la conexion automaticamente." -ForegroundColor Yellow
        Write-Host "    Razon: $_" -ForegroundColor Yellow
        Write-Host "    LOAD fact_ventas probablemente ya tiene success auto-terminated."
        Write-Host "    Se debe desmarcar 'success' en sus Relationships y luego correr este script de nuevo."
    }
}

# --- 7. Intentar arrancar el PutFile ---
Write-Step "Arrancando PutFile..."
try {
    $putFileEntity = Invoke-RestMethod -Uri "$NiFiBase/processors/$putFileId" -Headers $headers
    $startBody = @{
        revision = $putFileEntity.revision
        state    = "RUNNING"
        disconnectedNodeAcknowledged = $false
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri "$NiFiBase/processors/$putFileId/run-status" `
        -Method Put `
        -Headers $headers `
        -Body $startBody | Out-Null
    Write-Host "    PutFile RUNNING" -ForegroundColor Green
} catch {
    Write-Host "    AVISO: no se pudo arrancar (posiblemente esta invalido todavia)." -ForegroundColor Yellow
    Write-Host "    Razon: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Listo. Verifica en NiFi UI: https://localhost:8443/nifi" -ForegroundColor Cyan
