# Proyecto de Business Intelligence — Northwind
### Base de Datos Avanzadas

**Estudiante:** William Yaruro
**Fecha:** Junio 2026
**Fuente de datos:** Northwind (Microsoft)
**Herramientas:** Apache NiFi (ETL) · MySQL (Data Warehouse) · SSAS Tabular (Modelo semántico) · Tableau (Visualización)

---

## Tabla de contenido
1. Metodología, arquitectura y herramientas
2. Descripción de la fuente de datos
3. Matriz fuente–destino (Staging / Bodega)
4. Diseño lógico y físico de la Staging Area
5. Diseño lógico y físico de la bodega de datos (data mart)
6. Modelo semántico SSAS Tabular (Plus +1)
7. Diseño del ETL
8. Transformaciones realizadas a los datos
9. Diseño de las visualizaciones
10. Anexo A — Manual de instalación
11. Anexo B — Manual técnico y de usuario del ETL
12. Anexo C — Manual técnico y de usuario de la visualización
13. Anexo D — Supuestos y alcance del proyecto

---

## 1. Metodología, arquitectura y herramientas

### 1.1 Metodología
El proyecto sigue la metodología clásica de construcción de soluciones de Business
Intelligence basada en procesos **ETL (Extract, Transform, Load)**. Se eligió ETL
(y no ELT) porque las transformaciones se aplican **antes** de cargar la bodega,
manteniendo el repositorio de destino limpio y modelado dimensionalmente.

El flujo de datos atraviesa cuatro componentes:
**Fuente (OLTP) → Staging → Bodega de datos (DW) → Visualización.**

La bodega se diseña con **modelado dimensional (esquema estrella)**: una tabla de
hechos central con las métricas del negocio, rodeada de tablas de dimensión que
permiten analizar la información desde distintas perspectivas (tiempo, cliente,
producto, empleado, territorio, transportista).

### 1.2 Arquitectura — 4 servidores independientes
Requisito del proyecto: cada componente vive en un **servidor distinto**; nada
comparte servidor. Tres componentes se aíslan con **contenedores Docker** (red,
almacenamiento y puerto propios) y el cuarto es una instancia **SSAS Tabular**
local en Windows (servicio aparte), para un total de cuatro servidores.

| Servidor | Motor | Rol | Puerto | Regla |
|---|---|---|---|---|
| Servidor 1 | SQL Server 2022 (Docker) | Fuente / OLTP (Northwind) | 1433 | NiFi solo **lee** |
| Servidor 2 | MySQL 8 (Docker) | Staging | 3307 | Copia **cruda 1:1**, sin transformar |
| Servidor 3 | MySQL 8 (Docker) | Data Warehouse | 3306 | Esquema estrella |
| Servidor 4 | SSAS Tabular (Windows) | Modelo semántico | 2383 | Lee del DW, expone a Tableau |

**Regla de oro:** en el Staging los datos llegan **crudos, sin transformar**.
Todas las transformaciones ocurren en el trayecto Staging → Bodega, nunca dentro
del Staging.

```
┌──────────────┐  Pipeline 1 (NiFi)  ┌──────────────┐ Pipeline 2 (NiFi) ┌──────────────┐  Refresh   ┌─────────────────┐         ┌──────────┐
│ SERVIDOR 1   │ Extract + Load      │ SERVIDOR 2   │ Transform + Load  │ SERVIDOR 3   │ via ODBC   │ SERVIDOR 4      │  MDX/   │ TABLEAU  │
│ SQL Server   │ ───(dato crudo)───► │ MySQL        │ ────────────────► │ MySQL        │ ─────────► │ SSAS Tabular    │ ──────► │ Desktop  │
│ Northwind    │ sin transformar     │ Staging 1:1  │ joins, SK, medida │ DW estrella  │            │ Modelo semántico│  XMLA   │ (local)  │
└──────────────┘                     └──────────────┘                   └──────────────┘            └─────────────────┘         └──────────┘

         Apache NiFi orquesta los pipelines (corre en un equipo aparte / host)
```

> **Tableau Desktop** corre **local** en la máquina del estudiante, pero se conecta
> al modelo semántico SSAS (Servidor 4) — no consume el DW directamente. Esto
> habilita el punto extra del profesor (capítulo 6).

[CAPTURA: `docker ps` con los 3 contenedores + Services.msc mostrando "SQL Server Analysis Services (TABULAR)" corriendo]

### 1.3 Herramientas
- **Apache NiFi** — herramienta ETL. Orquesta la extracción, el cargue al staging
  y la transformación/cargue al DW mediante dos pipelines.
- **MySQL 8** — motor de la bodega de datos (Servidor 3) y del staging (Servidor 2,
  instancia aparte en otro puerto).
- **SQL Server 2022** — alberga la base transaccional Northwind (fuente, Servidor 1).
- **SSAS Tabular** (SQL Server Analysis Services, modo Tabular) — modelo semántico
  que lee del DW y expone medidas DAX a Tableau. Servicio Windows independiente
  (Servidor 4). Habilita el **+1 punto extra** del profesor.
- **Tableau Desktop** — herramienta de visualización; corre local pero se conecta
  al modelo semántico SSAS (no al DW directo).
- **Docker** — virtualización de los Servidores 1, 2 y 3.

---

## 2. Descripción de la fuente de datos

La fuente es **Northwind**, base de datos transaccional (OLTP) de ejemplo de
Microsoft que modela una comercializadora de alimentos: gestiona clientes,
pedidos, productos, categorías, proveedores, empleados y transportistas.

**Periodo de los datos:** julio 1996 – mayo 1998 (ver Anexo D, alcance).

Tablas de la fuente utilizadas (esquema `dbo`):

| Tabla (SQL Server) | Descripción | Registros aprox. |
|---|---|---|
| Customers | Clientes | 91 |
| Orders | Pedidos (cabecera) | 830 |
| Order Details | Líneas de pedido (detalle) | 2155 |
| Products | Productos | 77 |
| Categories | Categorías de producto | 8 |
| Suppliers | Proveedores | 29 |
| Employees | Empleados (vendedores) | 9 |
| Shippers | Transportistas | 3 |

> Nota: los nombres en SQL Server usan PascalCase y `Order Details` lleva espacio
> (se referencia como `[Order Details]`). El detalle de columnas, tipos y reglas
> de calidad de la fuente está en el archivo `Plantilla_Diccionario_Datos_BI.xlsx`.

[CAPTURA: SELECT COUNT(*) de las tablas en SQL Server / Northwind]

---

## 3. Matriz fuente–destino (Staging / Bodega)

La matriz completa está en el archivo `M.xlsx` (hojas *Staging*, *Bodega_Datos* y
*Catalogo_Transformaciones*). Resumen del recorrido fuente → staging → bodega:

| Origen (Northwind) | Staging (Servidor 2) | Destino DW (Servidor 3) |
|---|---|---|
| Customers | stg_customers | dim_cliente |
| Products + Categories + Suppliers | stg_products / stg_categories / stg_suppliers | dim_producto |
| Employees | stg_employees | dim_empleado |
| Shippers | stg_shippers | dim_transportista |
| Orders (campos Ship*) | stg_orders | dim_geografia |
| Orders.OrderDate | stg_orders | dim_tiempo (generada) |
| Order Details + Orders | stg_order_details + stg_orders | fact_ventas |

> Importante: en la columna *Transformación Staging* de `M.xlsx` debe decir
> **"Ninguna / copia 1:1"**, porque el staging no transforma. Las transformaciones
> reales se documentan en la hoja *Bodega_Datos* (trayecto staging → DW).

---

## 4. Diseño lógico y físico de la Staging Area

### 4.1 Diseño lógico
El staging es un **espejo 1:1** de la fuente: una tabla por cada tabla origen, con
los mismos campos y sin reglas de negocio. Su único propósito es desacoplar la
extracción de la transformación (si la fuente se cae o hay que reprocesar, los
datos crudos ya están aterrizados).

Tablas: `stg_categories`, `stg_suppliers`, `stg_products`, `stg_customers`,
`stg_employees`, `stg_shippers`, `stg_orders`, `stg_order_details`, más una tabla
de control `etl_control` para la carga incremental.

### 4.2 Diseño físico
Implementado en MySQL 8 (Servidor 2, `staging_northwind`). Script completo:
**`scripts/01_staging_mysql.sql`**.

Decisión de diseño: se excluyen las columnas binarias (`Picture`, `Photo`) porque
no aportan al análisis y complican la extracción; no es una transformación, es una
columna que simplemente no se extrae.

[CAPTURA: tablas del staging en MySQL Workbench / DBeaver]

---

## 5. Diseño lógico y físico de la bodega de datos (data mart)

### 5.1 Diseño lógico — esquema estrella

```
                         dim_tiempo
                              │
        dim_cliente ──────────┼────────── dim_producto
                              │
                       ┌──────┴──────┐
                       │ fact_ventas │   (grano = línea de pedido)
                       └──────┬──────┘
                              │
       dim_empleado ──────────┼────────── dim_geografia
                              │
                      dim_transportista

        + dim_metas (pregunta #5)   + costo en dim_producto (pregunta #8)
```

**Tabla de hechos `fact_ventas`** (grano = una línea de pedido):
medidas → cantidad, precio_unitario, descuento, venta_bruta, venta_neta,
costo_total, margen, dias_entrega. Dimensión degenerada → order_id.

**Dimensiones:** dim_tiempo, dim_cliente, dim_producto, dim_empleado,
dim_geografia, dim_transportista. Estrategia **SCD Tipo 1** (sobreescritura),
suficiente para el alcance del proyecto.

### 5.2 Diseño físico
Implementado en MySQL 8 (Servidor 3, `dw_northwind`). Cada dimensión tiene una
**llave sustituta** (surrogate key, `AUTO_INCREMENT`) y conserva la **llave de
negocio** (BK) para los cruces. La tabla de hechos referencia las dimensiones por
sus SK mediante claves foráneas.

Script completo: **`scripts/02_bodega_dw_mysql.sql`**.

[CAPTURA: diagrama del modelo estrella en MySQL Workbench (Reverse Engineer)]

---

## 6. Modelo semántico SSAS Tabular (Plus +1)

### 6.1 Por qué un modelo semántico
El profesor reconoce **un punto adicional** si la solución pasa del modelo
dimensional a un **modelo semántico con Tabular SSAS** y el visualizador se
conecta a ese modelo (no al DW directo). Beneficios:
- **Centraliza las medidas** (DAX) — todas las visualizaciones usan las mismas
  fórmulas de "venta_neta", "% cumplimiento meta", etc.
- **Rendimiento** — el motor VertiPaq comprime e indexa en memoria.
- **Seguridad y gobierno** — un solo punto de definición de KPIs.

### 6.2 Arquitectura del modelo
- **Motor:** SQL Server Analysis Services 2022, modo **Tabular**.
- **Origen de datos del modelo:** MySQL DW (`localhost:3306/dw_northwind`) vía
  conector **MySQL ODBC 8.x**.
- **Modo de almacenamiento:** *Import* (VertiPaq) — el modelo guarda copia en
  memoria; se refresca tras cada corrida del ETL.
- **Tablas importadas:** las 6 dimensiones (`dim_tiempo`, `dim_cliente`,
  `dim_producto`, `dim_empleado`, `dim_geografia`, `dim_transportista`),
  `dim_metas` y `fact_ventas`.
- **Relaciones:** una por cada FK del esquema estrella (fact ↔ dimensión por SK).
- **Jerarquías:** `dim_tiempo` → Año › Trimestre › Mes › Día.

### 6.3 Medidas DAX principales
Una medida por pregunta de negocio del capítulo 2 (definición conceptual; el
estudiante las escribe en el modelo):

| Medida | Pregunta | Idea DAX |
|---|---|---|
| `Ventas Netas` | 1, 2, 4, 6, 10 | `SUM(fact_ventas[venta_neta])` |
| `Ventas YoY %` | 1 | Comparación contra `SAMEPERIODLASTYEAR` |
| `Top10 Clientes` | 2 | `TOPN(10, ALL(dim_cliente), [Ventas Netas])` |
| `Cantidad Vendida` | 3 | `SUM(fact_ventas[cantidad])` |
| `% Contribución` | 3, 4 | `[Ventas Netas] / CALCULATE([Ventas Netas], ALL(...))` |
| `Cumplimiento Meta %` | 5 | `[Ventas Netas] / [Meta Mensual]` |
| `Días Entrega Promedio` | 7 | `AVERAGE(fact_ventas[dias_entrega])` |
| `Margen` | 8 | `SUM(fact_ventas[margen])` |
| `Clientes Inactivos` | 9 | conteo con `MAX(fecha)` < hoy − 365 |
| `Ventas Mismo Mes Año Ant.` | 10 | `CALCULATE([Ventas Netas], SAMEPERIODLASTYEAR(...))` |

### 6.4 Herramientas para construir el modelo
- **Visual Studio 2022** con la extensión *Microsoft Analysis Services Projects*
  (proyecto **Tabular Model Project**, *compatibility level 1600*).
- (Alternativa recomendada) **Tabular Editor 2** (gratuito) para escribir las
  medidas DAX más cómodamente y desplegar al servidor SSAS.

### 6.5 Despliegue
El proyecto Tabular se despliega al Servidor 4 (`localhost\TABULAR`, puerto 2383)
con el nombre de base de datos **`Northwind_Semantico`**.

[CAPTURA: modelo Tabular en Visual Studio (diagrama de tablas y relaciones)]
[CAPTURA: Tabular Editor con las medidas DAX]
[CAPTURA: SQL Server Management Studio conectado a la instancia SSAS Tabular mostrando la base desplegada]

---

## 7. Diseño del ETL

El ETL se implementó en **Apache NiFi** con **dos pipelines**:

### Pipeline 1 — Extract + Load (Fuente → Staging) · SIN transformar
Por cada tabla de Northwind:
- **Dimensiones pequeñas** (Customers, Products, Categories, Suppliers, Employees,
  Shippers): carga **completa** (truncate + load).
- **Tablas transaccionales** (Orders, Order Details): carga **incremental** por
  `OrderID`, usando la tabla `etl_control` como watermark.

Procesadores NiFi:
`QueryDatabaseTable` (lee SQL Server, mantiene estado del máximo OrderID) →
`PutDatabaseRecord` (escribe en MySQL staging).

### Pipeline 2 — Transform + Load (Staging → DW)
1. Carga de **dimensiones**: `ExecuteSQL` sobre staging (con sus joins internos) →
   `PutDatabaseRecord` a cada `dim_*` del DW.
2. Carga del hecho: `ExecuteSQL` sobre staging (Order Details ⋈ Orders) →
   `PutDatabaseRecord` a `fact_landing` (con llaves de negocio).
3. **Resolución de llaves sustitutas y métricas:** `PutSQL` ejecuta el script
   `03_transformaciones_dw.sql` dentro del DW (joins BK→SK, cálculo de medidas,
   metas y costos).

> Justificación del paso 3: como staging y DW están en **servidores distintos**,
> no se puede hacer un join cross-server. NiFi trae los datos al DW y la resolución
> de SK se hace con SQL set-based dentro del DW (rápido y robusto).

### Carga incremental (demostración)
Northwind es estático. Para evidenciar la incrementalidad se insertan manualmente
1–2 pedidos nuevos en la fuente y se re-ejecuta el Pipeline 1: NiFi detecta solo
los `OrderID` mayores al watermark y carga únicamente esos.

[CAPTURA: lienzo de NiFi con Pipeline 1 y Pipeline 2]
[CAPTURA: tabla order_details con 4 registros, luego con 6, tras la carga incremental]

---

## 8. Transformaciones realizadas a los datos

Todas ocurren en el trayecto Staging → DW (nunca en staging). Catálogo:

| Código | Transformación | Descripción | Dónde |
|---|---|---|---|
| TR-01 | Llaves sustitutas | Generar SK por dimensión y resolver BK→SK en el hecho | DW |
| TR-02 | Concatenación | nombre_completo = FirstName + ' ' + LastName | dim_empleado |
| TR-03 | Desnormalización | Producto + categoría + proveedor en una sola dim | dim_producto |
| TR-04 | Generación de calendario | Construir dim_tiempo (año, trimestre, mes, día) | dim_tiempo |
| TR-05 | Cálculo de medidas | venta_bruta, venta_neta, costo_total, margen | fact_ventas |
| TR-06 | Cálculo de tiempos | dias_entrega = shipped_date − order_date | fact_ventas |
| TR-07 | Manejo de nulos | Ship region/city nulos → 'No especificado' | dim_geografia |
| TR-08 | Costos (supuesto) | Costo manual por producto (ver Anexo D) | product_costos |
| TR-09 | Metas (supuesto) | Meta = promedio histórico del empleado + 10% | dim_metas |

Implementación: **`scripts/03_transformaciones_dw.sql`**.

---

## 9. Diseño de las visualizaciones

Tableau se conecta **al modelo semántico SSAS Tabular** (Servidor 4,
`Northwind_Semantico`) y consume las medidas DAX. **No** se conecta directo al DW
en la versión final, para honrar el plus del profesor. Un dashboard por pregunta
de negocio:

| # | Pregunta | Visualización | Medida DAX |
|---|---|---|---|
| 1 | Ventas por periodo | Línea por mes/año + % YoY | `Ventas Netas`, `Ventas YoY %` |
| 2 | Top 10 clientes | Barras horizontales | `Top10 Clientes` |
| 3 | Productos más vendidos | Barras + % contribución | `Cantidad Vendida`, `% Contribución` |
| 4 | Categorías con más ingresos | Treemap / barras | `Ventas Netas` por categoría |
| 5 | Empleados vs. metas | Barras reales vs. meta + % cumplimiento | `Cumplimiento Meta %` |
| 6 | Territorios | Mapa por país | `Ventas Netas` por país |
| 7 | Tiempos de entrega | Barras de promedio por región | `Días Entrega Promedio` |
| 8 | Margen de rentabilidad | Barras de margen por producto | `Margen` |
| 9 | Clientes inactivos | Tabla de última compra por cliente | `Clientes Inactivos` |
| 10 | Estacionalidad | Heatmap mes × año | `Ventas Netas`, `Ventas Mismo Mes Año Ant.` |

[CAPTURA: dashboard de cada pregunta]

---

## 10. Anexo A — Manual de instalación

### A.1 Requisitos
- Windows 10/11 con WSL2.
- Docker Desktop.
- Cliente SQL: Azure Data Studio o DBeaver.
- Cliente MySQL: MySQL Workbench o DBeaver.
- Apache NiFi (binario) + Java 11/17.
- **SQL Server 2022 Developer Edition** (local en Windows) con el rol *Analysis
  Services* en modo **Tabular** → Servidor 4.
- **SQL Server Management Studio (SSMS)** para administrar SSAS.
- **Visual Studio 2022 Community** + extensión *Microsoft Analysis Services
  Projects*. (Opcional pero recomendado: **Tabular Editor 2**.)
- **MySQL Connector/ODBC 8.x** (necesario para que SSAS lea MySQL).
- Tableau Desktop.

### A.2 Levantar los 3 servidores
1. Instalar Docker Desktop (motor WSL2) y verificar con `docker run hello-world`.
2. Crear `docker-compose.yml` (ver carpeta del proyecto) con los servicios
   `source_sqlserver` (1433), `staging_mysql` (3307) y `dw_mysql` (3306).
3. `docker compose up -d` y validar con `docker ps` (3 contenedores).

### A.3 Cargar Northwind (Servidor 1)
1. Conectar a `localhost,1433` (usuario `sa`).
2. Ejecutar el script `instnwnd.sql` (Northwind para SQL Server).
3. Validar: `SELECT COUNT(*) FROM Customers;` → 91.

### A.4 Crear Staging y Bodega
1. En `localhost:3307` ejecutar `scripts/01_staging_mysql.sql`.
2. En `localhost:3306` ejecutar `scripts/02_bodega_dw_mysql.sql`.

### A.5 Apache NiFi
1. Descargar y descomprimir NiFi; `bin\run-nifi.bat`.
2. Abrir `https://localhost:8443/nifi`.
3. Cargar el driver JDBC de SQL Server (mssql-jdbc) y el de MySQL en
   *Controller Services* (DBCPConnectionPool).
   - SQL Server URL: `jdbc:sqlserver://localhost:1433;databaseName=Northwind;encrypt=false;trustServerCertificate=true`
   - MySQL URL: `jdbc:mysql://localhost:3307/staging_northwind` (staging) y `:3306/dw_northwind` (DW).

### A.6 SSAS Tabular (Servidor 4)
1. Ejecutar el instalador de **SQL Server 2022 Developer**; marcar **Analysis
   Services** y elegir modo **Tabular**. Nombre de instancia sugerido: `TABULAR`.
2. Validar el servicio en `services.msc` → "SQL Server Analysis Services (TABULAR)"
   en estado **Running**. Puerto por defecto: 2383.
3. Instalar **SSMS** y conectarse a `localhost\TABULAR` para confirmar acceso.
4. Instalar **MySQL Connector/ODBC 8.x** (`Driver = MySQL ODBC 8.x Unicode Driver`).
5. Crear un **DSN de sistema** (ODBC Data Sources 64-bit) llamado `DW_NORTHWIND`
   apuntando a `localhost:3306`, base `dw_northwind`, usuario y contraseña del DW.
6. Instalar **Visual Studio 2022 Community** con la carga de trabajo "Almacenamiento
   y procesamiento de datos" y la extensión **Microsoft Analysis Services Projects**.
7. (Opcional) Instalar **Tabular Editor 2** desde tabulareditor.com.

[CAPTURA: cada paso clave de instalación]

---

## 11. Anexo B — Manual técnico y de usuario del ETL

### B.1 Técnico
- Pipeline 1 (Fuente→Staging): processors `QueryDatabaseTable` + `PutDatabaseRecord`.
- Pipeline 2 (Staging→DW): `ExecuteSQL` + `PutDatabaseRecord` + `PutSQL`.
- Controller Services: DBCPConnectionPool para SQL Server, staging MySQL y DW MySQL.
- Estado/incremental: NiFi guarda el máximo OrderID; la tabla `etl_control`
  documenta el watermark.

### B.2 Usuario
1. Abrir NiFi.
2. Iniciar el *Process Group* "Pipeline 1" → esperar que el staging se llene.
3. Iniciar el *Process Group* "Pipeline 2" → se cargan dimensiones, fact_landing
   y se ejecuta la resolución de SK.
4. Validar con la consulta de verificación al final de `03_transformaciones_dw.sql`.

[CAPTURA: pipelines en ejecución; conteos antes/después]

---

## 12. Anexo C — Manual técnico y de usuario de la visualización

### C.1 Técnico
- Conector: **Microsoft Analysis Services** → servidor `localhost\TABULAR`,
  base de datos `Northwind_Semantico`, modo *Import* o *Live*.
- Tableau no define medidas: consume las medidas DAX del modelo semántico.
- Refresco del modelo: tras cada corrida del ETL, el estudiante ejecuta un
  *Process Full* sobre la base SSAS desde SSMS (o desde Visual Studio).

### C.2 Usuario
1. Abrir Tableau → *Connect* → *To a Server* → **Microsoft Analysis Services**.
2. Server: `localhost\TABULAR` — autenticación de Windows.
3. Seleccionar la base **`Northwind_Semantico`** y el cubo único expuesto.
4. Crear una hoja por pregunta de negocio (ver capítulo 9) arrastrando las
   medidas DAX y las jerarquías de dim_tiempo.
5. Ensamblar el dashboard final.

[CAPTURA: conexión de Tableau a SSAS Tabular; árbol de medidas; cada dashboard]

---

## 13. Anexo D — Supuestos y alcance del proyecto

1. **Alcance temporal.** Northwind contiene datos de jul-1996 a may-1998. Las
   preguntas que mencionan "últimos 5 años" o "último año" se responden sobre el
   **histórico disponible en la fuente**. No se inventan datos.
2. **Costos (pregunta #8).** Northwind no incluye costo de producto. Se definió
   una **tabla de costos manual** (`product_costos`). Valor inicial sugerido =
   60 % del precio de venta, ajustable por producto. Es un supuesto del proyecto.
3. **Metas de ventas (pregunta #5).** Northwind no incluye metas. La meta mensual
   de cada empleado se calcula como su **promedio histórico de ventas netas + 10 %**.
   Cumplimiento = ventas reales / meta.
4. **Servidores.** Los Servidores 1, 2 y 3 se implementan como contenedores
   Docker aislados (red, almacenamiento y puerto propios). El Servidor 4 (SSAS
   Tabular) se implementa como instancia local de SQL Server Developer en
   Windows — proceso/servicio independiente con su propio puerto (2383).
5. **SCD.** Las dimensiones usan SCD Tipo 1 (sobreescritura).
6. **Modelo semántico.** Tableau se conecta exclusivamente al modelo Tabular,
   no al DW. El refresco del modelo se ejecuta manualmente después de cada
   corrida del ETL (no automatizado en este alcance).
7. **Naturaleza del ETL — replicación por lotes, no en tiempo real.** El ETL es
   **batch**: NiFi mueve datos solo cuando se ejecuta el pipeline (manual o
   programado), no hay replicación continua entre fuente y bodega. La forma en
   que los cambios de la fuente se reflejan en el DW depende del tipo de cambio:

   | Cambio en la fuente | ¿Se refleja en el DW? | Mecanismo |
   |---|---|---|
   | INSERT de pedido nuevo (`Orders`, `Order Details`) | ✅ Sí | Carga incremental por watermark sobre `OrderID` (tabla `etl_control`). |
   | INSERT de cliente / producto / empleado / categoría / proveedor / transportista nuevo | ✅ Sí | Truncate + load completo de la dimensión en cada corrida. |
   | UPDATE en una fila de dimensión existente (ej. cambio de dirección de un cliente, cambio de precio de un producto) | ✅ Sí, pero **sin historia** | Truncate + load sobreescribe el valor anterior. **SCD Tipo 1**: se pierde el valor previo. |
   | UPDATE en un pedido o detalle **ya cargado** (ej. cambio de cantidad, descuento o fecha de envío) | ❌ **No** | El watermark solo detecta `OrderID` mayores al máximo cargado; las filas existentes no se vuelven a leer. |
   | DELETE de cualquier registro en la fuente | ❌ **No** | El ETL no compara borrados; los registros eliminados quedan "fantasma" en el DW. |

   Esta es la arquitectura clásica de BI y es **una decisión consciente** del
   diseño, no una limitación accidental. Para soportar updates y deletes habría
   que implementar **Change Data Capture (CDC)** — por ejemplo con procesadores
   `CaptureChangeMySQL` de NiFi o replicación basada en logs (Debezium /
   transaction log de SQL Server) — lo cual queda **fuera del alcance** de este
   proyecto académico.
