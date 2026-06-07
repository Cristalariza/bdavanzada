# Fase 8 — Documentación final, matriz fuente-destino y sustentación

**Objetivo:** dejar todos los entregables del profesor listos: documento principal con capturas, matriz fuente–destino (`M.xlsx`), diccionario de datos, manuales de usuario, y preparar el guion + demo de la sustentación.
**Tiempo estimado:** 2-3 horas.
**Prerrequisitos:** Fases 0-7 completadas. Todas las capturas tomadas.

---

## Paso 1 — Revisar el documento principal

1.1. Abre `DOCUMENTO_PROYECTO_BI.md`.
1.2. Recorre cada `[CAPTURA: ...]` y reemplázalo por:
   ```markdown
   ![Descripción](capturas/XX/nombre_de_la_captura.png)
   ```
1.3. Convención de nombres de capturas: `<fase>_<paso>_<descripcion_corta>.png` (ej. `01_3_dbeaver_conectado.png`).
1.4. Verifica que cada capítulo tenga al menos 1 captura.
1.5. **NO** dejes ningún `[CAPTURA: ...]` sin reemplazar.

---

## Paso 2 — Completar la matriz fuente–destino (`M.xlsx`)

2.1. Crea un libro Excel `M.xlsx` con 3 hojas:
   - **Staging**
   - **Bodega_Datos**
   - **Catalogo_Transformaciones**

### Hoja "Staging" — columnas
| Origen Tabla | Origen Columna | Tipo Origen | Staging Tabla | Staging Columna | Tipo Staging | Regla |
|---|---|---|---|---|---|---|
| Categories | CategoryID | int | stg_categories | CategoryID | INT | Copia 1:1 |
| Categories | CategoryName | nvarchar(15) | stg_categories | CategoryName | VARCHAR(15) | Copia 1:1 |
| ... | ... | ... | ... | ... | ... | ... |

Llena una fila por cada columna de cada una de las 8 tablas origen → 8 staging.

### Hoja "Bodega_Datos" — columnas
| Staging Tabla | Staging Columna | DW Tabla | DW Columna | Tipo DW | Transformación |
|---|---|---|---|---|---|
| stg_customers | CustomerID | dim_cliente | customer_id | VARCHAR(5) | Rename + BK |
| stg_customers | (calculado) | dim_cliente | cliente_sk | INT AUTO | Generar SK |
| stg_products + stg_categories + stg_suppliers | múltiples | dim_producto | varias | varios | Desnormalización (TR-03) |
| stg_employees | FirstName, LastName | dim_empleado | nombre_completo | VARCHAR(50) | Concatenación (TR-02) |
| ... | ... | ... | ... | ... | ... |

### Hoja "Catalogo_Transformaciones" — columnas
| Código | Nombre | Descripción | Dónde se aplica | Fórmula/Regla |
|---|---|---|---|---|
| TR-01 | Llaves sustitutas | Generar SK incrementales por dimensión y resolver BK→SK en hechos | Pipeline 2 (PutSQL) | AUTO_INCREMENT en dim, JOIN BK→SK en fact |
| TR-02 | Concatenación | nombre_completo = FirstName + ' ' + LastName | dim_empleado | CONCAT(FirstName,' ',LastName) |
| TR-03 | Desnormalización | Producto + categoría + proveedor | dim_producto | LEFT JOIN categories + suppliers |
| TR-04 | Calendario | Generar dim_tiempo | dim_tiempo | sp_poblar_dim_tiempo() |
| TR-05 | Medidas ventas | venta_bruta, venta_neta, costo_total, margen | fact_ventas | precio * cantidad * (1-descuento) |
| TR-06 | Días entrega | shipped_date - order_date | fact_ventas | DATEDIFF |
| TR-07 | Manejo nulos | Ship region/city nulos → 'No especificado' | dim_geografia | COALESCE |
| TR-08 | Costos | 60% de UnitPrice | product_costos | UnitPrice * 0.60 |
| TR-09 | Metas | promedio histórico mensual + 10% | dim_metas | AVG por empleado * 1.10 |

2.2. Guarda como `M.xlsx` en la raíz del proyecto.

---

## Paso 3 — Completar el diccionario de datos

3.1. Abre/crea `Plantilla_Diccionario_Datos_BI.xlsx` con una hoja por capa (Fuente, Staging, DW).
3.2. Por cada tabla, lista:
   - Nombre, tipo, descripción, ¿es PK?, ¿es FK?, nullable, ejemplo.
3.3. Para el DW incluye una columna extra: **rol** (Dimensión, Hecho, Surrogate Key, BK, Medida aditiva, Medida semiaditiva).

---

## Paso 4 — Manual de instalación consolidado (Anexo A)

4.1. Revisa que el Anexo A del MD principal cubra TODOS los componentes:
   - Docker Desktop
   - WSL2
   - Java 21
   - NiFi 2.x
   - Drivers JDBC
   - DBeaver
   - Tableau Desktop
   - SQL Server 2022 Developer + SSAS Tabular
   - SSMS
   - Visual Studio 2022 + Analysis Services Projects
   - Tabular Editor 2
   - MySQL Connector/ODBC
   - DSN de sistema
4.2. Cada componente: link de descarga + versión usada + ruta de instalación.
4.3. Captura por cada componente instalado.

---

## Paso 5 — Manual técnico del ETL (Anexo B)

5.1. Documenta cada Controller Service de NiFi con sus parámetros (sin contraseñas, solo username y conexión).
5.2. Documenta cada Process Group con captura del lienzo.
5.3. Documenta cada procesador del Pipeline 1 y Pipeline 2 con:
   - Nombre
   - Función
   - SQL (si aplica)
   - Conexiones de entrada/salida
5.4. Sección de manejo de errores: cómo identificar flow files en cola "failure", cómo reintentar.

---

## Paso 6 — Manual del usuario del ETL (Anexo B.2)

6.1. Para alguien que solo necesita CORRER el ETL (no entenderlo):
   ```
   1. Abrir Docker Desktop. Verificar 3 contenedores corriendo (docker ps).
   2. Abrir NiFi: http://127.0.0.1:8080/nifi
   3. Doble clic en el Process Group "Pipeline 1 - Fuente a Staging".
   4. Click derecho en "Trigger ..." de cada tabla → Run Once.
   5. Esperar 30 segundos. Validar conteos en DBeaver (Staging).
   6. Volver al lienzo raíz. Doble clic en "Pipeline 2 - Staging a DW".
   7. Disparar Trigger dim_cliente, dim_producto, dim_empleado, dim_transportista, dim_geografia, product_costos (orden libre).
   8. Disparar Trigger fact_landing.
   9. Disparar Trigger fact_ventas.
   10. Validar conteos en DBeaver (DW).
   11. En SSMS: Process Full sobre Northwind_Semantico.
   12. Refrescar Tableau.
   ```
6.2. Para cada paso, captura.

---

## Paso 7 — Manual de la visualización (Anexo C)

7.1. C.1 Técnico:
   - Conector usado, server, base.
   - Cómo refrescar la conexión.
   - Cómo abrir el `.twb` desde cero.
7.2. C.2 Usuario:
   - Por cada dashboard, descripción de qué muestra y cómo interpretarlo.
   - Lista de filtros disponibles y su efecto.

---

## Paso 8 — Empaquetar el entregable

8.1. Estructura final del entregable:
```
PROYECTOBD/
├── DOCUMENTO_PROYECTO_BI.md         (o .pdf)
├── DOCUMENTO_PROYECTO_BI.pdf        (exportado)
├── PLAN_DE_TRABAJO.md
├── M.xlsx
├── Plantilla_Diccionario_Datos_BI.xlsx
├── docker-compose.yml
├── docs/                            (las 9 FASE_XX_*.md)
├── sql/
│   └── instnwnd.sql
├── nifi-templates/
│   ├── Pipeline_1.json
│   └── Pipeline_2.json
├── ssas/
│   ├── Northwind_BI/                (solución Visual Studio)
│   ├── config_servidor_4.md
│   └── diccionario_medidas.md
├── tableau/
│   └── Northwind_BI.twb
└── capturas/
    ├── 00/ ... 08/
```

8.2. Exporta el MD a PDF (DBeaver/VS Code tienen extensiones para esto; o pega en un Word y exporta).
8.3. Comprime todo en `Proyecto_BI_William_Yaruro.zip`.

---

## Paso 9 — Preparar la sustentación

9.1. **Guion de 8-10 minutos**:
   1. (1 min) Contexto: fuente Northwind, herramientas, arquitectura de 4 servidores independientes.
   2. (1 min) Mostrar `docker ps` → 3 contenedores + services.msc → SSAS Tabular.
   3. (2 min) Recorrer NiFi: Pipeline 1 incremental, Pipeline 2 con transformaciones.
   4. (1 min) Mostrar el modelo en Visual Studio: relaciones, medidas DAX clave.
   5. (3 min) Demo Tableau: navegar los 3 dashboards respondiendo las 10 preguntas.
   6. (1 min) Cerrar: punto extra (modelo semántico), supuestos del Anexo D.
9.2. **Demo en vivo opcional**: insertar pedido en fuente → correr pipelines → refrescar SSAS → mostrar el dato nuevo en Tableau. Si no confías en la demo en vivo, ten una versión grabada de respaldo.
9.3. **Preguntas frecuentes que puede hacer el profesor**:
   - "¿Por qué ETL y no ELT?" → porque transformamos antes de cargar el DW, dejando este último limpio y modelado.
   - "¿Por qué SCD Tipo 1?" → alcance académico, sin historicidad requerida en las preguntas.
   - "¿Cómo detectas cambios?" → watermark en OrderID. Updates y deletes no se detectan (Anexo D).
   - "¿Por qué SSAS si Tableau ya tiene su motor?" → para optar al punto extra, centralizar medidas y poder reusarlas si mañana cambias de visualizador.
   - "¿Servidores realmente independientes?" → sí, 4 procesos distintos con red/almacenamiento/puerto propios (3 contenedores + 1 servicio Windows).

---

## Paso 10 — Checklist final antes de entregar

- [ ] `DOCUMENTO_PROYECTO_BI.md` completo, todas las capturas en su lugar
- [ ] PDF exportado del documento
- [ ] `M.xlsx` con las 3 hojas llenas
- [ ] Diccionario de datos completo
- [ ] `docker-compose.yml` versionado
- [ ] Pipelines NiFi exportados como JSON
- [ ] Solución VS del modelo Tabular incluida
- [ ] Workbook Tableau `.twb` incluido
- [ ] Las 9 carpetas de capturas con su contenido
- [ ] ZIP final generado
- [ ] Guion de sustentación ensayado al menos 2 veces
- [ ] Plan B para demo (video grabado) listo

---

## Cierre

Cuando estés satisfecho con todo, envías el ZIP por la plataforma del curso y agendas la sustentación.

¡Buena suerte! Si surge algo durante una fase, regrésate al documento correspondiente y revisa el paso específico.
