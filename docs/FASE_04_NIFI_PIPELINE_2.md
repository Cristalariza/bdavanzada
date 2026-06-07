# Fase 4 — Pipeline 2 (Staging → DW) + Transformaciones

**Objetivo:** mover datos del Staging al Data Warehouse aplicando todas las transformaciones (joins, desnormalización, llaves sustitutas, cálculo de medidas, metas, geografía).
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fase 3 completada (Staging poblado con datos correctos).

---

## Visión general del Pipeline 2

```
                              ┌───────────────────────────┐
                              │ Trigger Pipeline 2        │
                              └──────────────┬────────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              │                              │                              │
   ┌──────────▼─────────┐         ┌──────────▼─────────┐         ┌──────────▼─────────┐
   │ Cargar Dimensiones │         │ Cargar fact_landing│         │ Cargar product_cost│
   │ (cliente, producto,│         │ (Order Details ⋈   │         │ (60% UnitPrice)    │
   │ empleado, transp., │         │  Orders)           │         │                    │
   │ geografia, metas)  │         │                    │         │                    │
   └──────────┬─────────┘         └──────────┬─────────┘         └──────────┬─────────┘
              │                              │                              │
              └──────────────────────────────▼──────────────────────────────┘
                                             │
                              ┌──────────────▼─────────────┐
                              │ Resolver SK y poblar       │
                              │ fact_ventas (PutSQL grande)│
                              └────────────────────────────┘
```

> **Por qué este orden:** Las dimensiones deben existir ANTES de resolver las surrogate keys del hecho. fact_landing es una zona intermedia con BKs (no SKs); el último paso hace los joins BK→SK dentro del DW.

---

## Paso 1 — Crear el Process Group "Pipeline 2"

1.1. En NiFi, regresa al lienzo raíz (botón "Back to Parent").
1.2. Arrastra un Process Group → Nombre: `Pipeline 2 - Staging a DW`.
1.3. Doble clic para entrar.

---

## Paso 2 — Cargar `dim_cliente`

### 2.A — TRUNCATE primero

2.A.1. **GenerateFlowFile** → Name: `Trigger dim_cliente` → File Size `0B` → Run Schedule `999 days`.
2.A.2. **PutSQL** (pool `MySQL-DW`) → SQL Statement:
   ```sql
   SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE dim_cliente; SET FOREIGN_KEY_CHECKS=1;
   ```
   Name: `TRUNCATE dim_cliente`.

> **Nota FK:** desactivamos checks porque fact_ventas tiene FK a dim_cliente. En producción se haría con TRUNCATE CASCADE o eliminando hechos primero. Para esta carga inicial es seguro porque limpiamos el hecho después también.

### 2.B — Extraer del Staging

2.B.1. **ExecuteSQL** (pool `MySQL-Staging`) → Query:
   ```sql
   SELECT
     CustomerID  AS customer_id,
     CompanyName AS company_name,
     ContactName AS contact_name,
     City        AS city,
     Country     AS country
   FROM stg_customers
   ```
   Name: `EXTRACT stg_customers → dim_cliente`.

2.B.2. **ConvertAvroToJSON** → Name: `Avro→JSON cliente`.

### 2.C — Cargar en DW

2.C.1. **PutDatabaseRecord** (pool `MySQL-DW`):
   - Statement Type: `INSERT`
   - Schema Name: `dw_northwind`
   - Table Name: `dim_cliente`
   - Translate Field Names: `true`
   - Unmatched Field/Column Behavior: `Ignore`
   - Record Reader: `JsonTreeReader` (el mismo de Pipeline 1)
   - Name: `LOAD dim_cliente`.

2.C.2. Conecta los 4 procesadores en cadena.

### 2.D — Probar

2.D.1. Start + Run Once en `Trigger dim_cliente`.
2.D.2. En DBeaver (DW):
   ```sql
   SELECT COUNT(*) FROM dim_cliente;  -- esperado: 91
   SELECT * FROM dim_cliente LIMIT 5;
   ```
2.D.3. **CAPTURA:** subflujo + resultado.

---

## Paso 3 — Cargar `dim_producto` (con desnormalización)

3.1. Trigger + TRUNCATE igual que en paso 2.
3.2. **ExecuteSQL** (pool `MySQL-Staging`):
   ```sql
   SELECT
     p.ProductID        AS product_id,
     p.ProductName      AS product_name,
     c.CategoryName     AS category_name,
     s.CompanyName      AS supplier_name,
     s.Country          AS supplier_country,
     p.UnitPrice        AS unit_price,
     p.Discontinued     AS discontinued
   FROM stg_products p
   LEFT JOIN stg_categories c ON c.CategoryID = p.CategoryID
   LEFT JOIN stg_suppliers  s ON s.SupplierID = p.SupplierID
   ```
3.3. Avro→JSON + PutDatabaseRecord (`dim_producto`).
3.4. Validar:
```sql
SELECT COUNT(*) FROM dim_producto;     -- 77
SELECT product_name, category_name, supplier_name FROM dim_producto LIMIT 5;
```

---

## Paso 4 — Cargar `dim_empleado` (con concatenación)

4.1. Trigger + TRUNCATE.
4.2. ExecuteSQL:
   ```sql
   SELECT
     EmployeeID                          AS employee_id,
     CONCAT(FirstName, ' ', LastName)    AS nombre_completo,
     Title                               AS titulo,
     Country                             AS pais,
     HireDate                            AS fecha_contratacion
   FROM stg_employees
   ```
4.3. Avro→JSON + PutDatabaseRecord (`dim_empleado`).
4.4. Validar:
```sql
SELECT COUNT(*) FROM dim_empleado;   -- 9
SELECT nombre_completo FROM dim_empleado;
```

---

## Paso 5 — Cargar `dim_transportista`

5.1. Trigger + TRUNCATE.
5.2. ExecuteSQL:
   ```sql
   SELECT ShipperID AS shipper_id, CompanyName AS company_name FROM stg_shippers
   ```
5.3. Avro→JSON + PutDatabaseRecord (`dim_transportista`).
5.4. Validar: 3 filas.

---

## Paso 6 — Cargar `dim_geografia` (con manejo de nulos)

La geografía se deriva de los campos `Ship*` de Orders.

6.1. Trigger + TRUNCATE.
6.2. ExecuteSQL (pool `MySQL-Staging`):
   ```sql
   SELECT DISTINCT
     COALESCE(ShipCity, 'No especificado')    AS ciudad,
     COALESCE(ShipRegion, 'No especificado')  AS region,
     COALESCE(ShipCountry, 'No especificado') AS pais
   FROM stg_orders
   ```
6.3. Avro→JSON + PutDatabaseRecord (`dim_geografia`).
6.4. Validar:
```sql
SELECT COUNT(*) FROM dim_geografia;   -- típicamente 70-80 combinaciones únicas
SELECT * FROM dim_geografia ORDER BY pais, ciudad LIMIT 10;
```

---

## Paso 7 — Cargar `product_costos`

7.1. Trigger + TRUNCATE.
7.2. ExecuteSQL (pool `MySQL-Staging`):
   ```sql
   SELECT
     ProductID                  AS product_id,
     ROUND(UnitPrice * 0.60, 2) AS costo_unitario
   FROM stg_products
   ```
7.3. Avro→JSON + PutDatabaseRecord (`product_costos`).
7.4. Validar: 77 filas.

---

## Paso 8 — Cargar `fact_landing` (zona intermedia con BKs)

Aquí materializamos el join Order Details ⋈ Orders con todas las claves de negocio.

8.1. Trigger + TRUNCATE de `fact_landing`.
8.2. ExecuteSQL (pool `MySQL-Staging`):
   ```sql
   SELECT
     od.OrderID        AS order_id,
     od.ProductID      AS product_id,
     o.CustomerID      AS customer_id,
     o.EmployeeID      AS employee_id,
     o.ShipVia         AS shipper_id,
     COALESCE(o.ShipCity,    'No especificado') AS ship_city,
     COALESCE(o.ShipRegion,  'No especificado') AS ship_region,
     COALESCE(o.ShipCountry, 'No especificado') AS ship_country,
     DATE(o.OrderDate)   AS order_date,
     DATE(o.ShippedDate) AS shipped_date,
     od.Quantity        AS cantidad,
     od.UnitPrice       AS precio_unitario,
     od.Discount        AS descuento
   FROM stg_order_details od
   INNER JOIN stg_orders o ON o.OrderID = od.OrderID
   ```
8.3. Avro→JSON + PutDatabaseRecord (`fact_landing`).
8.4. Validar: **2155** filas.

---

## Paso 9 — Generar `dim_metas` (cálculo dentro del DW)

Como `dim_metas` depende del histórico de ventas, la generamos DESPUÉS de cargar fact_ventas. Mejor: la generamos dentro del script grande del paso 10. Por ahora déjala vacía.

---

## Paso 10 — Resolución de SK y carga de `fact_ventas` (PutSQL grande)

Este es el corazón de las transformaciones. Se ejecuta como SQL set-based dentro del DW.

10.1. Crea un procesador **GenerateFlowFile** → Name `Trigger fact_ventas` → File Size `0B` → Run Schedule `999 days`.

10.2. **PutSQL** (pool `MySQL-DW`, recuerda que tiene `allowMultiQueries=true`) → SQL Statement (todo este bloque en una sola property):

```sql
-- 1) Limpiar hecho y metas
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE fact_ventas;
TRUNCATE TABLE dim_metas;
SET FOREIGN_KEY_CHECKS=1;

-- 2) Poblar fact_ventas resolviendo BK→SK y calculando medidas
INSERT INTO fact_ventas (
    tiempo_sk, cliente_sk, producto_sk, empleado_sk, geografia_sk, transportista_sk,
    order_id, cantidad, precio_unitario, descuento,
    venta_bruta, venta_neta, costo_total, margen, dias_entrega
)
SELECT
    CAST(DATE_FORMAT(fl.order_date, '%Y%m%d') AS UNSIGNED) AS tiempo_sk,
    dc.cliente_sk,
    dp.producto_sk,
    de.empleado_sk,
    dg.geografia_sk,
    dt.transportista_sk,
    fl.order_id,
    fl.cantidad,
    fl.precio_unitario,
    fl.descuento,
    ROUND(fl.cantidad * fl.precio_unitario, 2)                                AS venta_bruta,
    ROUND(fl.cantidad * fl.precio_unitario * (1 - fl.descuento), 2)           AS venta_neta,
    ROUND(fl.cantidad * pc.costo_unitario, 2)                                 AS costo_total,
    ROUND(fl.cantidad * fl.precio_unitario * (1 - fl.descuento)
        - fl.cantidad * pc.costo_unitario, 2)                                 AS margen,
    DATEDIFF(fl.shipped_date, fl.order_date)                                  AS dias_entrega
FROM fact_landing fl
JOIN dim_cliente       dc ON dc.customer_id  = fl.customer_id
JOIN dim_producto      dp ON dp.product_id   = fl.product_id
JOIN dim_empleado      de ON de.employee_id  = fl.employee_id
JOIN dim_transportista dt ON dt.shipper_id   = fl.shipper_id
JOIN dim_geografia     dg ON dg.ciudad   = fl.ship_city
                         AND dg.region   = fl.ship_region
                         AND dg.pais     = fl.ship_country
JOIN product_costos    pc ON pc.product_id   = fl.product_id;

-- 3) Generar dim_metas = promedio histórico mensual + 10% por empleado
INSERT INTO dim_metas (empleado_sk, anio, mes, meta_mensual)
SELECT
    fv.empleado_sk,
    dt.anio,
    dt.mes,
    ROUND(AVG(SUM(fv.venta_neta)) OVER (PARTITION BY fv.empleado_sk) * 1.10, 2)
FROM fact_ventas fv
JOIN dim_tiempo dt ON dt.tiempo_sk = fv.tiempo_sk
GROUP BY fv.empleado_sk, dt.anio, dt.mes;
```

> **Sobre la query de dim_metas:** MySQL no permite `AVG(SUM(...)) OVER (...)` directamente. Si te da error, reemplaza el paso 3 por una versión en 2 pasos:

```sql
-- 3a) Tabla temporal con totales mensuales por empleado
CREATE TEMPORARY TABLE tmp_ventas_mes AS
SELECT fv.empleado_sk, dt.anio, dt.mes, SUM(fv.venta_neta) AS venta_mes
FROM fact_ventas fv
JOIN dim_tiempo dt ON dt.tiempo_sk = fv.tiempo_sk
GROUP BY fv.empleado_sk, dt.anio, dt.mes;

-- 3b) Promedio por empleado * 1.10
INSERT INTO dim_metas (empleado_sk, anio, mes, meta_mensual)
SELECT t.empleado_sk, t.anio, t.mes,
       ROUND(prom.prom_emp * 1.10, 2)
FROM tmp_ventas_mes t
JOIN (
    SELECT empleado_sk, AVG(venta_mes) AS prom_emp
    FROM tmp_ventas_mes GROUP BY empleado_sk
) prom ON prom.empleado_sk = t.empleado_sk;

DROP TEMPORARY TABLE tmp_ventas_mes;
```

10.3. Name: `LOAD fact_ventas + dim_metas`. Auto-terminate: success, failure, retry.

---

## Paso 11 — Validar la bodega completa

11.1. En el DW:
```sql
-- Conteos esperados
SELECT 'fact_ventas' AS tbl, COUNT(*) FROM fact_ventas   -- 2155
UNION ALL SELECT 'dim_cliente',  COUNT(*) FROM dim_cliente   -- 91
UNION ALL SELECT 'dim_producto', COUNT(*) FROM dim_producto  -- 77
UNION ALL SELECT 'dim_empleado', COUNT(*) FROM dim_empleado  -- 9
UNION ALL SELECT 'dim_transportista', COUNT(*) FROM dim_transportista -- 3
UNION ALL SELECT 'dim_geografia',   COUNT(*) FROM dim_geografia
UNION ALL SELECT 'dim_metas',       COUNT(*) FROM dim_metas;

-- Suma total de ventas (cross-check vs fuente)
SELECT ROUND(SUM(venta_neta), 2) AS total_neto FROM fact_ventas;
-- Comparar con SQL Server:
-- SELECT ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2)
-- FROM [Order Details] od;
```
Los dos totales deben coincidir (centavo arriba/abajo por redondeos).

11.2. Una consulta de prueba para cada pregunta de negocio:
```sql
-- Pregunta 1: ventas por año
SELECT t.anio, ROUND(SUM(f.venta_neta), 2) AS total
FROM fact_ventas f JOIN dim_tiempo t ON t.tiempo_sk = f.tiempo_sk
GROUP BY t.anio ORDER BY t.anio;

-- Pregunta 4: top categorías
SELECT p.category_name, ROUND(SUM(f.venta_neta), 2) AS total
FROM fact_ventas f JOIN dim_producto p ON p.producto_sk = f.producto_sk
GROUP BY p.category_name ORDER BY total DESC;

-- Pregunta 8: margen total por producto (top 5)
SELECT p.product_name, ROUND(SUM(f.margen), 2) AS margen_total
FROM fact_ventas f JOIN dim_producto p ON p.producto_sk = f.producto_sk
GROUP BY p.product_name ORDER BY margen_total DESC LIMIT 5;
```
11.3. **CAPTURA:** los conteos + el total cross-check + las 3 consultas.

---

## Paso 12 — Orquestación: corrida End-to-End

12.1. Crea un **GenerateFlowFile maestro** `Trigger Pipeline 2 Completo` → File Size `0B`.
12.2. Conéctalo a TODOS los `Trigger dim_*`, `Trigger fact_landing`, `Trigger product_costos`. Para esto, usa un procesador **DuplicateFlowFile** o crea conexiones múltiples desde el GenerateFlowFile.
12.3. Tras todos los TRUNCATE/LOAD de dimensiones y landing, dispara el `Trigger fact_ventas`. Para sincronizar, usa el procesador **Wait/Notify** o simplemente confía en el orden de Start (las dimensiones cargan rápido).
12.4. **Simplificación pragmática:** en lugar de Wait/Notify, ejecuta manualmente en este orden cada `Trigger X` (Right Click → Run Once):
   1. dim_cliente, dim_producto, dim_empleado, dim_transportista, dim_geografia, product_costos (en paralelo, no importa el orden entre sí)
   2. fact_landing
   3. fact_ventas (y dim_metas)

> Esto es suficiente para la sustentación; la orquestación con Wait/Notify es opcional.

---

## Paso 13 — Exportar Pipeline 2

13.1. Right Click sobre el process group → Download Flow Definition → `nifi-templates\Pipeline_2.json`.

---

## Checklist de cierre de la Fase 4

- [ ] Las 6 dimensiones cargan con conteos correctos
- [ ] `product_costos` tiene 77 filas
- [ ] `fact_landing` tiene 2155 filas
- [ ] `fact_ventas` tiene 2155 filas
- [ ] `dim_metas` tiene N filas (~ 9 empleados × meses con ventas)
- [ ] Sumatoria de venta_neta cuadra con la fuente
- [ ] Las 10 preguntas de negocio retornan datos coherentes con un SELECT exploratorio
- [ ] Pipeline 2 exportado
- [ ] Capturas en `capturas\04\` (mínimo 8)

**"Fase 4 lista"** → pasamos a la Fase 5 (instalar SSAS Tabular).
