# =============================================================================
# Proyecto BI Northwind — bootstrap de contenedores
# Uso (desde la raíz del proyecto):
#     .\scripts\setup_containers.ps1
#
# Qué hace:
#   1. Verifica que Docker está corriendo.
#   2. Descarga los drivers JDBC a nifi\drivers\ (solo si faltan).
#   3. Hace docker compose pull para asegurar imágenes al día.
#   4. Levanta los 4 contenedores en segundo plano.
#   5. Espera a que cada servicio responda y muestra el estado final.
#
# NO hace:
#   - Instalar Docker, DBeaver, Tableau, SSAS, Visual Studio.
#     Eso queda a tu cargo según FASE_00.
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Versiones de los drivers ------------------------------------------------
$MssqlJdbcVersion       = "12.8.1"
$MssqlJdbcUrl           = "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/$MssqlJdbcVersion.jre11/mssql-jdbc-$MssqlJdbcVersion.jre11.jar"
$MssqlJdbcFile          = "mssql-jdbc-$MssqlJdbcVersion.jre11.jar"

$MysqlConnectorVersion  = "8.4.0"
$MysqlConnectorUrl      = "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/$MysqlConnectorVersion/mysql-connector-j-$MysqlConnectorVersion.jar"
$MysqlConnectorFile     = "mysql-connector-j-$MysqlConnectorVersion.jar"

$DriversDir = Join-Path $PSScriptRoot "..\nifi\drivers"

Write-Host "==> Proyecto BI Northwind - setup de contenedores" -ForegroundColor Cyan
Write-Host ""

# --- 1. Verificar Docker -----------------------------------------------------
Write-Host "[1/5] Verificando Docker..." -ForegroundColor Yellow
try {
    docker info | Out-Null
    Write-Host "      Docker OK." -ForegroundColor Green
} catch {
    Write-Host "      ERROR: Docker no responde. Abre Docker Desktop y reintenta." -ForegroundColor Red
    exit 1
}

# --- 2. Descargar drivers JDBC ----------------------------------------------
Write-Host ""
Write-Host "[2/5] Verificando drivers JDBC en $DriversDir ..." -ForegroundColor Yellow

if (-not (Test-Path $DriversDir)) {
    New-Item -ItemType Directory -Path $DriversDir -Force | Out-Null
}

$MssqlPath  = Join-Path $DriversDir $MssqlJdbcFile
$MysqlPath  = Join-Path $DriversDir $MysqlConnectorFile

if (Test-Path $MssqlPath) {
    Write-Host "      $MssqlJdbcFile ya existe, salto descarga." -ForegroundColor Green
} else {
    Write-Host "      Descargando $MssqlJdbcFile ..."
    Invoke-WebRequest -Uri $MssqlJdbcUrl -OutFile $MssqlPath
    Write-Host "      OK." -ForegroundColor Green
}

if (Test-Path $MysqlPath) {
    Write-Host "      $MysqlConnectorFile ya existe, salto descarga." -ForegroundColor Green
} else {
    Write-Host "      Descargando $MysqlConnectorFile ..."
    Invoke-WebRequest -Uri $MysqlConnectorUrl -OutFile $MysqlPath
    Write-Host "      OK." -ForegroundColor Green
}

# --- 3. Pull de imágenes ----------------------------------------------------
Write-Host ""
Write-Host "[3/5] docker compose pull (puede tardar la primera vez)..." -ForegroundColor Yellow
docker compose pull

# --- 4. Levantar contenedores -----------------------------------------------
Write-Host ""
Write-Host "[4/5] docker compose up -d ..." -ForegroundColor Yellow
docker compose up -d

# --- 5. Esperar y mostrar estado --------------------------------------------
Write-Host ""
Write-Host "[5/5] Esperando 30s para que los servicios inicialicen..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host ""
Write-Host "==> Estado de los contenedores:" -ForegroundColor Cyan
docker ps --filter "name=source_sqlserver" --filter "name=staging_mysql" --filter "name=dw_mysql" --filter "name=nifi" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "==> Listo. Endpoints:" -ForegroundColor Cyan
Write-Host "    SQL Server : localhost:1433  (sa / Northwind2026!)"
Write-Host "    MySQL Stg  : localhost:3307  (root / Northwind2026!)"
Write-Host "    MySQL DW   : localhost:3306  (root / Northwind2026!)"
Write-Host "    NiFi UI    : https://localhost:8443/nifi  (admin / NifiAdmin2026!)"
Write-Host ""
Write-Host "    NiFi tarda 2-3 min adicionales en estar listo tras 'docker ps'."
Write-Host "    Si el navegador advierte cert. autofirmado, acepta y continúa."
