# Guía de defensa — Proyecto BI Northwind

Documento de referencia para la sustentación. Contiene:
- 9 preguntas técnicas frecuentes del jurado con respuestas defendibles.
- Las 10 preguntas de negocio + dónde se responde cada una en Tableau.

---

## Parte 1 — Preguntas técnicas

### 1. ¿Para qué se usa ShipName?

`ShipName` es el **nombre del destinatario que va en la etiqueta del paquete**. En Northwind no siempre coincide con el `CustomerName` porque un cliente puede pedir que la mercancía se entregue a otra empresa o persona (drop-shipping, oficina alterna, regalo a un tercero, etc.).

**En el modelo dimensional NO lo propagamos** porque para análisis BI no aporta valor: la entidad analíticamente relevante es el cliente que paga (`dim_cliente`), no el receptor físico. `ShipName` se queda en `staging_northwind.stg_orders` como dato crudo de la fuente; no llega ni a `fact_landing` ni a `fact_ventas`.

**Dónde verlo:**
- Fuente SQL Server: `Orders.ShipName` (Northwind).
- Staging: `staging_northwind.stg_orders.ShipName`.

### 2. ¿Dónde se configura el horario del ETL?

**En el estado actual:** los Triggers (`GenerateFlowFile`) están en modo manual con `Run Schedule = 999 day`. Esto permite ejecutarlos solo con **Run Once** para demostrar el flujo durante la sustentación, sin que se disparen solos.

**Para programar a las 02:00 AM diario en producción**, en cada Trigger:

| Property | Valor |
|---|---|
| Scheduling Strategy | **CRON driven** |
| Run Schedule | `0 0 2 * * ?` |

Esa expresión Quartz CRON significa "segundo 0, minuto 0, hora 2, todos los días, todos los meses, cualquier día de la semana".

**Dónde se ve en el repo:**
- `nifi-templates/Pipeline_1.json`: cada procesador `GenerateFlowFile` tiene la propiedad `schedulingPeriod`. Actualmente vale `"999 days"`; cambiarla a `"0 0 2 * * ?"` con `schedulingStrategy: "CRON_DRIVEN"`.
- Procesador a configurar primero: **Trigger Categories**, **Trigger fact_ventas** (los demás se encadenan).

### 3. ¿Dónde se hace el cargue de la tabla más pesada?

La tabla más pesada en filas es `stg_order_details` con **2155 filas** (la transaccional con un registro por línea de pedido).

**Cómo se carga** (`docs/FASE_03_NIFI_PIPELINE_1.md`, paso 8.B):

```
EXTRACT Order Details (incremental) → LOAD stg_order_details
       QueryDatabaseTableRecord          PutDatabaseRecord
```

- **EXTRACT**: `QueryDatabaseTableRecord` 2.0.0
  - Database Connection: `SQLServer-Northwind-Reader`
  - Table Name: `[Order Details]` (con corchetes porque "Order" es palabra reservada en SQL Server)
  - Maximum-value Columns: `OrderID` (watermark para carga incremental)
  - Database Type: `MS SQL 2012+`
- **LOAD**: `PutDatabaseRecord` 2.0.0
  - JDBC Connection: `MySQL-Staging`
  - Schema: `staging_northwind`, Table: `stg_order_details`
  - Statement Type: `INSERT`

**Tamaño en disco:** ~350 KB por corrida full. Se transfiere en JSON via `JsonRecordSetWriter` + `JsonTreeReader` (patrón record-oriented NiFi 2.x).

### 4. ¿Dónde se hace el cargue de la tabla Orders al staging?

**`docs/FASE_03_NIFI_PIPELINE_1.md`, paso 8.A**. Subflujo de **2 procesadores** (incremental, no tiene TRUNCATE):

```
EXTRACT Orders (incremental) → LOAD stg_orders
   QueryDatabaseTableRecord        PutDatabaseRecord
```

- **EXTRACT**: `QueryDatabaseTableRecord`
  - Table Name: `Orders`
  - Columns to Return: `OrderID, CustomerID, EmployeeID, OrderDate, RequiredDate, ShippedDate, ShipVia, Freight, ShipName, ShipAddress, ShipCity, ShipRegion, ShipPostalCode, ShipCountry`
  - Maximum-value Columns: `OrderID`
- **LOAD**: `PutDatabaseRecord` a `staging_northwind.stg_orders`.

Resultado: **830 filas** en staging. Validable con:
```sql
SELECT COUNT(*) FROM staging_northwind.stg_orders;   -- 830
```

### 5. Tabla que pasa del ETL al staging (EXTRACT)

El **Pipeline 1** copia las **8 tablas espejo** de SQL Server → MySQL Staging sin transformar. Es un "espejo 1:1" deliberadamente.

| Tabla en SQL Server | Tabla en `staging_northwind` (MySQL 3307) | Filas |
|---|---|---|
| Categories | stg_categories | 8 |
| Suppliers | stg_suppliers | 29 |
| Products | stg_products | 77 |
| Customers | stg_customers | 91 |
| Employees | stg_employees | 9 |
| Shippers | stg_shippers | 3 |
| Orders | stg_orders | 830 |
| Order Details | stg_order_details | 2155 |
| **Total** | | **3202** |

Validación combinada:
```sql
SELECT 'stg_categories' tbl, COUNT(*) n FROM stg_categories
UNION ALL SELECT 'stg_suppliers', COUNT(*) FROM stg_suppliers
UNION ALL SELECT 'stg_products', COUNT(*) FROM stg_products
UNION ALL SELECT 'stg_customers', COUNT(*) FROM stg_customers
UNION ALL SELECT 'stg_employees', COUNT(*) FROM stg_employees
UNION ALL SELECT 'stg_shippers', COUNT(*) FROM stg_shippers
UNION ALL SELECT 'stg_orders', COUNT(*) FROM stg_orders
UNION ALL SELECT 'stg_order_details', COUNT(*) FROM stg_order_details;
```

### 6. Al staging no hay que hacerle transformaciones, pasa crudo

**Correcto.** Ese es un principio de Kimball: el **staging es un buffer fiel a la fuente**. No se aplican joins, agregaciones, limpieza ni renombres. Las únicas "transformaciones" aceptables en Pipeline 1 son:
- **Casting de tipos** que la fuente no maneja bien al exportar (ej. `CONVERT(VARCHAR(10), BirthDate, 23)` para evitar el bug de timestamps en milisegundos al cargar fechas a MySQL).
- **Casting de columnas binarias largas** (ej. `CAST(Notes AS NVARCHAR(MAX))`) porque NiFi no maneja `ntext` directo.

Estos castings son **adaptación de formato, no transformación de negocio**. La estructura, los nombres de columnas y los valores se preservan idénticos a la fuente.

**Las transformaciones de negocio** (joins, desnormalización, surrogate keys, cálculo de medidas) ocurren en **Pipeline 2** (Staging → DW), siguiendo la arquitectura medallion.

### 7. ¿Dónde está el LOAD al staging?

Los **8 procesadores LOAD** de Pipeline 1 son cada uno un `PutDatabaseRecord` 2.0.0 con esta configuración:

| Property | Value |
|---|---|
| Record Reader | `JsonReader` (JsonTreeReader) |
| Statement Type | `INSERT` |
| Database Connection Pooling Service | `MySQL-Staging` |
| Schema Name | `staging_northwind` |
| Table Name | (el `stg_*` correspondiente) |
| Translate Field Names | `true` |
| Unmatched Field Behavior | `Ignore Unmatched Fields` |
| Unmatched Column Behavior | `Ignore Unmatched Columns` |

**Auto-terminate**: `success`, `failure`, `retry` (los 3) — el LOAD es el final de la cadena.

**Listado de los 8 LOAD en `nifi-templates/Pipeline_1.json`:**
- LOAD stg_categories
- LOAD stg_suppliers
- LOAD stg_products
- LOAD stg_customers
- LOAD stg_employees
- LOAD stg_shippers
- LOAD stg_orders
- LOAD stg_order_details

### 8. ¿Cómo se construye la dimensión tiempo?

`dim_tiempo` es la **única dimensión NO derivada de la fuente** — se construye **programáticamente** porque las dimensiones de tiempo son universales (no dependen de Northwind).

**Stored procedure** en MySQL DW (`docs/FASE_02_MYSQL_STAGING_DW.md`, paso 6):

```sql
DELIMITER //
CREATE PROCEDURE sp_poblar_dim_tiempo()
BEGIN
    DECLARE v_fecha DATE DEFAULT '1994-01-01';
    DECLARE v_fin   DATE DEFAULT '1999-12-31';

    WHILE v_fecha <= v_fin DO
        INSERT IGNORE INTO dim_tiempo (
            tiempo_sk, fecha, anio, trimestre, mes, nombre_mes,
            dia, dia_semana, nombre_dia, es_fin_semana
        ) VALUES (
            CAST(DATE_FORMAT(v_fecha, '%Y%m%d') AS UNSIGNED),  -- SK = 19960704
            v_fecha,
            YEAR(v_fecha),
            QUARTER(v_fecha),
            MONTH(v_fecha),
            MONTHNAME(v_fecha),
            DAY(v_fecha),
            DAYOFWEEK(v_fecha),
            DAYNAME(v_fecha),
            IF(DAYOFWEEK(v_fecha) IN (1,7), 1, 0)
        );
        SET v_fecha = DATE_ADD(v_fecha, INTERVAL 1 DAY);
    END WHILE;
END //
DELIMITER ;

CALL sp_poblar_dim_tiempo();
```

**Resultado**: **2191 filas** (6 años × 365 + 1 bisiesto en 1996).

**Decisiones de diseño defendibles:**
- **Smart key entera (`tiempo_sk = 19960704`)**: legible, ordenable, indexable, 8 bytes mínimo. Mejor que un `INT IDENTITY` ciego.
- **Rango 1994-1999**: cubre Northwind (1996-1998) con margen para datos futuros. Buena práctica: nunca quedarse corto.
- **`INSERT IGNORE`**: idempotente — si la corres 2 veces no duplica.
- **Atributos pre-calculados**: año, trimestre, mes, nombre de día, fin de semana → evita cálculos en runtime en Tableau/Excel.

### 9. ¿Qué hace el ETL por cada tabla del staging?

Cada tabla del staging tiene su **subflujo de 4 procesadores** en Pipeline 1 (excepto Orders y Order Details que tienen 2 — incremental):

```
GenerateFlowFile → PutSQL          → ExecuteSQLRecord → PutDatabaseRecord
   (Trigger)        (TRUNCATE)        (EXTRACT)         (LOAD)
```

**Detalle del comportamiento por procesador:**

| # | Procesador | Función | Pool |
|---|---|---|---|
| 1 | Trigger | Genera un FlowFile vacío que dispara la cadena. Run Schedule = 999 day para control manual. | - |
| 2 | TRUNCATE | Vacía la tabla destino. Ejecuta `TRUNCATE TABLE stg_<tabla>;`. | MySQL-Staging |
| 3 | EXTRACT | Lee la tabla fuente en SQL Server y la serializa como JSON. | SQLServer-Northwind-Reader |
| 4 | LOAD | Recibe el JSON y hace INSERT batch en la tabla MySQL. Auto-commit=false (transaccional). | MySQL-Staging |

**Para Orders y Order Details:**
- NO hay TRUNCATE (incremental).
- EXTRACT es `QueryDatabaseTableRecord` (maneja watermark sobre `OrderID`).
- Si hay nuevos pedidos en la fuente, solo trae los nuevos. Si no hay, no hace nada (idempotente).

**Política de errores:**
- En `failure` y `retry` → auto-terminate (descarta el FlowFile, bulletin rojo en la UI).
- En `success` → siguiente procesador de la cadena.

---

## Parte 2 — Las 10 preguntas de negocio (Tableau)

| # | Pregunta | Hoja Tableau | Estado |
|---|---|---|---|
| 1 | Ventas por periodo (mes/año, 5 años) | `Q1_Ventas_Por_Periodo` | ✓ Cubierta |
| 2 | Top 10 clientes y su comportamiento | `Q2_Top10_Clientes` | ✓ Cubierta |
| 3 | Productos más vendidos + contribución | `Q3_Productos_Top` | ✓ Cubierta |
| 4 | Categorías con más ingresos + tendencia | `Q4_Categorias` | ✓ Cubierta |
| 5 | Empleados vs metas | `Q5_Empleados_vs_Metas` | ⚠ Cubierta con caveat |
| 6 | Territorios — regiones/países | `Q6_Territorios` | ✓ Cubierta |
| 7 | Tiempos de entrega | `Q7_Tiempos_Entrega` | ✓ Cubierta |
| 8 | Margen de rentabilidad por producto | `Q8_Margen_Producto` | ✓ Cubierta |
| 9 | Clientes inactivos | `Q9_Clientes_Activos` | ⚠ Requiere ajuste |
| 10 | Estacionalidad por trimestre/mes | `Q10_Estacionalidad` | ✓ Cubierta |

### Detalle por pregunta

#### Pregunta 1 — Ventas por periodo
**Hoja**: `Q1_Ventas_Por_Periodo`
**Cómo responde**: línea de Ventas Netas con jerarquía Año › Mes en Columnas. Muestra evolución del valor mensual durante 1996, 1997 y 1998 (Northwind cubre 23 meses).
**Filtros sugeridos**: Año (multi-select), País.
**Qué decir**: "Pasamos de ~28k en julio 1996 (inicio operaciones) a picos de ~125k en abril 1998. Crecimiento sostenido año a año."

#### Pregunta 2 — Top 10 Clientes
**Hoja**: `Q2_Top10_Clientes`
**Cómo responde**: barra horizontal de los 10 clientes con mayor `Ventas Netas`. Color gradient por intensidad.
**Filtros sugeridos**: Año, País del cliente.
**Qué decir**: "QUICK-Stop, Save-a-lot Markets y Ernst Handel son los top 3 con >100k cada uno. El filtro de Año permite ver si su comportamiento cambió entre 1996, 1997, 1998."

#### Pregunta 3 — Productos más vendidos + contribución
**Hoja**: `Q3_Productos_Top`
**Cómo responde**: Top 15 productos por Cantidad Vendida con etiqueta de `% Contribucion` al lado.
**Qué decir**: "Camembert Pierrot lidera con 1,577 unidades vendidas (5.62% del total). Top 5 representa ~20% del volumen — distribución larga (long tail)."

#### Pregunta 4 — Categorías
**Hoja**: `Q4_Categorias`
**Cómo responde**: treemap con tamaño = Ventas Netas, color por categoría, etiqueta con `% Contribucion`.
**Qué decir**: "Beverages 21.16% y Dairy Products 18.53% concentran ~40% de las ventas. Grains/Cereals y Produce las menores con ~7-8% cada una."
**Tendencia histórica**: agregar a la hoja un filtro de Año o duplicarla y usar líneas por año.

#### Pregunta 5 — Eficiencia de empleados vs metas ⚠
**Hoja**: `Q5_Empleados_vs_Metas`
**Cómo responde**: barras de Ventas Netas vs Meta Mensual por empleado, etiqueta con `Cumplimiento Meta %`.

**⚠ Caveat importante para la sustentación:**
El `Cumplimiento Meta %` muestra **90.91% para TODOS los empleados** cuando se mira en agregado total. Esto NO es un error — es resultado del diseño de `dim_metas`:

```
meta_mensual = AVG(venta_neta_mensual) × 1.10
```

Por construcción, la meta total es 110% de la venta total → cumplimiento = 1/1.10 = 90.91%.

**Cómo responder si el jurado pregunta:**
- Filtra por **un mes y año específico** (ej. abril 1998): ahí sí ves variación real (algunos empleados >100%, otros <80%).
- Explica: "La meta se calculó como el promedio histórico × 1.10. Para evaluar cumplimiento es necesario comparar mes a mes, no en agregado total. En la vista mensual, Margaret Peacock y Janet Leverling consistentemente superan meta; Steven Buchanan y Michael Suyama están por debajo."

**Filtros recomendados**: Año, Mes (obligatorios para que la métrica sea útil).

#### Pregunta 6 — Territorios
**Hoja**: `Q6_Territorios`
**Cómo responde**: mapa mundial con burbujas. Tamaño = Cantidad Vendida, color = Ventas Netas.
**Qué decir**: "Estados Unidos y Alemania son los mercados dominantes. Latam tiene presencia mínima (Brasil, Venezuela, México) — oportunidad de crecimiento."

#### Pregunta 7 — Tiempos de entrega
**Hoja**: `Q7_Tiempos_Entrega`
**Cómo responde**: barras de `Dias Entrega Promedio` por país, ordenadas descendente. Línea de referencia con el promedio global.
**Qué decir**: "Ireland tarda ~12 días en promedio (el peor), Finland 5.3 días (el mejor). Promedio global ~8.5 días. Oportunidad de mejora en países con alto tiempo."

#### Pregunta 8 — Margen de rentabilidad
**Hoja**: `Q8_Margen_Producto`
**Cómo responde**: Top 15 productos por `Margen Total` con color gradient por % contribución.
**Qué decir**: "Côte de Blaye lidera con ~45k de margen — alto precio unitario aunque no es top en cantidad. Estrategia premium. Thüringer Rostbratwurst y Raclette Courdavault completan el podio."
**Recordar**: el costo es supuesto al 60% del UnitPrice (ver `product_costos` en FASE_02 paso 7), no es real de Northwind.

#### Pregunta 9 — Clientes inactivos ⚠ REQUIERE AJUSTE
**Estado actual**: `Q9_Clientes_Activos` muestra KPIs de Ventas Netas Totales y Cantidad Vendida — NO responde la pregunta de "clientes inactivos".

**Cómo arreglarlo (15 minutos en Tableau)**:

1. Renombra la hoja a `Q9_Clientes_Inactivos`.
2. Borra los campos actuales (Ventas Netas, Cantidad Vendida del cuadro Texto).
3. Crea un campo calculado:
   - **Análisis → Crear campo calculado** → Nombre: `Ultima Compra`
   - Fórmula: `{ FIXED [customer_id]: MAX([fecha]) }`
   - OK.
4. Crea otro campo calculado:
   - Nombre: `Dias Desde Ultima Compra`
   - Fórmula: `DATEDIFF('day', [Ultima Compra], #1998-05-06#)`
   - OK.
5. Crea un tercer:
   - Nombre: `Estado Cliente`
   - Fórmula: `IF [Dias Desde Ultima Compra] > 365 THEN "Inactivo" ELSEIF [Dias Desde Ultima Compra] > 180 THEN "En riesgo" ELSE "Activo" END`
   - OK.
6. Construye la hoja:
   - Filas: `dim_cliente[company_name]`
   - Columnas: `Dias Desde Ultima Compra`
   - Color: `Estado Cliente`
   - Filtro: `Estado Cliente` → marca "Inactivo" y "En riesgo"
7. Adicional: arrastra `Ventas Netas` al cuadro **Etiqueta** para mostrar el impacto en ventas que tiene cada cliente perdido.

**Qué decir en la defensa**:
"Identificamos N clientes inactivos (>365 días sin compra) y M en riesgo (180-365 días). El impacto en ventas globales se calcula como la suma de ventas históricas de los inactivos — aproximadamente X% del total. Recomendación: campaña de re-engagement para los del segmento 'En riesgo'."

#### Pregunta 10 — Estacionalidad
**Hoja**: `Q10_Estacionalidad`
**Cómo responde**: heatmap Año × Mes con color por Ventas Netas.
**Qué decir**: "Pico claro en abril 1998 (~125k) y noviembre-diciembre 1997 (cierre de año). Caída típica en mes 5-6 de cada año. Patrón sugiere estacionalidad asociada a celebraciones europeas y fin de año fiscal."

---

## Resumen de ajustes a hacer antes de la sustentación

1. ⚠ **Arreglar Q9 a "Clientes Inactivos"** según las instrucciones del punto 9. **15 minutos.**
2. ⚠ **En Q5**, agregar filtro obligatorio de Año + Mes y mostrar la vista filtrada por un mes específico para que el % de cumplimiento muestre variación real.
3. ✓ Las demás 8 hojas están bien.
4. ✓ Los 3 dashboards (Resumen, Clientes/Productos, Operaciones) están bien.

---

## Cross-check final (validación de datos)

Para la sustentación, ten listo este SELECT contra el DW (cualquier conexión MySQL DW por DBeaver):

```sql
SELECT ROUND(SUM(venta_neta), 2) AS total_neto FROM dw_northwind.fact_ventas;
-- Esperado: 1,265,793.04
```

Y este contra la fuente SQL Server:

```sql
USE Northwind;
SELECT ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS total_fuente
FROM [Order Details] od;
-- Esperado: 1,265,793.04 (mismos valores → ETL no perdió ni distorsionó datos)
```

Si los 2 números coinciden, **el ETL está validado** y eso responde a cualquier pregunta del jurado sobre "¿cómo sabemos que está bien?"
