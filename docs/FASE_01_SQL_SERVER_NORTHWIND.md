# Fase 1 — Servidor 1: SQL Server + Northwind

**Objetivo:** levantar el contenedor de SQL Server 2022 (Servidor 1 / fuente OLTP) y cargar la base **Northwind** original de Microsoft.
**Tiempo estimado:** 1 hora.
**Prerrequisitos:** Fase 0 completada (Docker funcionando, `instnwnd.sql` descargado, DBeaver instalado).

---

## Paso 1 — Crear el `docker-compose.yml` inicial

1.1. Abre el archivo `C:\Users\<TU_USUARIO>\OneDrive\Pictures\Desktop\PROYECTOBD\docker-compose.yml` en un editor de texto (VS Code, Notepad++, o el que prefieras).
1.2. Escribe **exactamente** este contenido (todavía solo SQL Server; en la Fase 2 agregaremos los MySQL):

```yaml
services:
  source_sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: source_sqlserver
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "Northwind2026!"
      MSSQL_PID: "Developer"
    ports:
      - "1433:1433"
    volumes:
      - sqlserver_data:/var/opt/mssql
    restart: unless-stopped

volumes:
  sqlserver_data:
```

1.3. Guarda el archivo. Verifica que la **indentación** sea con espacios (2 espacios), no tabs. YAML es estricto con esto.

> **¿Por qué esta configuración?**
> - `image:` la imagen oficial Microsoft, versión 2022 Linux.
> - `ACCEPT_EULA`: obligatorio, sino el contenedor no arranca.
> - `MSSQL_SA_PASSWORD`: tu contraseña del usuario `sa`. Debe cumplir la política de SQL Server (8+ caracteres, mayúscula, minúscula, número, símbolo). `Northwind2026!` cumple.
> - `MSSQL_PID: "Developer"`: edición gratuita para desarrollo, todas las features de Enterprise.
> - `volumes:` volumen **nombrado** `sqlserver_data` para que los datos sobrevivan a `docker compose down`.
> - `restart: unless-stopped`: se levanta solo al reiniciar Docker, salvo que tú lo apagues.

---

## Paso 2 — Levantar el contenedor

2.1. Abre PowerShell y navega a la carpeta del proyecto:
```powershell
cd C:\Users\<TU_USUARIO>\OneDrive\Pictures\Desktop\PROYECTOBD
```
2.2. Ejecuta:
```powershell
docker compose up -d
```
2.3. Espera 30-60 segundos. La primera vez descarga la imagen (~1.5 GB).
2.4. Verifica que está corriendo:
```powershell
docker ps
```
Debes ver una línea con `source_sqlserver` en estado `Up X seconds`.
2.5. Mira los logs por si hay errores:
```powershell
docker logs source_sqlserver
```
La última línea útil debe ser algo como `SQL Server is now ready for client connections`.
2.6. **CAPTURA:** la salida de `docker ps`.

---

## Paso 3 — Conectarse desde DBeaver

3.1. Abre DBeaver.
3.2. **Database → New Database Connection** → busca y selecciona **SQL Server** → Next.
3.3. Llena:
   - **Server Host:** `localhost`
   - **Port:** `1433`
   - **Database/Schema:** déjalo vacío por ahora
   - **Authentication:** `SQL Server Authentication`
   - **Username:** `sa`
   - **Password:** `Northwind2026!`
3.4. En la pestaña **Driver properties**, agrega:
   - `encrypt` = `false`
   - `trustServerCertificate` = `true`
   (esto evita errores de certificado en conexiones locales)
3.5. Clic en **Test Connection**. Si pide descargar el driver `jTDS` o `Microsoft JDBC Driver`, acepta — DBeaver lo descarga solo.
3.6. Debe aparecer "Connected" en verde. Clic en **Finish**.
3.7. **CAPTURA:** la pantalla de "Connected".

---

## Paso 4 — Crear la base Northwind vacía

El script `instnwnd.sql` asume que se ejecuta sobre la base `master` y él mismo crea la base `Northwind`. Hay que prepararlo.

4.1. En DBeaver, expande la conexión → carpeta **Databases** → confirma que existen `master`, `model`, `msdb`, `tempdb`. **NO debe existir** `Northwind` todavía.
4.2. Doble clic en `master` → se vuelve activa (en negrita).
4.3. Abre el script: **SQL Editor → Open SQL Script** → selecciona `C:\...\PROYECTOBD\sql\instnwnd.sql`.
4.4. **Antes de ejecutar**: revisa que las primeras líneas hagan `CREATE DATABASE Northwind` y luego `USE Northwind`. Si el script comienza con `USE [Northwind]` y NO con `CREATE DATABASE`, primero ejecuta manualmente:
   ```sql
   CREATE DATABASE Northwind;
   GO
   ```
   y guárdalo como costumbre para el documento.

---

## Paso 5 — Ejecutar `instnwnd.sql`

5.1. Con el script abierto en DBeaver, presiona **Alt+X** (Execute SQL Script) o el botón "Execute SQL Script" (no "Execute SQL statement").
5.2. DBeaver puede preguntar "execute statements?". Confirma.
5.3. Espera 20-40 segundos. El log inferior mostrará "X statements executed".
5.4. Si hay errores rojos, **léelos**:
   - Si dice "database already exists" — está bien, ignora.
   - Si dice "Cannot find the object Customers" — el `USE Northwind` no aplicó; selecciona `Northwind` como base activa y reintenta.
   - Si dice "Login failed" — la conexión se cayó; reconéctate.
5.5. **CAPTURA:** la salida del execute con los conteos.

---

## Paso 6 — Validar la carga de Northwind

6.1. Selecciona la base `Northwind` (doble clic) — debe ponerse en negrita.
6.2. Abre un **SQL Editor nuevo** (Ctrl+Alt+Enter) y ejecuta una a una estas consultas (Ctrl+Enter para cada una):

```sql
SELECT COUNT(*) AS total FROM Customers;        -- esperado: 91
SELECT COUNT(*) AS total FROM Orders;           -- esperado: 830
SELECT COUNT(*) AS total FROM [Order Details];  -- esperado: 2155
SELECT COUNT(*) AS total FROM Products;         -- esperado: 77
SELECT COUNT(*) AS total FROM Categories;       -- esperado: 8
SELECT COUNT(*) AS total FROM Suppliers;        -- esperado: 29
SELECT COUNT(*) AS total FROM Employees;        -- esperado: 9
SELECT COUNT(*) AS total FROM Shippers;         -- esperado: 3
```

> Si algún conteo no coincide, el script no terminó de aplicar. Borra la base (`DROP DATABASE Northwind`), reconéctate al `master` y vuelve a ejecutar `instnwnd.sql`.

6.3. Ejecuta una consulta de inspección de fechas (para el alcance del documento):
```sql
SELECT
    MIN(OrderDate) AS fecha_min,
    MAX(OrderDate) AS fecha_max,
    COUNT(DISTINCT YEAR(OrderDate)) AS anios_distintos
FROM Orders;
```
Debe darte algo como `1996-07-04`, `1998-05-06`, `3` años.

6.4. **CAPTURA:** las 8 consultas de conteo + la de fechas, cada una con su resultado.

---

## Paso 7 — Crear el usuario de lectura para NiFi (buena práctica)

NiFi no debe conectarse con `sa`. Creamos un usuario `nifi_reader` con solo permiso de lectura sobre `Northwind`.

7.1. En DBeaver, sobre la base `master`, ejecuta (uno a uno con Ctrl+Enter):

```sql
CREATE LOGIN nifi_reader WITH PASSWORD = 'NifiReader2026!';
GO
```

7.2. Cambia a `Northwind` (doble clic en la base) y ejecuta:

```sql
CREATE USER nifi_reader FOR LOGIN nifi_reader;
GO
ALTER ROLE db_datareader ADD MEMBER nifi_reader;
GO
```

7.3. Valida desconectándote y reconectando con `nifi_reader` / `NifiReader2026!`. Debe poder hacer `SELECT * FROM Customers` pero NO `INSERT`.

7.4. **CAPTURA:** prueba el login `nifi_reader` con un SELECT y un INSERT bloqueado.

---

## Paso 8 — Documentar la fuente (tabla de inventario)

Apunta en una nota para la sección 2 del documento principal:

- **Motor:** Microsoft SQL Server 2022 Developer Edition (Linux container).
- **Host:** `localhost:1433`
- **Base de datos:** `Northwind`
- **Schema:** `dbo`
- **Periodo:** 1996-07-04 a 1998-05-06.
- **Tablas usadas:** Customers (91), Orders (830), Order Details (2155), Products (77), Categories (8), Suppliers (29), Employees (9), Shippers (3).
- **Usuario de extracción ETL:** `nifi_reader` (solo lectura).

---

## Checklist de cierre de la Fase 1

- [ ] `docker-compose.yml` con el servicio `source_sqlserver` creado y commiteable
- [ ] `docker ps` muestra `source_sqlserver` en estado `Up`
- [ ] DBeaver conecta a `localhost:1433` con `sa`
- [ ] Base `Northwind` creada con las 8 tablas
- [ ] Los 8 conteos coinciden con los esperados
- [ ] Usuario `nifi_reader` creado, autenticado, con permisos solo de lectura
- [ ] Capturas guardadas en `capturas\01\` (mínimo 5)

Cuando esté listo, dime **"Fase 1 lista"** y pasamos a la Fase 2.
