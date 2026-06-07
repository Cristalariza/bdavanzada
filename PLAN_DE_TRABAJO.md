# Plan de Trabajo — Proyecto BI Northwind
**Estudiante:** William Yaruro · **Stack:** SQL Server + NiFi + MySQL + SSAS Tabular + Tableau
**Modalidad:** William implementa; Claude entrega paso a paso detallado por fase.

---

## Fase 0 — Preparación del ambiente *(1 sesión, ~1 h)*
- Instalar Docker Desktop con WSL2 y validar (`docker run hello-world`).
- Instalar clientes: DBeaver (o MySQL Workbench + Azure Data Studio).
- Descargar binario de Apache NiFi 1.x + Java 17.
- Descargar drivers JDBC: `mssql-jdbc` y `mysql-connector-j`.
- Descargar Tableau Desktop (licencia estudiante).
- **Entregable:** capturas de cada herramienta instalada.

## Fase 1 — Servidor 1: SQL Server + Northwind *(1 sesión, ~1 h)*
- Crear `docker-compose.yml` con servicio `source_sqlserver` (puerto 1433).
- Levantar contenedor y conectarse.
- Cargar `instnwnd.sql` (Northwind oficial de Microsoft).
- Validar conteos (`Customers`=91, `Orders`=830, `[Order Details]`=2155).
- **Entregable:** capturas + sección 2 del MD lista.

## Fase 2 — Servidores 2 y 3: MySQL Staging + DW *(1 sesión, ~1.5 h)*
- Agregar al compose los servicios `staging_mysql` (3307) y `dw_mysql` (3306).
- Escribir el DDL de Staging (8 tablas espejo + `etl_control`).
- Escribir el DDL del DW (6 dimensiones + `fact_ventas` + `dim_metas` + `product_costos`).
- Validar `SHOW TABLES` en ambas instancias.
- **Entregable:** scripts `01_staging_mysql.sql` y `02_bodega_dw_mysql.sql` + secciones 4 y 5 del MD.

## Fase 3 — Apache NiFi y Pipeline 1 (Fuente → Staging) *(2 sesiones, ~3 h)*
- Arrancar NiFi en `https://localhost:8443/nifi`.
- Configurar 3 `DBCPConnectionPool` (SQL Server, Staging, DW).
- Construir Pipeline 1: `QueryDatabaseTable` → `PutDatabaseRecord` por cada tabla origen.
- Carga completa para dimensiones pequeñas; incremental por `OrderID` para `Orders`/`Order Details`.
- Validar conteos en Staging tras la primera corrida.
- **Entregable:** template NiFi exportado + sección 7 del MD + capturas.

## Fase 4 — Pipeline 2 (Staging → DW) + Transformaciones *(2 sesiones, ~3 h)*
- Escribir `03_transformaciones_dw.sql` con: poblar `dim_tiempo`, joins BK→SK, cálculo de medidas (`venta_bruta`, `venta_neta`, `costo_total`, `margen`, `dias_entrega`), generación de `dim_metas`.
- Construir Pipeline 2 en NiFi: `ExecuteSQL` (staging) → `PutDatabaseRecord` (`fact_landing`) → `PutSQL` (script de resolución de SK en DW).
- Validar `SELECT COUNT(*)` y sumatorias contra la fuente.
- Probar **carga incremental**: insertar 1–2 pedidos en SQL Server y re-correr.
- **Entregable:** script de transformaciones + sección 8 del MD + capturas antes/después.

## Fase 5 — Servidor 4: SSAS Tabular *(1 sesión, ~2 h)*
- Instalar SQL Server 2022 Developer con rol *Analysis Services* en modo **Tabular** (instancia `TABULAR`).
- Instalar SSMS, Visual Studio 2022 + extensión *Analysis Services Projects*, Tabular Editor 2.
- Instalar MySQL Connector/ODBC 8.x y crear DSN de sistema `DW_NORTHWIND`.
- Validar conexión desde SSMS a `localhost\TABULAR`.
- **Entregable:** capturas de cada componente + Anexo A.6 del MD.

## Fase 6 — Modelo semántico + medidas DAX *(2 sesiones, ~3 h)*
- Crear proyecto Tabular en Visual Studio, importar tablas del DW vía ODBC.
- Definir relaciones del esquema estrella.
- Crear jerarquía Año › Trimestre › Mes › Día en `dim_tiempo`.
- Escribir las 10 medidas DAX del capítulo 6.3 del MD.
- Desplegar a `localhost\TABULAR` como `Northwind_Semantico`.
- **Entregable:** modelo desplegado + capturas + sección 6 del MD enriquecida.

## Fase 7 — Tableau: dashboards *(2 sesiones, ~3 h)*
- Conectar Tableau a *Microsoft Analysis Services* (`localhost\TABULAR`).
- Una hoja por pregunta de negocio (10 en total).
- Ensamblar 1–2 dashboards finales con filtros globales (año, país, categoría).
- **Entregable:** archivo `.twb` + capturas + sección 9 del MD.

## Fase 8 — Documentación final y sustentación *(1 sesión, ~2 h)*
- Llenar todas las `[CAPTURA: ...]` del MD.
- Completar `M.xlsx` (matriz fuente–destino) y diccionario de datos.
- Redactar manuales de usuario (Anexos B y C).
- Preparar guion de sustentación (5–10 min) + demo en vivo.
- **Entregable:** PDF final + repositorio organizado + presentación.

---

## Estimado total
**~13 sesiones · ~18-20 horas de trabajo efectivo**

## Reglas de trabajo acordadas
1. William implementa cada paso; Claude **no genera scripts ni archivos finales**.
2. Cada fase termina con validaciones medibles y capturas listas para el documento.
3. El MD principal (`DOCUMENTO_PROYECTO_BI.md`) se actualiza al cierre de cada fase.
4. Si una fase descubre una decisión nueva, se documenta como supuesto en Anexo D.
