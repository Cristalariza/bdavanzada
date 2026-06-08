# Fase 3 — Apache NiFi 2.x (en Docker) + Pipeline 1 (Fuente → Staging)

**Objetivo:** acceder al NiFi 2.x que corre en el contenedor `nifi`, configurar pools de conexión y construir el **Pipeline 1**, que extrae datos crudos de SQL Server (Northwind) y los carga 1:1 al Staging MySQL.
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fases 0, 1, 2 completadas. Los 4 contenedores corriendo (`docker ps` muestra `source_sqlserver`, `staging_mysql`, `dw_mysql`, `nifi`).

> **Importante (cambio en NiFi 2.x):** los procesadores legacy `ExecuteSQL` + `ConvertAvroToJSON` están sustituidos por procesadores **record-oriented**. Usaremos `ExecuteSQLRecord` y `QueryDatabaseTableRecord`, que aceptan un *Record Writer* y producen JSON directamente. Resultado: el pipeline tiene **un procesador menos** y la conversión Avro→JSON desaparece.

---

## Paso 1 — Verificar drivers JDBC en NiFi

El script `setup_containers.ps1` de la Fase 0 ya descargó los drivers a `nifi\drivers\` y los montó dentro del contenedor en `/opt/nifi/nifi-current/extra-jars/`. Validar:

1.1. Confirma que existen los `.jar` localmente:
   ```powershell
   dir nifi\drivers
   ```
1.2. Confirma que NiFi los ve por dentro:
   ```powershell
   docker exec nifi ls -la /opt/nifi/nifi-current/extra-jars/
   ```
1.3. Si los drivers se descargaron DESPUÉS de que el contenedor arrancara, reinícialo:
   ```powershell
   docker compose restart nifi
   ```
1.4. **CAPTURA:** salida del `docker exec`.

---

## Paso 2 — Acceder a la UI de NiFi 2.x

2.1. Verifica que el contenedor esté corriendo:
   ```powershell
   docker ps --filter "name=nifi"
   ```
2.2. Mira los logs hasta ver `NiFi has started`:
   ```powershell
   docker logs nifi --tail 30
   ```
2.3. Abre el navegador en **`https://localhost:8443/nifi`** (HTTPS, certificado autofirmado).
2.4. El navegador advertirá certificado no confiable. Avanzado → "Continuar a localhost".
2.5. Pantalla de login:
   - Usuario: `admin`
   - Contraseña: `NifiAdmin2026!`
2.6. Aparece el lienzo de NiFi 2.x (UI rediseñada, barra superior con íconos y panel derecho con detalles del componente seleccionado).
2.7. **CAPTURA:** lienzo de NiFi tras login.

> **Nota de UI:** en NiFi 2.x el menú principal está en la **esquina superior derecha (☰)** y muestra: Controller Settings, Cluster, Counters, Reporting Tasks, Parameter Contexts, etc. Las "Properties" de cada procesador se editan en el panel derecho (no en un diálogo emergente como en 1.x), aunque también puedes hacer doble clic para abrir el editor en ventana.

---

## Paso 3 — Crear los 3 Controller Services (pools de conexión)

> **URLs JDBC:** como NiFi corre en el contenedor `nifi` y se conecta a los demás contenedores por la red `bi_network`, los URLs usan **nombres de servicio** (no `localhost`) y los **puertos internos**: `source_sqlserver:1433`, `staging_mysql:3306`, `dw_mysql:3306`.

3.1. Menú **☰ → Controller Settings → Controller Services**.
3.2. Clic en **+** → busca `DBCPConnectionPool` → Add.

### 3.A — Pool para SQL Server (fuente)

Doble clic sobre el servicio → pestaña **Properties**:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:sqlserver://source_sqlserver:1433;databaseName=Northwind;encrypt=false;trustServerCertificate=true` |
| Database Driver Class Name | `com.microsoft.sqlserver.jdbc.SQLServerDriver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mssql-jdbc-12.8.1.jre11.jar` |
| Database User | `nifi_reader` |
| Password | `NifiReader2026!` |
| Max Wait Time | `30 seconds` |
| Max Total Connections | `8` |

Pestaña **Settings** → Name: `SQLServer-Northwind-Reader`. Apply → habilita el servicio con el rayito ⚡ → State: **Enabled**.

### 3.B — Pool para MySQL Staging

Otro DBCPConnectionPool con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://staging_mysql:3306/staging_northwind?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mysql-connector-j-8.4.0.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

Name: `MySQL-Staging`. Habilítalo.

### 3.C — Pool para MySQL DW

Otro más con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://dw_mysql:3306/dw_northwind?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&allowMultiQueries=true` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mysql-connector-j-8.4.0.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

> Nota el `allowMultiQueries=true` — lo necesitaremos en Fase 4 para ejecutar el script de transformaciones en una sola llamada.

Name: `MySQL-DW`. Habilítalo.

3.3. **CAPTURA:** los 3 Controller Services en estado **Enabled**.

> **Si alguno NO se habilita** y da error "Driver class not found": revisa que el `.jar` esté en `nifi\drivers\` y que la ruta de "Driver Location" coincida con el nombre real del archivo. `docker compose restart nifi` si dudas.

---

## Paso 4 — Crear los 2 Record Writers/Readers (clave del enfoque NiFi 2.x)

En la misma pantalla de Controller Services, agrega dos servicios más:

### 4.A — `JsonRecordSetWriter`

Este servicio convierte los registros que devuelve la base de datos a JSON.

4.A.1. **+** → busca `JsonRecordSetWriter` → Add.
4.A.2. Properties:

| Property | Value |
|---|---|
| Schema Write Strategy | `Do Not Write Schema` |
| Schema Access Strategy | `Inherit Record Schema` |
| Pretty Print JSON | `false` |
| Suppress Null Values | `Always Suppress` |

4.A.3. Name: `JsonWriter`. Habilítalo.

### 4.B — `JsonTreeReader`

Este servicio permite leer JSON cuando llega al `PutDatabaseRecord`.

4.B.1. **+** → busca `JsonTreeReader` → Add.
4.B.2. Properties:

| Property | Value |
|---|---|
| Schema Access Strategy | `Infer Schema` |

4.B.3. Name: `JsonReader`. Habilítalo.

4.C. **CAPTURA:** ahora hay **5 Controller Services** Enabled (3 pools + Writer + Reader).

---

## Paso 5 — Crear el Process Group "Pipeline 1"

5.1. Cierra la ventana de Controller Settings.
5.2. En la barra superior del lienzo, arrastra el ícono **Process Group** al canvas.
5.3. Nombre: `Pipeline 1 - Fuente a Staging`. Add.
5.4. Doble clic sobre el grupo para entrar.

---

## Paso 6 — Subflujo: tabla `Categories` (carga completa, como plantilla)

Vamos a construir el subflujo para `Categories`. Luego lo replicas para las demás dimensiones pequeñas con copy-paste.

**Patrón del pipeline (NiFi 2.x):**

```
GenerateFlowFile → PutSQL (TRUNCATE) → ExecuteSQLRecord → PutDatabaseRecord
   (trigger)        (vacía destino)    (consulta + JSON)   (carga staging)
```

Observa que **NO hay** `ConvertAvroToJSON`. `ExecuteSQLRecord` ya produce JSON gracias al `JsonRecordSetWriter`.

### 6.A — Procesador 1: `GenerateFlowFile` (trigger manual)

6.A.1. Arrastra **Processor** desde la barra superior. Busca **GenerateFlowFile** → Add.
6.A.2. Properties:

| Property | Value |
|---|---|
| File Size | `0B` |
| Batch Size | `1` |

6.A.3. Settings:
   - Name: `Trigger Categories`
   - Scheduling tab → Run Schedule: `999 days` (lo dispararemos manualmente con "Run Once")
   - Auto-terminate Relationships: (ninguna; la salida `success` la vamos a usar)
6.A.4. Apply.

### 6.B — Procesador 2: `PutSQL` (TRUNCATE destino)

6.B.1. Arrastra **Processor** → **PutSQL** → Add.
6.B.2. Properties:

| Property | Value |
|---|---|
| JDBC Connection Pool | `MySQL-Staging` |
| SQL Statement | `TRUNCATE TABLE stg_categories` |
| Support Fragmented Transactions | `false` |

6.B.3. Settings → Name: `TRUNCATE stg_categories`. Auto-terminate: `failure`, `retry`.
6.B.4. Apply.

### 6.C — Procesador 3: `ExecuteSQLRecord` (lee de SQL Server, escribe JSON)

Este es el procesador clave del enfoque NiFi 2.x. Combina ejecutar SQL y escribir con un Record Writer.

6.C.1. Arrastra **Processor** → busca **ExecuteSQLRecord** → Add.
6.C.2. Properties:

| Property | Value |
|---|---|
| Database Connection Pooling Service | `SQLServer-Northwind-Reader` |
| Record Writer | `JsonWriter` |
| SQL select query | `SELECT CategoryID, CategoryName, CAST(Description AS NVARCHAR(MAX)) AS Description FROM Categories` |
| Max Rows Per Flow File | `0` |
| Output Batch Size | `0` |
| Normalize Table/Column Names | `false` |

6.C.3. Settings:
   - Name: `EXTRACT Categories`
   - Penalty Duration: `30 sec`
   - Yield Duration: `1 sec`
   - Auto-terminate: marca `failure`
6.C.4. Apply.

### 6.D — Procesador 4: `PutDatabaseRecord` (escribe en MySQL Staging)

6.D.1. Arrastra **Processor** → **PutDatabaseRecord** → Add.
6.D.2. Properties:

| Property | Value |
|---|---|
| Record Reader | `JsonReader` |
| Statement Type | `INSERT` |
| Database Connection Pooling Service | `MySQL-Staging` |
| Schema Name | `staging_northwind` |
| Table Name | `stg_categories` |
| Translate Field Names | `true` |
| Unmatched Field Behavior | `Ignore Unmatched Fields` |
| Unmatched Column Behavior | `Ignore Unmatched Columns` |

> **`Translate Field Names = true`** convierte `CategoryID` → `categoryid` para que matchee con la columna `CategoryID` de MySQL (insensible a mayúsculas).

6.D.3. Settings → Name: `LOAD stg_categories`. Auto-terminate: `success`, `failure`, `retry`.
6.D.4. Apply.

### 6.E — Conectar los 4 procesadores

6.E.1. Pasa el mouse sobre `Trigger Categories` → aparece una flecha → arrástrala hasta `TRUNCATE stg_categories` → relación `success` → Add.
6.E.2. De `TRUNCATE stg_categories` a `EXTRACT Categories` → `success` → Add.
6.E.3. De `EXTRACT Categories` a `LOAD stg_categories` → `success` → Add.

### 6.F — Probar

6.F.1. Selecciona los 4 procesadores con un rectángulo → clic derecho → **Start**. Quedan en estado "Running" (triángulo verde).
6.F.2. Clic derecho sobre `Trigger Categories` → **Run Once**.
6.F.3. Observa los contadores de cada procesador: deben subir a `1 (X bytes)` en "Out" / "In".
6.F.4. En DBeaver, en el Staging (`localhost:3307`):
   ```sql
   SELECT COUNT(*) FROM stg_categories;     -- esperado: 8
   SELECT * FROM stg_categories LIMIT 3;
   ```
6.F.5. **CAPTURA:** subflujo de 4 procesadores en NiFi + el SELECT en DBeaver.

> **Si algún flow file se queda en cola "failure"**: clic derecho sobre la cola → **List queue** → clic en una entrada → **View Provenance** → revisa el error. Lo más común: error de casteo de tipos (ej. `Description` como `ntext` no convertido a `NVARCHAR(MAX)`).

---

## Paso 7 — Replicar para las demás dimensiones pequeñas

Repite el patrón **Trigger → TRUNCATE → ExecuteSQLRecord → PutDatabaseRecord** para:

| Tabla origen | Query SELECT | Tabla destino |
|---|---|---|
| Suppliers | `SELECT SupplierID, CompanyName, ContactName, ContactTitle, Address, City, Region, PostalCode, Country, Phone, Fax, CAST(HomePage AS NVARCHAR(MAX)) AS HomePage FROM Suppliers` | `stg_suppliers` |
| Products | `SELECT ProductID, ProductName, SupplierID, CategoryID, QuantityPerUnit, UnitPrice, UnitsInStock, UnitsOnOrder, ReorderLevel, Discontinued FROM Products` | `stg_products` |
| Customers | `SELECT CustomerID, CompanyName, ContactName, ContactTitle, Address, City, Region, PostalCode, Country, Phone, Fax FROM Customers` | `stg_customers` |
| Employees | `SELECT EmployeeID, LastName, FirstName, Title, TitleOfCourtesy, BirthDate, HireDate, Address, City, Region, PostalCode, Country, HomePhone, Extension, CAST(Notes AS NVARCHAR(MAX)) AS Notes, ReportsTo FROM Employees` | `stg_employees` |
| Shippers | `SELECT ShipperID, CompanyName, Phone FROM Shippers` | `stg_shippers` |

7.1. **Truco productividad:** en NiFi 2.x puedes **seleccionar los 4 procesadores de Categories** (rectángulo), Ctrl+C, Ctrl+V → se copia el grupo. Luego edita cada uno con los valores de la tabla.
7.2. Tras pegar, abre cada procesador y ajusta el query, el nombre de la tabla destino, y el nombre del procesador.
7.3. Dispara cada `Trigger X` (Run Once).
7.4. Valida en DBeaver:
   ```sql
   SELECT 'stg_categories' AS tbl, COUNT(*) AS n FROM stg_categories
   UNION ALL SELECT 'stg_suppliers', COUNT(*) FROM stg_suppliers
   UNION ALL SELECT 'stg_products', COUNT(*) FROM stg_products
   UNION ALL SELECT 'stg_customers', COUNT(*) FROM stg_customers
   UNION ALL SELECT 'stg_employees', COUNT(*) FROM stg_employees
   UNION ALL SELECT 'stg_shippers', COUNT(*) FROM stg_shippers;
   ```
   Esperado: 8 / 29 / 77 / 91 / 9 / 3.
7.5. **CAPTURA:** el resultado.

---

## Paso 8 — Subflujo incremental: `Orders` y `Order Details`

Para tablas transaccionales usamos **carga incremental por watermark** sobre `OrderID`.

### 8.A — Orders

8.A.1. Arrastra **Processor** → busca **QueryDatabaseTableRecord** → Add.
8.A.2. Properties:

| Property | Value |
|---|---|
| Database Connection Pooling Service | `SQLServer-Northwind-Reader` |
| Database Type | `MS SQL 2012+` |
| Record Writer | `JsonWriter` |
| Table Name | `Orders` |
| Columns to Return | `OrderID,CustomerID,EmployeeID,OrderDate,RequiredDate,ShippedDate,ShipVia,Freight,ShipName,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry` |
| Maximum-value Columns | `OrderID` |
| Output Batch Size | `0` |

8.A.3. Settings → Name: `EXTRACT Orders (incremental)`. Auto-terminate: nada (success va al siguiente procesador).
8.A.4. Conéctalo a un nuevo `PutDatabaseRecord` (destino `stg_orders` en `MySQL-Staging`). Misma configuración que las dimensiones, **sin TRUNCATE** porque es incremental.

> **Importante:** `QueryDatabaseTableRecord` guarda el `MAX(OrderID)` en el **estado** del procesador. La primera corrida trae todo (10248..11077); las siguientes solo lo nuevo. Para reiniciar el estado: clic derecho sobre el procesador → **View State** → Clear State.

### 8.B — Order Details

8.B.1. Igual que Orders pero:
   - Table Name: `Order Details` (con espacio — NiFi lo maneja).
   - Maximum-value Columns: `OrderID` (PK compuesta; OrderID es monotónico).
   - Columns to Return: `OrderID,ProductID,UnitPrice,Quantity,Discount`.
8.B.2. Destino: `stg_order_details`.

8.C. Start → Run Once en ambos `EXTRACT *`.
8.D. Valida:
```sql
SELECT COUNT(*) FROM stg_orders;        -- esperado: 830
SELECT COUNT(*) FROM stg_order_details; -- esperado: 2155
```
8.E. **CAPTURA:** flujo completo + conteos.

---

## Paso 9 — Probar la incrementalidad

9.1. En SQL Server (DBeaver, base `Northwind`), inserta un pedido nuevo:
```sql
USE Northwind;
INSERT INTO Orders (CustomerID, EmployeeID, OrderDate)
VALUES ('ALFKI', 1, GETDATE());
DECLARE @new_id INT = SCOPE_IDENTITY();
INSERT INTO [Order Details] (OrderID, ProductID, UnitPrice, Quantity, Discount)
VALUES (@new_id, 1, 18.00, 5, 0);
SELECT @new_id AS nuevo_pedido;
```
9.2. En NiFi, **Run Once** sobre `EXTRACT Orders` y `EXTRACT Order Details`.
9.3. Verifica que `stg_orders` subió a **831** y `stg_order_details` a **2156**.
9.4. **CAPTURA:** evidencia antes/después.

---

## Paso 10 — Exportar el Pipeline 1

10.1. En el lienzo raíz, clic derecho sobre el Process Group `Pipeline 1 - Fuente a Staging` → **Download flow definition** → guarda como `nifi-templates\Pipeline_1.json` en la raíz del proyecto.
10.2. NiFi 2.x **eliminó los Templates legacy** — el formato estándar ahora es **Flow Definition (JSON)** que es lo que estás exportando.
10.3. Como los flows viven en el volumen persistente del contenedor (`nifi_state`, `nifi_flowfile`, `nifi_conf`), sobreviven a `docker compose restart`. El JSON exportado es solo para versionado en git.
10.4. **CAPTURA:** archivo guardado.

---

## Checklist de cierre de la Fase 3

- [ ] Drivers JDBC en `nifi\drivers\` y visibles dentro del contenedor
- [ ] NiFi accesible en `https://localhost:8443/nifi` con `admin / NifiAdmin2026!`
- [ ] 5 Controller Services Enabled (3 pools + `JsonWriter` + `JsonReader`)
- [ ] URLs JDBC usan nombres de servicio y puerto **interno** (`source_sqlserver:1433`, `staging_mysql:3306`, `dw_mysql:3306`)
- [ ] Pipeline 1 carga las 8 tablas con conteos correctos (8/29/77/91/9/3 + 830/2155)
- [ ] Carga incremental probada (pedido manual aparece tras re-ejecutar)
- [ ] Pipeline 1 exportado a `nifi-templates\Pipeline_1.json`
- [ ] Capturas en `capturas\03\` (mínimo 7)

## Resumen del cambio respecto a NiFi 1.x

| Antes (NiFi 1.x) | Ahora (NiFi 2.x) |
|---|---|
| `ExecuteSQL` (Avro out) → `ConvertAvroToJSON` → `PutDatabaseRecord` | `ExecuteSQLRecord` (con `JsonWriter`) → `PutDatabaseRecord` |
| `QueryDatabaseTable` (Avro) → `ConvertAvroToJSON` → `PutDatabaseRecord` | `QueryDatabaseTableRecord` (con `JsonWriter`) → `PutDatabaseRecord` |
| Templates `.xml` (legacy) | Flow Definitions `.json` |
| UI con diálogos emergentes | UI con panel lateral derecho |

**"Fase 3 lista"** → pasamos a la Fase 4 (Pipeline 2 + transformaciones).
