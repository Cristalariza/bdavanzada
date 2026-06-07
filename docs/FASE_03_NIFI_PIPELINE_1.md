# Fase 3 — Apache NiFi 2.x + Pipeline 1 (Fuente → Staging)

**Objetivo:** arrancar NiFi 2.x, configurar los pools de conexión y construir el **Pipeline 1**, que extrae datos crudos de SQL Server (Northwind) y los carga 1:1 al Staging MySQL. Sin transformar nada.
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fases 0, 1, 2 completadas.

---

## Paso 1 — Configurar NiFi para acceso sin SSL (modo desarrollo)

NiFi 2.x por defecto usa HTTPS con certificado autofirmado y un usuario aleatorio. Para este proyecto académico simplificamos a HTTP plano.

1.1. Detén NiFi si lo iniciaste antes: cierra la terminal donde corre.
1.2. Abre el archivo `C:\nifi\nifi-2.x.x\conf\nifi.properties` con Notepad++ o VS Code (NO con Notepad simple — daña los saltos de línea).
1.3. Busca y modifica estas líneas (usa Ctrl+F):

| Buscar | Cambiar a |
|---|---|
| `nifi.web.https.port=8443` | `nifi.web.https.port=` (deja vacío) |
| `nifi.web.https.host=127.0.0.1` | `nifi.web.https.host=` (deja vacío) |
| `nifi.web.http.port=` (vacío) | `nifi.web.http.port=8080` |
| `nifi.web.http.host=` (vacío) | `nifi.web.http.host=127.0.0.1` |
| `nifi.security.user.login.identity.provider=single-user-provider` | `nifi.security.user.login.identity.provider=` (vacío) |
| `nifi.security.allow.anonymous.authentication=false` | `nifi.security.allow.anonymous.authentication=true` |

1.4. Guarda el archivo.

> **¿Por qué?** En desarrollo local sin secretos sensibles, HTTPS + auth añade fricción sin valor. Para producción real, esto NO se hace.

---

## Paso 2 — Arrancar NiFi

2.1. Abre PowerShell y ejecuta:
```powershell
cd C:\nifi\nifi-2.x.x\bin
.\run-nifi.bat
```
2.2. NiFi tarda **2-3 minutos** en arrancar. Verás muchos logs. Espera hasta ver una línea similar a:
```
NiFi has started. The UI is available at the following URLs: http://127.0.0.1:8080/nifi
```
2.3. **No cierres esta terminal**: si la cierras, NiFi se apaga. Más adelante puedes correrlo como servicio Windows.
2.4. Abre el navegador en `http://127.0.0.1:8080/nifi`. Debe aparecer el lienzo de NiFi vacío.
2.5. **CAPTURA:** lienzo de NiFi cargado.

---

## Paso 3 — Cargar los drivers JDBC en NiFi

3.1. En PowerShell (otra ventana, NiFi sigue corriendo):
```powershell
copy C:\nifi\drivers\mssql-jdbc-*.jar C:\nifi\nifi-2.x.x\lib\
copy C:\nifi\drivers\mysql-connector-j-*.jar C:\nifi\nifi-2.x.x\lib\
```
3.2. **Reinicia NiFi** para que cargue los drivers nuevos:
   - En la terminal donde corre NiFi, presiona Ctrl+C y espera a que termine.
   - Vuelve a ejecutar `.\run-nifi.bat`.
   - Espera de nuevo el mensaje "NiFi has started".

---

## Paso 4 — Crear los 3 Controller Services (pools de conexión)

NiFi separa la configuración de la conexión a base de datos del procesador que la usa. Estos pools son **Controller Services**.

4.1. En la UI de NiFi, clic en el ícono de **hamburguesa (☰) arriba a la derecha → Controller Settings**.
4.2. Ve a la pestaña **Controller Services**.
4.3. Clic en el **+** para agregar un nuevo servicio.
4.4. Busca **DBCPConnectionPool** → Add.

### 4.4.A — Pool para SQL Server (fuente)

Doble clic sobre el servicio creado → Properties:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:sqlserver://host.docker.internal:1433;databaseName=Northwind;encrypt=false;trustServerCertificate=true` |
| Database Driver Class Name | `com.microsoft.sqlserver.jdbc.SQLServerDriver` |
| Database Driver Location(s) | `/C:/nifi/nifi-2.x.x/lib/mssql-jdbc-XX.X.X.jre11.jar` (ajusta nombre real del jar) |
| Database User | `nifi_reader` |
| Password | `NifiReader2026!` |
| Max Wait Time | `30 seconds` |
| Max Total Connections | `8` |

> **Importante:** dentro de NiFi corriendo en Windows nativo, accedes a `localhost:1433`. PERO si más adelante decides correr NiFi también en contenedor, debes usar el nombre del servicio (`source_sqlserver`). Para esta guía NiFi corre nativo, usa `localhost`.
> Corrige: el URL correcto desde NiFi nativo es `jdbc:sqlserver://localhost:1433;...`. Solo usa `host.docker.internal` si NiFi está en contenedor.

Cambia el URL a:
```
jdbc:sqlserver://localhost:1433;databaseName=Northwind;encrypt=false;trustServerCertificate=true
```

Pestaña **Settings** → Name: `SQLServer-Northwind-Reader`.
Apply → Habilita el servicio con el rayito ⚡ → State: **Enabled**.

### 4.4.B — Pool para MySQL Staging

Repite el proceso. Otro DBCPConnectionPool con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://localhost:3307/staging_northwind?useSSL=false&serverTimezone=UTC` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/C:/nifi/nifi-2.x.x/lib/mysql-connector-j-X.X.X.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

Name: `MySQL-Staging`. Habilítalo.

### 4.4.C — Pool para MySQL DW

Otro más con:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:mysql://localhost:3306/dw_northwind?useSSL=false&serverTimezone=UTC&allowMultiQueries=true` |
| Database Driver Class Name | `com.mysql.cj.jdbc.Driver` |
| Database Driver Location(s) | `/C:/nifi/nifi-2.x.x/lib/mysql-connector-j-X.X.X.jar` |
| Database User | `etl_user` |
| Password | `EtlUser2026!` |

> Nota el `allowMultiQueries=true` — lo necesitaremos en Fase 4 para ejecutar el script de transformaciones en una sola llamada.

Name: `MySQL-DW`. Habilítalo.

4.5. **CAPTURA:** los 3 Controller Services en estado **Enabled**.

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

> **`Translate Field Names = true`** convierte `CategoryID` → `categoryid` para que matchee `CategoryID` de MySQL (insensible a mayúsculas). Por eso podemos copiar columnas con PascalCase desde SQL Server a MySQL.

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

8.A.1. Arrastra un procesador **QueryDatabaseTable** (este sí maneja estado de incremental por sí mismo).
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

> **Importante:** QueryDatabaseTable guarda el `MAX(OrderID)` en el estado del procesador. La primera corrida trae todo (10248..11077); las siguientes solo lo nuevo.

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

9.1. En SQL Server, inserta un pedido nuevo:
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
10.2. **CAPTURA:** archivo guardado.

---

## Checklist de cierre de la Fase 3

- [ ] NiFi corre en `http://127.0.0.1:8080/nifi` sin auth
- [ ] 3 Controller Services Enabled (`SQLServer-Northwind-Reader`, `MySQL-Staging`, `MySQL-DW`)
- [ ] Pipeline 1 carga las 8 tablas con conteos correctos (91/830/2155/77/8/29/9/3)
- [ ] Carga incremental probada (pedido manual aparece tras re-ejecutar)
- [ ] Pipeline 1 exportado a `nifi-templates\Pipeline_1.json`
- [ ] Capturas en `capturas\03\` (mínimo 7)

**"Fase 3 lista"** → pasamos a la Fase 4 (Pipeline 2 + transformaciones).
