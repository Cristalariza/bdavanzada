# =============================================================================
# Proyecto BI Northwind — bootstrap de contenedores
# Uso:
#   .\scripts\setup_containers.ps1            # arranque normal
#   .\scripts\setup_containers.ps1 -Reset     # borra volúmenes MySQL corruptos
#                                             # (usa esto si MySQL queda en loop)
#
# Qué hace:
#   1. Verifica Docker.
#   2. Valida docker-compose.yml.
#   3. Descarga drivers JDBC a nifi\drivers\ (solo si faltan).
#   4. (Opcional con -Reset) recrea volúmenes de MySQL.
#   5. docker compose pull (con progreso visible).
#   6. docker compose up -d y espera a que MySQL responda.
#
# NO hace:
#   - Instalar Docker, DBeaver, Tableau, SSAS, Visual Studio.
# =============================================================================

$ErrorActionPreference = "Stop"

# Posicionarse en la raíz del proyecto sin importar desde dónde se llame.
Push-Location (Join-Path $PSScriptRoot "..")

try {
    # --- Versiones de los drivers ---------------------------------------------
    $MssqlJdbcVersion      = "12.8.1"
    $MssqlJdbcFile         = "mssql-jdbc-$MssqlJdbcVersion.jre11.jar"
    $MssqlJdbcUrl          = "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/$MssqlJdbcVersion.jre11/$MssqlJdbcFile"

    $MysqlConnectorVersion = "8.4.0"
    $MysqlConnectorFile    = "mysql-connector-j-$MysqlConnectorVersion.jar"
    $MysqlConnectorUrl     = "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/$MysqlConnectorVersion/$MysqlConnectorFile"

    $DriversDir = "nifi\drivers"

    # --- Flag opcional --------------------------------------------------------
    $Reset = $args -contains "-Reset"

    Write-Host "==> Proyecto BI Northwind - setup de contenedores" -ForegroundColor Cyan
    Write-Host "    Carpeta de trabajo: $(Get-Location)"
    if ($Reset) {
        Write-Host "    MODO RESET: se recrearán los volúmenes de los dos MySQL." -ForegroundColor Yellow
    }
    Write-Host ""

    # --- 1. Verificar Docker --------------------------------------------------
    Write-Host "[1/6] Verificando Docker..." -ForegroundColor Yellow
    $dockerInfo = docker info 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Docker no responde. Abre Docker Desktop, espera a 'Engine running' y reintenta."
    }
    Write-Host "      Docker OK." -ForegroundColor Green

    # --- 2. Validar compose ---------------------------------------------------
    Write-Host ""
    Write-Host "[2/6] Validando docker-compose.yml..." -ForegroundColor Yellow
    docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw "docker-compose.yml inválido." }
    Write-Host "      Compose OK." -ForegroundColor Green

    # --- 3. Descargar drivers JDBC -------------------------------------------
    Write-Host ""
    Write-Host "[3/6] Verificando drivers JDBC en $DriversDir ..." -ForegroundColor Yellow
    if (-not (Test-Path $DriversDir)) {
        New-Item -ItemType Directory -Path $DriversDir -Force | Out-Null
    }

    $MssqlPath = Join-Path $DriversDir $MssqlJdbcFile
    if (Test-Path $MssqlPath) {
        Write-Host "      $MssqlJdbcFile ya existe, salto descarga." -ForegroundColor Green
    } else {
        Write-Host "      Descargando $MssqlJdbcFile (~1.4 MB)..."
        try {
            Invoke-WebRequest -Uri $MssqlJdbcUrl -OutFile $MssqlPath -UseBasicParsing
            Write-Host "      OK." -ForegroundColor Green
        } catch {
            throw "Fallo descargando $MssqlJdbcFile : $_"
        }
    }

    $MysqlPath = Join-Path $DriversDir $MysqlConnectorFile
    if (Test-Path $MysqlPath) {
        Write-Host "      $MysqlConnectorFile ya existe, salto descarga." -ForegroundColor Green
    } else {
        Write-Host "      Descargando $MysqlConnectorFile (~2.5 MB)..."
        try {
            Invoke-WebRequest -Uri $MysqlConnectorUrl -OutFile $MysqlPath -UseBasicParsing
            Write-Host "      OK." -ForegroundColor Green
        } catch {
            throw "Fallo descargando $MysqlConnectorFile : $_"
        }
    }

    # --- 4. Reset opcional de volúmenes MySQL --------------------------------
    Write-Host ""
    if ($Reset) {
        Write-Host "[4/6] Recreando volúmenes MySQL..." -ForegroundColor Yellow
        docker compose stop staging_mysql dw_mysql 2>&1 | Out-Null
        docker compose rm -f staging_mysql dw_mysql 2>&1 | Out-Null
        docker volume rm proyectobd_staging_data proyectobd_dw_data 2>&1 | Out-Null
        Write-Host "      Volúmenes eliminados." -ForegroundColor Green
    } else {
        Write-Host "[4/6] (No reset. Si MySQL queda en loop, vuelve a correr con -Reset)" -ForegroundColor Gray
    }

    # --- 5. Pull de imágenes (con progreso visible) --------------------------
    Write-Host ""
    Write-Host "[5/6] docker compose pull..." -ForegroundColor Yellow
    Write-Host "      AVISO: la primera vez tarda 5-15 min (~3 GB total)." -ForegroundColor Yellow
    Write-Host "      No canceles aunque parezca quieto: las capas grandes (NiFi 1.5GB," -ForegroundColor Yellow
    Write-Host "      SQL Server 1.5GB) descargan en silencio." -ForegroundColor Yellow
    docker compose pull
    if ($LASTEXITCODE -ne 0) { throw "docker compose pull falló." }

    # --- 6. Up y validación de MySQL listo -----------------------------------
    Write-Host ""
    Write-Host "[6/6] Levantando contenedores..." -ForegroundColor Yellow
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw "docker compose up -d falló." }

    Write-Host ""
    Write-Host "      Esperando a que los servicios acepten conexiones..." -ForegroundColor Yellow

    # SQL Server: busca "SQL Server is now ready for client connections"
    # MySQL:      busca "ready for connections"
    # NiFi:       no se valida aquí porque tarda 2-3 min (solo se reporta al final)
    $checks = @(
        @{ Svc = "source_sqlserver"; Ready = "ready for client connections"; Bad = "Login failed for user" },
        @{ Svc = "staging_mysql";    Ready = "ready for connections";        Bad = "Cannot create redo log files|Aborting" },
        @{ Svc = "dw_mysql";         Ready = "ready for connections";        Bad = "Cannot create redo log files|Aborting" }
    )

    foreach ($c in $checks) {
        $svc = $c.Svc
        $ready = $false
        for ($i = 0; $i -lt 60; $i++) {
            $log = docker logs $svc --tail 20 2>&1 | Out-String
            if ($log -match $c.Ready) {
                Write-Host "      $svc OK." -ForegroundColor Green
                $ready = $true
                break
            }
            if ($log -match $c.Bad) {
                Write-Host ""
                if ($svc -like "*mysql*") {
                    Write-Host "      $svc FALLA: volumen corrupto de un intento anterior." -ForegroundColor Red
                    Write-Host "      Solución: vuelve a correr así:" -ForegroundColor Red
                    Write-Host "          .\scripts\setup_containers.ps1 -Reset" -ForegroundColor Red
                } else {
                    Write-Host "      $svc FALLA: revisa el log con 'docker logs $svc'." -ForegroundColor Red
                }
                throw "$svc no pudo arrancar."
            }
            Start-Sleep -Seconds 2
        }
        if (-not $ready) {
            Write-Host "      $svc tardó >2 min en estar listo. Revisa: docker logs $svc" -ForegroundColor Red
        }
    }

    # --- Estado final ---------------------------------------------------------
    Write-Host ""
    Write-Host "==> Estado de los contenedores:" -ForegroundColor Cyan
    docker ps `
        --filter "name=source_sqlserver" `
        --filter "name=staging_mysql" `
        --filter "name=dw_mysql" `
        --filter "name=nifi" `
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    Write-Host ""
    Write-Host "==> Endpoints:" -ForegroundColor Cyan
    Write-Host "    SQL Server : localhost:14333 (sa / Northwind2026!)"
    Write-Host "    MySQL Stg  : localhost:3307  (root / Northwind2026!)"
    Write-Host "    MySQL DW   : localhost:3306  (root / Northwind2026!)"
    Write-Host "    NiFi UI    : https://localhost:8443/nifi  (admin / NifiAdmin2026!)"
    Write-Host ""
    Write-Host "    NiFi tarda 2-3 min adicionales tras 'docker ps' en estar accesible."
    Write-Host "    El navegador advertirá certificado autofirmado; acepta y continúa."

} finally {
    Pop-Location
}
