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

---

## Parte 1.B — El modelo semántico y el cuarto servidor (SSAS Tabular)

Esta es probablemente la pregunta más exigente del jurado: "¿por qué un cuarto servidor solo para análisis?". Tener una respuesta clara y técnica suma puntos.

### ¿Qué es un modelo semántico?

Un **modelo semántico** es una capa lógica de negocio que se monta encima de un Data Warehouse físico. Su rol:

| Aspecto | DW físico (MySQL) | Modelo semántico (SSAS Tabular) |
|---|---|---|
| Almacenamiento | Tablas relacionales en disco | Compresión columnar en memoria (Vertipaq) |
| Estructura visible | Tablas con FK | "Cubo" con dimensiones, medidas y jerarquías |
| Lenguaje | SQL (relacional) | DAX (analítico) y MDX (multidimensional) |
| Optimización | Para escrituras transaccionales | Para agregaciones masivas |
| Reglas de negocio | Cada herramienta calcula a su modo | Centralizadas como medidas DAX → resultados idénticos en todos los reportes |
| Audiencia | DBA / desarrolladores | Analistas / usuarios finales |

En resumen: el DW es el "depósito de hechos", el modelo semántico es la "vista de negocio amigable" donde Ventas Netas, Margen y Cumplimiento Meta significan **exactamente lo mismo** sin importar quién pregunte ni desde qué herramienta.

### ¿Por qué un cuarto servidor solo para SSAS?

**Argumento 1 — Separación de responsabilidades (Single Responsibility Principle aplicado a infraestructura):**

| Servidor | Rol único | Optimización |
|---|---|---|
| 1. SQL Server (Northwind) | OLTP fuente | Transacciones rápidas, integridad |
| 2. MySQL Staging | Buffer ETL | Escritura masiva sin restricciones |
| 3. MySQL DW | Bodega histórica | Schema estrella, consultas analíticas SQL |
| 4. SSAS Tabular | Capa semántica | Agregaciones in-memory, DAX, jerarquías |

Cada servidor está afinado para un patrón de carga distinto. Mezclarlos en uno solo obliga a comprometer la afinación de todos.

**Argumento 2 — Performance (in-memory vs. disco):**

SSAS Tabular usa **Vertipaq**, un motor columnar comprimido residente en RAM. Cuando Tableau pide "Ventas Netas por categoría y mes", SSAS responde en **decenas de milisegundos** porque:
1. Los datos están comprimidos 10-15x en RAM (no toca disco).
2. Las agregaciones son nativas (no recorre filas, opera sobre vectores).
3. Las jerarquías de tiempo están pre-indexadas para drill-down.

Si Tableau preguntara directamente al MySQL DW, cada query sería un `JOIN + GROUP BY + SUM` recorriendo 2155 filas en disco. Bien para una tabla, mal para un dashboard con 8 visualizaciones simultáneas.

**Argumento 3 — Lógica de negocio centralizada:**

Las 10 medidas DAX (`Ventas Netas`, `Cumplimiento Meta %`, `% Contribucion`, etc.) viven dentro del modelo. Si mañana cambia la definición de "Ventas Netas" (ej. excluir devoluciones), se modifica **un solo lugar** y todos los reportes actualizan. Si en cambio cada herramienta calculara su propia fórmula en SQL, habría inconsistencias entre Tableau, Excel y Power BI.

**Argumento 4 — Escalabilidad de usuarios:**

El modelo Tabular soporta **decenas de usuarios concurrentes** consultando dashboards sin degradar el rendimiento del DW. Sin SSAS, cada vista de Tableau dispararía SQL contra el DW, saturando conexiones y bloqueos. Con SSAS, el DW solo se toca cuando se refresca el modelo (1 vez al día), no en cada consulta de usuario.

**Argumento 5 — Compatibilidad ecosistema Microsoft + Tableau:**

SSAS Tabular es el estándar de facto para conexión BI en Windows. Tableau, Power BI, Excel, todos hablan **nativamente con SSAS** vía XMLA/MDX. No necesitas conectores extra, drivers ODBC ni configuraciones por usuario — Tableau ve un cubo y arrastras campos.

### ¿Dónde está el modelo semántico?

**Localización física:**

| | |
|---|---|
| Servidor | `localhost\TABULAR` (o `KARASU\TABULAR`) |
| Base de datos SSAS | `Northwind_Semantico` |
| Proceso del SO | `msmdsrv.exe` (Microsoft Multidimensional Server) |
| Ruta de datos | `C:\Program Files\Microsoft SQL Server\MSAS17.TABULAR\OLAP\Data` |
| Puerto | Dinámico vía SQL Server Browser (instancia nombrada) |

**Definición versionada en el repo:**

| Archivo | Qué contiene |
|---|---|
| `ssas/01_create_modelo.xmla` | TMSL/XMLA que crea el modelo: 8 tablas, 7 relaciones, 10 medidas DAX, data source apuntando al DSN `DW_NORTHWIND` (System.Data.Odbc) |
| `ssas/02_procesar_modelo.xmla` | Comando `refresh` que carga las filas desde MySQL DW |
| `ssas/config_servidor_4.md` | Documentación completa del Servidor 4 |

**Cómo se construyó (decisión de diseño defendible):**

El proyecto NO usó la ruta tradicional de Visual Studio + SQL Server Data Tools porque la versión 2022+ tiene un bug conocido con conexiones ODBC a MySQL (el wizard usa un proceso 32-bit y rechaza los modos de impersonación válidos para Tabular 1500+). En lugar de eso:

1. Se escribió el modelo directamente en **TMSL** (formato JSON nativo de SSAS).
2. Se desplegó vía **SSMS 19 → XMLA Query → F5**.
3. El archivo `01_create_modelo.xmla` queda en el repo como **fuente de verdad** — el modelo se puede reconstruir desde cero en cualquier máquina con SSAS Tabular instalado.

**Es más limpio que el approach con Visual Studio porque:**
- El modelo es código versionado (Git diff muestra cualquier cambio).
- Reproducible: un nuevo desarrollador clona el repo y deploya con 2 clics.
- Sin dependencia de IDE específico.

### Componentes del modelo semántico Northwind

Para defender ante el jurado qué hay dentro:

**8 tablas** (importadas del DW vía DSN):

```
fact_ventas         2,155 filas    (hechos: una venta = una línea de pedido)
dim_tiempo          2,191 filas    (calendario 1994-1999)
dim_cliente         91             (clientes Northwind)
dim_producto        77             (catálogo desnormalizado: producto + categoría + proveedor)
dim_empleado        9              (vendedores)
dim_geografia       ~70            (combinaciones únicas ciudad/región/país)
dim_transportista   3              (Speedy Express, United Package, Federal Shipping)
dim_metas           192            (metas por empleado/año/mes calculadas)
```

**7 relaciones** (esquema estrella):

```
fact_ventas[tiempo_sk]        → dim_tiempo[tiempo_sk]
fact_ventas[cliente_sk]       → dim_cliente[cliente_sk]
fact_ventas[producto_sk]      → dim_producto[producto_sk]
fact_ventas[empleado_sk]      → dim_empleado[empleado_sk]
fact_ventas[geografia_sk]     → dim_geografia[geografia_sk]
fact_ventas[transportista_sk] → dim_transportista[transportista_sk]
dim_metas[empleado_sk]        → dim_empleado[empleado_sk]
```

Todas son **many-to-one** (cardinalidad clásica de estrella).

**10 medidas DAX** centralizadas en `fact_ventas`:

| # | Medida | Fórmula resumida |
|---|---|---|
| 1 | Ventas Netas | `SUM(venta_neta)` |
| 2 | Ventas Año Anterior | `CALCULATE([Ventas Netas], SAMEPERIODLASTYEAR(fecha))` |
| 3 | Ventas YoY % | `DIVIDE([V.Act] - [V.Ant], [V.Ant])` |
| 4 | Cantidad Vendida | `SUM(cantidad)` |
| 5 | % Contribución | `DIVIDE([V.Netas], CALCULATE([V.Netas], ALL))` |
| 6 | Meta Mensual | `SUM(dim_metas[meta_mensual])` |
| 7 | Cumplimiento Meta % | `DIVIDE([V.Netas], [Meta Mensual])` |
| 8 | Días Entrega Promedio | `AVERAGEX(FILTER(...), dias_entrega)` |
| 9 | Margen Total | `SUM(margen)` |
| 10 | Clientes Activos | `CALCULATE(DISTINCTCOUNT(cliente_sk), DATESINPERIOD(...365 días...))` |

### Flujo end-to-end resumido

```
SQL Server Northwind  (OLTP, datos transaccionales)
        ↓ NiFi Pipeline 1 (espejo 1:1)
MySQL Staging (3307)
        ↓ NiFi Pipeline 2 (joins, surrogate keys, medidas)
MySQL DW (3306) ─── esquema estrella físico
        ↓ XMLA Refresh (vía DSN ODBC, 64-bit)
SSAS Tabular Server (Northwind_Semantico) ─── modelo semántico in-memory
        ↓ Microsoft Analysis Services connector
Tableau Desktop (10 hojas + 3 dashboards) ─── visualización al usuario final
```

Cada flecha es un componente del proyecto. Cada caja es un servidor independiente. Esta separación NO es "complicación innecesaria" — es la arquitectura BI clásica que escala a cualquier tamaño.

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

---

## Parte 3 — Guion práctico de demostración

Esta sección dice **qué ventana abrir, qué mostrar y qué decir** para cada punto. Sigue el orden si quieres una demo lineal.

### Setup previo (antes de empezar la sustentación)

Ten estas ventanas abiertas y minimizadas, listas para Alt+Tab:

1. **Docker Desktop** (mostrando los 4 contenedores verdes).
2. **PowerShell** con el comando `docker ps` ya tipeado.
3. **DBeaver** con las 3 conexiones desplegadas (SQL Server 14333, MySQL Staging 3307, MySQL DW 3306).
4. **NiFi UI** en `https://localhost:8443/nifi` con los 2 Process Groups visibles.
5. **SSMS 19** conectado a `localhost\TABULAR` (Analysis Services) con la base `Northwind_Semantico` expandida.
6. **Tableau Desktop** con `Northwind_BI.twb` abierto en el Dashboard de Resumen.
7. **VS Code** con `DOCUMENTO_PROYECTO_BI.md` abierto.

### Orden de demostración recomendado

```
Arquitectura → Fuente → ETL Pipeline 1 → Staging → ETL Pipeline 2 → DW → Modelo Semántico → Tableau
```

Esto te lleva por la línea de tiempo del dato: desde Northwind crudo hasta el dashboard final.

---

## Parte 4 — Cómo demostrar el modelo semántico

El modelo semántico es probablemente lo que diferencia este proyecto de uno "simple". Hay que enseñarlo desde 3 ángulos distintos para que el jurado entienda qué es y por qué importa.

### Vista 1 — Servicio corriendo en el SO (15 segundos)

**Qué mostrar:**
- Abre **services.msc** (Win+R → services.msc).
- Busca **SQL Server Analysis Services (TABULAR)** → resaltar el estado **"En ejecución"**.

**Qué decir:**
> *"El cuarto servidor es un servicio nativo de Windows porque Microsoft no publica imagen Docker de SSAS. Está corriendo aquí en estado Running, escuchando en la instancia TABULAR. Es un proceso aparte del motor relacional — `msmdsrv.exe` — optimizado para consultas analíticas en memoria."*

### Vista 2 — Estructura del modelo en SSMS (30 segundos)

**Qué mostrar:**
- En SSMS 19, expande **Databases → Northwind_Semantico → Tables**.
- Muestra las 8 tablas con sus filas (`fact_ventas: 2155 rows`, etc).
- Expande **fact_ventas → Measures**.
- Muestra las 14 medidas DAX listadas.

**Qué decir:**
> *"Aquí está el modelo desplegado. 8 tablas formando un esquema estrella, 7 relaciones, y 14 medidas DAX que centralizan la lógica de negocio. Todo esto es código versionado en mi repo bajo `ssas/01_create_modelo.xmla` — el modelo es 100% reproducible desde Git, no depende de un IDE."*

**Qué consulta ejecutar (para demostrar que funciona):**

Clic derecho sobre `Northwind_Semantico` → **New Query → MDX**:

```dax
EVALUATE
SUMMARIZECOLUMNS (
  dim_tiempo[anio],
  "Ventas Netas", [Ventas Netas],
  "Margen Total", [Margen Total],
  "% Contribucion", [% Contribucion]
)
ORDER BY dim_tiempo[anio]
```

F5. Devuelve 3 filas (1996, 1997, 1998) con totales. Eso demuestra que las medidas DAX viven en el modelo, no en Tableau.

### Vista 3 — Modelo conectado desde Tableau (15 segundos)

**Qué mostrar:**
- En Tableau, ir a la pestaña **Origen de datos** (abajo).
- Muestra:
  - "Conectado a Microsoft SQL Server Analysis Services localhost\TABULAR"
  - Cubo `Northwind_Semantico` → Model
  - Lista de Campos con las medidas y dimensiones.

**Qué decir:**
> *"Tableau no calcula nada — solo arrastra los campos del cubo. Cuando arrastro 'Ventas Netas' a un gráfico, Tableau emite una consulta MDX al SSAS, SSAS agrega los datos en memoria y devuelve el resultado en milisegundos. Si mañana cambio la fórmula de 'Ventas Netas' en el modelo, todos los dashboards actualizan automáticamente sin tocar Tableau."*

### Ubicación física para la pregunta "¿dónde está?"

| Capa | Ubicación |
|---|---|
| Servicio corriendo | Proceso `msmdsrv.exe` en Windows |
| Datos en disco | `C:\Program Files\Microsoft SQL Server\MSAS17.TABULAR\OLAP\Data` |
| Definición versionada | `ssas/01_create_modelo.xmla` en el repo Git |
| Datos cargados | Cargados desde MySQL DW vía DSN ODBC `DW_NORTHWIND` (System.Data.Odbc) |
| Acceso vía red | Puerto dinámico vía SQL Server Browser (puerto 2382 broker) |

---

## Parte 5 — Cómo defender cada pregunta de negocio (con pantallas)

Para cada pregunta: qué hoja abrir, qué resaltar con el mouse, qué números mencionar.

### Q1 — Ventas por periodo

**Mostrar**: hoja `Q1_Ventas_Por_Periodo` (o el Dashboard de Resumen donde aparece).

**Cómo señalarlo:**
- Pasa el mouse sobre la **línea de 1997** (debe verse plana en ~50k mensuales).
- Resalta el pico de **abril 1998** (~125k).
- Aplica filtro de año a 1997 → la línea muestra un detalle por mes.

**Qué decir:**
> *"Pasamos de iniciar operaciones en julio de 1996 con 28k mensuales, a un pico de 125k en abril de 1998 — crecimiento sostenido año a año. El filtro de año arriba permite hacer drill-down por mes."*

**Filtros visibles que debe haber:** Año, País.

### Q2 — Top 10 clientes

**Mostrar**: hoja `Q2_Top10_Clientes`.

**Cómo señalarlo:**
- Apunta a las 3 barras superiores: **QUICK-Stop ($110k), Save-a-lot Markets ($104k), Ernst Handel ($104k)**.
- Pasa el mouse sobre cada una para mostrar el tooltip.

**Qué decir:**
> *"Los 3 clientes más valiosos concentran cerca del 24% de las ventas totales. QUICK-Stop el #1 con 110k. Si filtro por año puedo ver si su comportamiento cambió — en 1997 era todavía más dominante."*

### Q3 — Productos más vendidos

**Mostrar**: hoja `Q3_Productos_Top`.

**Cómo señalarlo:**
- Camembert Pierrot arriba con 1,577 unidades.
- Resalta el porcentaje al lado de cada barra (% Contribución).

**Qué decir:**
> *"Top 15 productos por volumen. Camembert Pierrot lidera con 5.62% de contribución total. Es una distribución larga: los top 15 representan ~30% del volumen — el resto se reparte en los 62 productos siguientes."*

### Q4 — Categorías

**Mostrar**: hoja `Q4_Categorias` (treemap).

**Cómo señalarlo:**
- Beverages el bloque más grande arriba-izquierda (21.16%).
- Dairy Products debajo (18.53%).

**Qué decir:**
> *"Las 2 categorías líderes — Beverages y Dairy Products — concentran ~40% de las ventas. La distribución visual hace evidente la prioridad de inversión publicitaria y stock."*

### Q5 — Empleados vs Metas (⚠ con filtro mensual obligatorio)

**Mostrar**: hoja `Q5_Empleados_vs_Metas`.

**Cómo señalarlo:**
- **Primero sin filtros**: todos muestran 90.91% — explica el por qué.
- **Luego con filtro Año=1997, Mes=9**: ahora Margaret Peacock ~112%, Steven Buchanan ~78%.

**Qué decir:**
> *"La meta se calculó como el promedio histórico × 1.10. Por construcción matemática, el cumplimiento en agregado total siempre dará 90.91% — no es bug, es el diseño. Para evaluación real, **el dashboard se opera con filtro mensual obligatorio**. Aquí en septiembre 1997 vemos que Margaret Peacock está al 112%, Janet Leverling al 95% y Steven Buchanan al 78% — eso sí permite feedback al equipo."*

**Filtros visibles que debe haber:** Año (dropdown), Mes (dropdown).

### Q6 — Territorios

**Mostrar**: hoja `Q6_Territorios` (mapa mundial).

**Cómo señalarlo:**
- Burbujas grandes sobre **Estados Unidos y Alemania**.
- Burbujas pequeñas o ausentes en Latinoamérica y Asia.

**Qué decir:**
> *"USA y Alemania concentran el mayor volumen. Latinoamérica tiene presencia mínima — solo Brasil, Venezuela y México. Eso señala una oportunidad clara de crecimiento si el negocio quisiera expansión geográfica."*

### Q7 — Tiempos de entrega

**Mostrar**: hoja `Q7_Tiempos_Entrega`.

**Cómo señalarlo:**
- Ireland arriba (~12 días, el peor).
- Finland abajo (~5 días, el mejor).
- Línea de referencia con el promedio global ~8.5 días.

**Qué decir:**
> *"Ireland tarda 12 días en promedio entregar — 40% por encima del promedio global. Eso indica un problema logístico que debe atacarse: probablemente único transportista, baja frecuencia de despacho. Finland en cambio entrega en 5 días por su cercanía geográfica a Suecia, donde está nuestro hub."*

### Q8 — Margen de rentabilidad

**Mostrar**: hoja `Q8_Margen_Producto`.

**Cómo señalarlo:**
- Côte de Blaye en el tope con ~$45k de margen.
- Tooltip muestra que tiene precio unitario alto.

**Qué decir:**
> *"Top 15 productos por margen absoluto, no por volumen. Côte de Blaye lidera con $45k — es un vino premium que se vende poco pero con margen alto. Estrategia distinta del top de Q3 que prioriza volumen. El costo aquí es un supuesto del 60% del precio venta, documentado en el Anexo D del proyecto."*

### Q9 — Clientes inactivos

**Mostrar**: hojas `Q9_Clientes_Inactivos` y `Q9b_Clientes_En_Riesgo`.

**Cómo señalarlo:**
- En Inactivos: resalta los con bar más larga (>700 días sin comprar).
- Apunta al label de Ventas Netas — diferencia clientes marginales vs significativos.

**Qué decir:**
> *"Tenemos N clientes inactivos (>365 días) que representan $X en ventas históricas. Pero hay que mirarlo con cuidado: Centro comercial Moctezuma facturó solo $100 — pérdida marginal, no vale campaña. Mère Paillarde con $29k sí es prioritaria. La estrategia: priorizar re-engagement por **valor histórico**, no por todos los inactivos."*

### Q10 — Estacionalidad

**Mostrar**: hoja `Q10_Estacionalidad` (heatmap).

**Cómo señalarlo:**
- Cuadrados oscuros en **diciembre 1997** (fin de año fiscal).
- **Abril 1998** el pico absoluto.
- Cuadrados claros en mayo-junio (caída estacional).

**Qué decir:**
> *"El heatmap muestra patrones estacionales claros: picos en cierre de año y arranque de Q2, caída en mayo-junio. Esa info permite planear inventario y staff: stockear más en Q4, recortar en mayo. Información estratégica para finanzas y operaciones."*

---

## Parte 6 — Si el jurado pregunta algo no preparado

### "¿Cómo sabemos que el ETL no perdió datos?"

Abre DBeaver y ejecuta en paralelo:

```sql
-- SQL Server (fuente)
USE Northwind;
SELECT ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS total_fuente
FROM [Order Details] od;
-- Resultado esperado: 1,265,793.04
```

```sql
-- MySQL DW (destino)
SELECT ROUND(SUM(venta_neta), 2) AS total_dw
FROM dw_northwind.fact_ventas;
-- Resultado esperado: 1,265,793.04
```

> *"Los 2 números coinciden al centavo. El ETL preserva integridad: no pierde ni distorsiona datos."*

### "¿Por qué Docker?"

> *"Docker me da reproducibilidad y aislamiento. Cualquiera con el repo Git clona, corre `docker-compose up`, y tiene mi misma infraestructura en 5 minutos. SQL Server, los 2 MySQL y NiFi corren cada uno en su contenedor — independientes, sin instalación local."*

### "¿Por qué NiFi en lugar de SSIS?"

> *"NiFi es agnóstico de proveedor (no depende de Microsoft), tiene UI gráfica con monitoreo en tiempo real, y es la herramienta de mercado para data flows modernos (Apache, open source, usada en producción por NSA, banca, telcos). SSIS me obligaría a estar en ecosistema Microsoft completo. Como tengo MySQL en el destino, NiFi es más natural."*

### "¿Por qué 2 servidores MySQL en lugar de 1?"

> *"Separación de Staging (espejo crudo, lectura-escritura intensa) vs DW (modelo estrella, optimizado para consultas analíticas). En producción tendrían afinaciones distintas: el Staging puede correr en SSD rápido, el DW en almacenamiento más barato. Si los junto en uno, comprometo ambos."*

### "¿Y si quiero agregar una pregunta de negocio nueva mañana?"

> *"Si la respuesta sale del modelo actual: agrego una medida DAX nueva al `01_create_modelo.xmla`, lo re-deploy, refresco Tableau, agrego una hoja. 30 minutos. Si necesito una dimensión nueva: agrego la tabla al DW, modifico Pipeline 2 para poblarla, agrego una `dim_*` al modelo. 2 horas. La arquitectura es extensible por diseño."*

### "¿Qué pasa si SSAS se cae?"

> *"Tableau no puede consultar — los dashboards quedan en blanco. PERO los datos NO se pierden: están en el DW MySQL (capa de persistencia). Reinicio SSAS, el modelo se recarga automáticamente, en 30 segundos los dashboards vuelven a vivir."*

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
