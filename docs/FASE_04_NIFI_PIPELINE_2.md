# Fase 4 — Pipeline 2 (Staging → DW) + Transformaciones

**Objetivo:** mover datos del Staging al Data Warehouse aplicando todas las transformaciones (joins, desnormalización, llaves sustitutas, cálculo de medidas, metas, geografía).
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fase 3 completada (Staging poblado con datos correctos, 5 Controller Services Enabled).

> **Importante (NiFi 2.x):** seguimos el mismo enfoque **record-oriented** de la Fase 3. `ExecuteSQLRecord` con `JsonWriter` produce JSON directamente, no hace falta `ConvertAvroToJSON`. Para transformaciones SQL "puras" dentro del DW seguimos usando `PutSQL`.

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

> **Por qué este orden:** las dimensiones deben existir ANTES de resolver las surrogate keys del hecho. `fact_landing` es una zona intermedia con BKs (no SKs); el último paso hace los joins BK→SK dentro del DW.

---

## Paso 1 — Crear el Process Group "Pipeline 2"

1.1. En NiFi, regresa al lienzo raíz ("Back to Parent").
1.2. Arrastra un Process Group → Nombre: `Pipeline 2 - Staging a DW`.
1.3. Doble clic para entrar.

> Reutilizamos los 5 Controller Services creados en Fase 3 (`SQLServer-Northwind-Reader`, `MySQL-Staging`, `MySQL-DW`, `JsonWriter`, `JsonReader`). No hay que crear nada nuevo.

---

## Paso 2 — Cargar `dim_cliente`

Patrón del subflujo (4 procesadores):

```
Trigger → TRUNCATE dim_cliente → EXTRACT stg_customers → LOAD dim_cliente
```

### 2.A — `GenerateFlowFile`: trigger

2.A.1. Arrastra **Processor → GenerateFlowFile**.
2.A.2. Properties: `File Size = 0B`.
2.A.3. Scheduling → Run Schedule: `999 days`.
2.A.4. Name: `Trigger dim_cliente`.

### 2.B — `PutSQL`: vaciar tabla destino

2.B.1. Arrastra **Processor → PutSQL**.
2.B.2. Properties:

| Property | Value |
|---|---|
| JDBC Connection Pool | `MySQL-DW` |
| SQL Statement | `SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE dim_cliente; SET FOREIGN_KEY_CHECKS=1;` |

2.B.3. Name: `TRUNCATE dim_cliente`. Auto-terminate: `failure`, `retry`.

> **FK checks:** los desactivamos porque `fact_ventas` tiene FK a `dim_cliente`. Es seguro porque vamos a limpiar y recargar todo el hecho al final.

### 2.C — `ExecuteSQLRecord`: extraer del Staging como JSON

2.C.1. Arrastra **Processor → ExecuteSQLRecord**.
2.C.2. Properties:

| Property | Value |
|---|---|
| Database Connection Pooling Service | `MySQL-Staging` |
| Record Writer | `JsonWriter` |
| SQL select query | (ver abajo) |
| Max Rows Per Flow File | `0` |
| Normalize Table/Column Names | `false` |

SQL:
```sql
SELECT
  CustomerID  AS customer_id,
  CompanyName AS company_name,
  ContactName AS contact_name,
  City        AS city,
  Country     AS country
FROM stg_customers
```

2.C.3. Name: `EXTRACT stg_customers → dim_cliente`. Auto-terminate: `failure`.

### 2.D — `PutDatabaseRecord`: cargar DW

2.D.1. Arrastra **Processor → PutDatabaseRecord**.
2.D.2. Properties:

| Property | Value |
|---|---|
| Record Reader | `JsonReader` |
| Statement Type | `INSERT` |
| Database Connection Pooling Service | `MySQL-DW` |
| Schema Name | `dw_northwind` |
| Table Name | `dim_cliente` |
| Translate Field Names | `true` |
| Unmatched Field Behavior | `Ignore Unmatched Fields` |
| Unmatched Column Behavior | `Ignore Unmatched Columns` |

2.D.3. Name: `LOAD dim_cliente`. Auto-terminate: `success`, `failure`, `retry`.

### 2.E — Conectar y probar

2.E.1. Conecta: Trigger → TRUNCATE → EXTRACT → LOAD (todos por `success`).
2.E.2. Start sobre los 4 procesadores → Run Once en `Trigger dim_cliente`.
2.E.3. Valida en DBeaver (DW):
```sql
SELECT COUNT(*) FROM dim_cliente;  -- esperado: 91
SELECT * FROM dim_cliente LIMIT 5;
```
2.E.4. **CAPTURA:** subflujo + resultado.

---

## Paso 3 — Cargar `dim_producto` (con desnormalización)

Mismo patrón de 4 procesadores. Cambia el query y el destino.

3.1. Trigger + TRUNCATE igual que el paso 2.
3.2. **ExecuteSQLRecord** (pool `MySQL-Staging`, writer `JsonWriter`):
```sql
SELECT
  p.ProductID    AS product_id,
  p.ProductName  AS product_name,
  c.CategoryName AS category_name,
  s.CompanyName  AS supplier_name,
  s.Country      AS supplier_country,
  p.UnitPrice    AS unit_price,
  p.Discontinued AS discontinued
FROM stg_products p
LEFT JOIN stg_categories c ON c.CategoryID = p.CategoryID
LEFT JOIN stg_suppliers  s ON s.SupplierID = p.SupplierID
```
3.3. PutDatabaseRecord destino `dim_producto`.
3.4. Validar:
```sql
SELECT COUNT(*) FROM dim_producto;     -- 77
SELECT product_name, category_name, supplier_name FROM dim_producto LIMIT 5;
```

---

## Paso 4 — Cargar `dim_empleado` (con concatenación)

4.1. Trigger + TRUNCATE.
4.2. ExecuteSQLRecord:
```sql
SELECT
  EmployeeID                          AS employee_id,
  CONCAT(FirstName, ' ', LastName)    AS nombre_completo,
  Title                               AS titulo,
  Country                             AS pais,
  HireDate                            AS fecha_contratacion
FROM stg_employees
```
4.3. PutDatabaseRecord → `dim_empleado`.
4.4. Validar:
```sql
SELECT COUNT(*) FROM dim_empleado;   -- 9
SELECT nombre_completo FROM dim_empleado;
```

---

## Paso 5 — Cargar `dim_transportista`

5.1. Trigger + TRUNCATE.
5.2. ExecuteSQLRecord:
```sql
SELECT ShipperID AS shipper_id, CompanyName AS company_name FROM stg_shippers
```
5.3. PutDatabaseRecord → `dim_transportista`.
5.4. Validar: 3 filas.

---

## Paso 6 — Cargar `dim_geografia` (con manejo de nulos)

La geografía se deriva de los campos `Ship*` de Orders.

6.1. Trigger + TRUNCATE.
6.2. ExecuteSQLRecord (pool `MySQL-Staging`):
```sql
SELECT DISTINCT
  COALESCE(ShipCity,    'No especificado') AS ciudad,
  COALESCE(ShipRegion,  'No especificado') AS region,
  COALESCE(ShipCountry, 'No especificado') AS pais
FROM stg_orders
```
6.3. PutDatabaseRecord → `dim_geografia`.
6.4. Validar:
```sql
SELECT COUNT(*) FROM dim_geografia;   -- típicamente 70-80 combinaciones únicas
SELECT * FROM dim_geografia ORDER BY pais, ciudad LIMIT 10;
```

---

## Paso 7 — Cargar `product_costos`

7.1. Trigger + TRUNCATE.
7.2. ExecuteSQLRecord (pool `MySQL-Staging`):
```sql
SELECT
  ProductID                  AS product_id,
  ROUND(UnitPrice * 0.60, 2) AS costo_unitario
FROM stg_products
```
7.3. PutDatabaseRecord → `product_costos`.
7.4. Validar: 77 filas.

---

## Paso 8 — Cargar `fact_landing` (zona intermedia con BKs)

Aquí materializamos el join Order Details ⋈ Orders con todas las claves de negocio.

8.1. Trigger + TRUNCATE de `fact_landing`.
8.2. ExecuteSQLRecord (pool `MySQL-Staging`):
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
8.3. PutDatabaseRecord → `fact_landing`.
8.4. Validar: **2155** filas.

---

## Paso 9 — Resolución de SK y carga de `fact_ventas` + `dim_metas`

Este es el corazón de las transformaciones. Se ejecuta como SQL set-based dentro del DW (no record-oriented porque es lógica de negocio en una sola transacción).

9.1. **GenerateFlowFile** → Name `Trigger fact_ventas` → File Size `0B` → Run Schedule `999 days`.

9.2. **PutSQL** (pool `MySQL-DW`, con `allowMultiQueries=true` desde Fase 3) → SQL Statement:

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

-- 3) Generar dim_metas en 2 pasos (MySQL no permite AVG(SUM()) OVER directo)
CREATE TEMPORARY TABLE tmp_ventas_mes AS
SELECT fv.empleado_sk, dt.anio, dt.mes, SUM(fv.venta_neta) AS venta_mes
FROM fact_ventas fv
JOIN dim_tiempo dt ON dt.tiempo_sk = fv.tiempo_sk
GROUP BY fv.empleado_sk, dt.anio, dt.mes;

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

9.3. Name: `LOAD fact_ventas + dim_metas`. Auto-terminate: success, failure, retry.

---

## Paso 10 — Validar la bodega completa

10.1. En el DW:
```sql
-- Conteos esperados
SELECT 'fact_ventas' AS tbl, COUNT(*) FROM fact_ventas        -- 2155
UNION ALL SELECT 'dim_cliente',  COUNT(*) FROM dim_cliente    -- 91
UNION ALL SELECT 'dim_producto', COUNT(*) FROM dim_producto   -- 77
UNION ALL SELECT 'dim_empleado', COUNT(*) FROM dim_empleado   -- 9
UNION ALL SELECT 'dim_transportista', COUNT(*) FROM dim_transportista -- 3
UNION ALL SELECT 'dim_geografia',   COUNT(*) FROM dim_geografia
UNION ALL SELECT 'dim_metas',       COUNT(*) FROM dim_metas;

-- Cross-check: suma total de ventas
SELECT ROUND(SUM(venta_neta), 2) AS total_neto FROM fact_ventas;
-- Comparar contra SQL Server:
-- SELECT ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2)
-- FROM [Order Details] od;
```
Los dos totales deben coincidir (centavo arriba/abajo por redondeos).

10.2. Una consulta de prueba para algunas preguntas de negocio:
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
10.3. **CAPTURA:** los conteos + el total cross-check + las 3 consultas.

---

## Paso 11 — Orquestación: corrida End-to-End

11.1. **Simplificación pragmática:** en lugar de coordinar con Wait/Notify, dispara manualmente cada trigger en este orden:
   1. `Trigger dim_cliente`, `Trigger dim_producto`, `Trigger dim_empleado`, `Trigger dim_transportista`, `Trigger dim_geografia`, `Trigger product_costos` (orden libre entre sí — todos cargan a tablas distintas)
   2. `Trigger fact_landing` (una vez las dimensiones estén)
   3. `Trigger fact_ventas` (que también genera `dim_metas`)

11.2. Si quieres automatizarlo, NiFi 2.x permite encadenar con **Wait + Notify** o usando un único `GenerateFlowFile` maestro que se conecte a todos los triggers con `DuplicateFlowFile`. Para esta sustentación, disparar manualmente es suficiente.

---

## Paso 12 — Exportar Pipeline 2

12.1. En el lienzo raíz, clic derecho sobre el Process Group `Pipeline 2 - Staging a DW` → **Download flow definition** → guarda como `nifi-templates\Pipeline_2.json`.

---

## Checklist de cierre de la Fase 4

- [ ] Las 6 dimensiones cargan con conteos correctos
- [ ] `product_costos` tiene 77 filas
- [ ] `fact_landing` tiene 2155 filas
- [ ] `fact_ventas` tiene 2155 filas
- [ ] `dim_metas` tiene N filas (~ 9 empleados × meses con ventas)
- [ ] Sumatoria de `venta_neta` cuadra con la fuente
- [ ] Las consultas de prueba retornan datos coherentes
- [ ] Pipeline 2 exportado a `nifi-templates\Pipeline_2.json`
- [ ] Capturas en `capturas\04\` (mínimo 8)

## Resumen del cambio respecto a NiFi 1.x

| Antes (NiFi 1.x) | Ahora (NiFi 2.x) |
|---|---|
| ExecuteSQL → ConvertAvroToJSON → PutDatabaseRecord | **ExecuteSQLRecord** (con `JsonWriter`) → PutDatabaseRecord |
| 5 procesadores por dimensión | **4 procesadores** por dimensión |
| Templates `.xml` (legacy) | Flow Definitions `.json` |

**"Fase 4 lista"** → pasamos a la Fase 5 (instalar SSAS Tabular).
