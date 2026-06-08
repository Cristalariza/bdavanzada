# Fase 3 — Apache NiFi 2.x (en Docker) + Pipeline 1 (Fuente → Staging)

**Objetivo:** acceder al NiFi que ya corre en el contenedor `nifi`, configurar los pools de conexión y construir el **Pipeline 1**, que extrae datos crudos de SQL Server (Northwind) y los carga 1:1 al Staging MySQL.
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fases 0, 1, 2 completadas. Los 4 contenedores deben estar corriendo (`docker ps` muestra `source_sqlserver`, `staging_mysql`, `dw_mysql`, `nifi`).

---

## Paso 1 — Verificar drivers JDBC en NiFi

El script `setup_containers.ps1` de la Fase 0 ya descargó los drivers a `nifi\drivers\` y los montó en el contenedor en `/opt/nifi/nifi-current/extra-jars/`. Validar:

1.1. Confirma que existen:
   ```powershell
   dir nifi\drivers
   ```
   Debes ver `mssql-jdbc-*.jar` y `mysql-connector-j-*.jar`.
1.2. Confirma que NiFi los ve por dentro:
   ```powershell
   docker exec nifi ls -la /opt/nifi/nifi-current/extra-jars/
   ```
1.3. Si descargaste los drivers DESPUÉS de que el contenedor arrancara, reinícialo:
   ```powershell
   docker compose restart nifi
   ```
1.4. **CAPTURA:** salida del `docker exec`.

---

## Paso 2 — Acceder a la UI de NiFi

2.1. Verifica que el contenedor esté corriendo:
   ```powershell
   docker ps --filter "name=nifi"
   ```
   Debe mostrar `Up X minutes`.
2.2. Mira los logs para confirmar que arrancó bien:
   ```powershell
   docker logs nifi --tail 30
   ```
   Debe aparecer una línea similar a `NiFi has started. The UI is available at the following URLs`.
2.3. Abre el navegador en **`https://localhost:8443/nifi`** (es HTTPS, no HTTP).
2.4. El navegador advertirá certificado no confiable (porque es autofirmado). Clic en **"Avanzado" → "Continuar a localhost (no seguro)"**.
2.5. Pantalla de login. Usuario y contraseña:
   - Usuario: `admin`
   - Contraseña: `NifiAdmin2026!`
2.6. Debe aparecer el lienzo vacío de NiFi.
2.7. **CAPTURA:** lienzo de NiFi cargado tras login.

---

## Paso 3 — Verificar que NiFi puede ver los drivers

3.1. Clic en el menú **☰ (arriba a la derecha) → Controller Settings → Controller Services**. (Lista vacía por ahora, normal.)
3.2. Clic en el botón **+** → busca `DBCPConnectionPool` → Add. (Solo es para confirmar que el tipo existe; lo configuraremos en el paso 4.)
3.3. Si quieres asegurarte que los `.jar` están dentro del contenedor:
   ```powershell
   docker exec nifi ls -la /opt/nifi/nifi-current/extra-jars/
   ```
   Debe listar los 2 `.jar`.
3.4. **CAPTURA:** salida del `docker exec` mostrando los `.jar`.

---

## Paso 4 — Crear los 3 Controller Services

> **Importante:** como NiFi corre en el contenedor `nifi` y se conecta a los otros contenedores por la red `bi_network`, **los URL JDBC usan los nombres de servicio, NO `localhost`**. Y para MySQL usan el **puerto interno 3306** (no 3307), porque los contenedores se ven entre sí dentro de la red, no por los puertos mapeados al host.

### 4.A — Pool para SQL Server (fuente)

4.A.1. En **Controller Settings → Controller Services → +** → `DBCPConnectionPool` → Add.
4.A.2. Doble clic sobre el servicio → pestaña **Properties**:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:sqlserver://source_sqlserver:1433;databaseName=Northwind;encrypt=false;trustServerCertificate=true` |
| Database Driver Class Name | `com.microsoft.sqlserver.jdbc.SQLServerDriver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mssql-jdbc-XX.X.X.jre11.jar` (ajusta el nombre real del jar) |
| Database User | `nifi_reader` |
| Password | `NifiReader2026!` |
| Max Wait Time | `30 seconds` |
| Max Total Connections | `8` |

4.A.3. Pestaña **Settings** → Name: `SQLServer-Northwind-Reader`.
4.A.4. Apply → habilita el servicio con el rayito ⚡ → State: **Enabled**.

### 4.B — Pool para MySQL Staging

4.B.1. Otro DBCPConnectionPool con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://staging_mysql:3306/staging_northwind?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mysql-connector-j-X.X.X.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

Name: `MySQL-Staging`. Habilítalo.

### 4.C — Pool para MySQL DW

4.C.1. Otro más con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://dw_mysql:3306/dw_northwind?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&allowMultiQueries=true` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/opt/nifi/nifi-current/extra-jars/mysql-connector-j-X.X.X.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

> Nota el `allowMultiQueries=true` — lo necesitaremos en Fase 4 para ejecutar el script de transformaciones en una sola llamada.

Name: `MySQL-DW`. Habilítalo.

4.D. **CAPTURA:** los 3 Controller Services en estado **Enabled**.

> **Si alguno NO se habilita** y da error "Driver class not found": revisa que el `.jar` esté en `nifi\drivers\` y que la ruta del campo "Driver Location" coincida con el nombre real del archivo. Reinicia el contenedor (`docker compose restart nifi`) si dudas.

---

## Paso 5 — Crear el Process Group "Pipeline 1"

5.1. En el lienzo vacío de NiFi, arrastra desde la barra superior el ícono de **Process Group** (segundo desde la izquierda).
5.2. Nombre: `Pipeline 1 - Fuente a Staging`. Add.
5.3. Doble clic sobre el grupo para entrar.

---

## Paso 6 — Subflujo: tabla `Categories` (carga completa, como plantilla)

Vamos a construir el subflujo para `Categories` primero. Luego lo replicas para las demás dimensiones pequeñas con un copy-paste.

### 6.A — Procesador 1: `ExecuteSQL` (lee de SQL Server)

6.A.1. Arrastra el ícono **Processor** desde la barra superior. Busca **ExecuteSQL** → Add.
6.A.2. Doble clic sobre él → Properties:

| Property | Value |
|---|---|
| Database Connection Pooling Service | `SQLServer-Northwind-Reader` |
| SQL select query | `SELECT CategoryID, CategoryName, CAST(Description AS NVARCHAR(MAX)) AS Description FROM Categories` |
| Max Rows Per Flow File | `0` |
| Output Batch Size | `0` |

6.A.3. Pestaña **Settings**:
   - Name: `EXTRACT Categories`.
   - Penalty Duration: `30 sec`.
   - Yield Duration: `1 sec`.
   - Auto-terminate: marca `failure`.
6.A.4. Apply.

### 6.B — Procesador 2: `ConvertAvroToJSON`

`ExecuteSQL` produce Avro. Para usar `PutDatabaseRecord` con conversión limpia, mejor pasar por JSON.

6.B.1. Arrastra otro Processor → busca **ConvertAvroToJSON** → Add.
6.B.2. Properties → deja por defecto.
6.B.3. Settings → Name: `Avro→JSON`. Auto-terminate: `failure`.

### 6.C — Procesador 3: `PutDatabaseRecord` (escribe en MySQL Staging)

6.C.1. Arrastra otro Processor → **PutDatabaseRecord** → Add.
6.C.2. Para que lea JSON necesitamos un **Record Reader**. NiFi pedirá uno.
6.C.3. Properties:

| Property | Value |
|---|---|
| Record Reader | (clic) → Create new → **JsonTreeReader** → Apply → Habilítalo con el rayito |
| Statement Type | `INSERT` |
| Database Connection Pooling Service | `MySQL-Staging` |
| Schema Name | `staging_northwind` |
| Table Name | `stg_categories` |
| Translate Field Names | `true` |
| Unmatched Field Behavior | `Ignore Unmatched Fields` |
| Unmatched Column Behavior | `Ignore Unmatched Columns` |

> **`Translate Field Names = true`** convierte `CategoryID` → `categoryid` para que matchee con la columna `CategoryID` de MySQL (insensible a mayúsculas).

6.C.4. Settings → Name: `LOAD stg_categories`. Auto-terminate: `success`, `failure`, `retry`.

### 6.D — Conectar los 3 procesadores

6.D.1. Pasa el mouse sobre `EXTRACT Categories` → aparece una flecha → arrástrala hasta `Avro→JSON` → seleccion **success** → Add.
6.D.2. Igual de `Avro→JSON` a `LOAD stg_categories` → **success** → Add.

### 6.E — Estrategia anti-duplicados: TRUNCATE antes de cargar

Para una **carga completa**, antes de insertar conviene vaciar la tabla destino.

6.E.1. Antes de `EXTRACT Categories`, agrega un procesador **PutSQL**:
   - Connection Pool: `MySQL-Staging`
   - SQL Statement: `TRUNCATE TABLE stg_categories`
   - Name: `TRUNCATE stg_categories`
   - Auto-terminate: `failure`, `retry`
6.E.2. Para que se dispare una vez, antes de **PutSQL** agrega un **GenerateFlowFile**:
   - File Size: `0B`
   - Scheduling: Run Schedule = `999 days` (lo dispararemos manualmente).
   - Name: `Trigger Categories`.
6.E.3. Conecta: `Trigger Categories` --success--> `TRUNCATE stg_categories` --success--> `EXTRACT Categories`.

### 6.F — Probar

6.F.1. Selecciona los 5 procesadores → clic derecho → Start.
6.F.2. Clic derecho sobre `Trigger Categories` → **Run Once**.
6.F.3. Observa los contadores: cada flow file debe pasar por todos los procesadores sin acumularse en una cola.
6.F.4. En DBeaver, en el Staging:
```sql
SELECT COUNT(*) FROM stg_categories;     -- esperado: 8
SELECT * FROM stg_categories LIMIT 3;
```
6.F.5. **CAPTURA:** subflujo de Categories en NiFi + el SELECT en DBeaver.

---

## Paso 7 — Replicar para las demás dimensiones pequeñas

Repite el patrón **Trigger → TRUNCATE → ExtractSQL → Avro→JSON → PutDatabaseRecord** para:

| Tabla origen | Query SELECT | Tabla destino |
|---|---|---|
| Suppliers | `SELECT SupplierID, CompanyName, ContactName, ContactTitle, Address, City, Region, PostalCode, Country, Phone, Fax, CAST(HomePage AS NVARCHAR(MAX)) AS HomePage FROM Suppliers` | `stg_suppliers` |
| Products | `SELECT ProductID, ProductName, SupplierID, CategoryID, QuantityPerUnit, UnitPrice, UnitsInStock, UnitsOnOrder, ReorderLevel, Discontinued FROM Products` | `stg_products` |
| Customers | `SELECT CustomerID, CompanyName, ContactName, ContactTitle, Address, City, Region, PostalCode, Country, Phone, Fax FROM Customers` | `stg_customers` |
| Employees | `SELECT EmployeeID, LastName, FirstName, Title, TitleOfCourtesy, BirthDate, HireDate, Address, City, Region, PostalCode, Country, HomePhone, Extension, CAST(Notes AS NVARCHAR(MAX)) AS Notes, ReportsTo FROM Employees` | `stg_employees` |
| Shippers | `SELECT ShipperID, CompanyName, Phone FROM Shippers` | `stg_shippers` |

7.1. Truco de productividad: en NiFi puedes **seleccionar los 5 procesadores de Categories**, Copy (Ctrl+C), Paste (Ctrl+V), y luego renombrar/editar.
7.2. Tras pegar, edita cada procesador con los valores de la tabla.
7.3. Ejecuta el `Trigger ...` de cada uno una vez.
7.4. Valida en DBeaver:
```sql
SELECT 'stg_categories' AS tbl, COUNT(*) AS n FROM stg_categories
UNION ALL SELECT 'stg_suppliers', COUNT(*) FROM stg_suppliers
UNION ALL SELECT 'stg_products', COUNT(*) FROM stg_products
UNION ALL SELECT 'stg_customers', COUNT(*) FROM stg_customers
UNION ALL SELECT 'stg_employees', COUNT(*) FROM stg_employees
UNION ALL SELECT 'stg_shippers', COUNT(*) FROM stg_shippers;
```
Esperado:
| tbl | n |
|---|---|
| stg_categories | 8 |
| stg_suppliers | 29 |
| stg_products | 77 |
| stg_customers | 91 |
| stg_employees | 9 |
| stg_shippers | 3 |

7.5. **CAPTURA:** el resultado.

---

## Paso 8 — Subflujo incremental: `Orders` y `Order Details`

Estas son tablas transaccionales. Aquí sí carga **incremental por watermark** (`OrderID`).

### 8.A — Orders

8.A.1. Arrastra un procesador **QueryDatabaseTable** (este maneja estado de incremental por sí mismo).
8.A.2. Properties:

| Property | Value |
|---|---|
| Database Connection Pooling Service | `SQLServer-Northwind-Reader` |
| Database Type | `MS SQL 2012+` |
| Table Name | `Orders` |
| Columns to Return | `OrderID,CustomerID,EmployeeID,OrderDate,RequiredDate,ShippedDate,ShipVia,Freight,ShipName,ShipAddress,ShipCity,ShipRegion,ShipPostalCode,ShipCountry` |
| Maximum-value Columns | `OrderID` |
| Output Batch Size | `0` |

8.A.3. Settings → Name: `EXTRACT Orders (incremental)`. Auto-terminate: nada (success va al siguiente procesador).
8.A.4. Conéctalo a un nuevo `Avro→JSON` + `PutDatabaseRecord` (con destino `stg_orders` en `MySQL-Staging`). MISMA configuración que las dimensiones, sin TRUNCATE — porque es incremental.

> **Importante:** QueryDatabaseTable guarda el `MAX(OrderID)` en el estado del procesador. La primera corrida trae todo (10248..11077); las siguientes solo lo nuevo. Para reiniciar el estado: clic derecho sobre el procesador → View State → Clear State.

### 8.B — Order Details

8.B.1. Igual que Orders pero:
   - Table Name: `Order Details` (sí, con espacio — NiFi lo maneja).
   - Maximum-value Columns: `OrderID` (composite PK; OrderID monotónico al insertarse).
   - Columns to Return: `OrderID,ProductID,UnitPrice,Quantity,Discount`.
8.B.2. Destino: `stg_order_details`.

8.C. Start → Run Once en ambos.
8.D. Valida:
```sql
SELECT COUNT(*) FROM stg_orders;        -- esperado: 830
SELECT COUNT(*) FROM stg_order_details; -- esperado: 2155
```
8.E. **CAPTURA:** flujo completo con orders/order_details + conteos.

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
9.2. En NiFi, Run Once de los procesadores `EXTRACT Orders` y `EXTRACT Order Details`.
9.3. Valida que stg_orders subió a **831** y stg_order_details a **2156**.
9.4. **CAPTURA:** evidencia antes/después.

---

## Paso 10 — Exportar el template

10.1. En NiFi, selecciona TODOS los procesadores del Pipeline 1 → clic derecho → Download Flow Definition → guarda como `nifi-templates\Pipeline_1.json` en la carpeta del proyecto.
10.2. Como NiFi corre en contenedor y los volúmenes son persistentes, los flows ya sobreviven a reinicios. El JSON exportado es solo para versionado/git.
10.3. **CAPTURA:** archivo guardado.

---

## Checklist de cierre de la Fase 3

- [ ] Drivers JDBC en `nifi\drivers\` y visibles dentro del contenedor
- [ ] NiFi accesible en `https://localhost:8443/nifi` con `admin / NifiAdmin2026!`
- [ ] 3 Controller Services Enabled (`SQLServer-Northwind-Reader`, `MySQL-Staging`, `MySQL-DW`)
- [ ] URLs JDBC usan nombres de servicio (`source_sqlserver`, `staging_mysql`, `dw_mysql`) y puerto **3306** interno
- [ ] Pipeline 1 carga las 8 tablas con conteos correctos (91/830/2155/77/8/29/9/3)
- [ ] Carga incremental probada (pedido manual aparece tras re-ejecutar)
- [ ] Pipeline 1 exportado a `nifi-templates\Pipeline_1.json`
- [ ] Capturas en `capturas\03\` (mínimo 7)

**"Fase 3 lista"** → pasamos a la Fase 4 (Pipeline 2 + transformaciones).
