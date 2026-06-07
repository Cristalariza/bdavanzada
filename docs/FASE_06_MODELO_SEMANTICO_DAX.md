# Fase 6 — Modelo semántico SSAS Tabular + medidas DAX

**Objetivo:** crear el proyecto Tabular en Visual Studio, importar las tablas del DW MySQL vía el DSN ODBC, definir relaciones del esquema estrella, crear la jerarquía de tiempo y escribir las 10 medidas DAX que responden las preguntas de negocio. Desplegar a `localhost\TABULAR` como `Northwind_Semantico`.
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fase 5 completada. DW poblado.

---

## Paso 1 — Crear el proyecto Tabular en Visual Studio

1.1. Abre **Visual Studio 2022**.
1.2. **File → New → Project**.
1.3. Filtra por "Analysis Services" → selecciona **"Analysis Services Tabular Project"** → Next.
1.4. **Project name:** `Northwind_Semantico`.
1.5. **Location:** `C:\Users\<TU_USUARIO>\OneDrive\Pictures\Desktop\PROYECTOBD\ssas\`.
1.6. **Solution name:** `Northwind_BI`.
1.7. Create.
1.8. Aparece el diálogo **Tabular Model Designer**:
   - **Workspace server:** `localhost\TABULAR`.
   - **Compatibility level:** **SQL Server 2022 / Azure Analysis Services (1600)** o más alto. NO uses 1500.
   - **Integrated workspace** marcado.
   - OK.
1.9. **CAPTURA:** Visual Studio con el proyecto vacío y la pestaña "Model.bim" abierta.

---

## Paso 2 — Importar tablas desde el DW MySQL

2.1. En el menú **Model → Import From Data Source**.
2.2. Selecciona **Other → ODBC** → Next.

> Si "ODBC" no aparece directamente, selecciona **OLE DB / ODBC** según la versión de la extensión.

2.3. **Build** la cadena de conexión → en **Use connection string**:
   ```
   Dsn=DW_NORTHWIND;
   ```
   O si pide DSN directo, selecciónalo de la lista.
2.4. Provee credenciales: usuario `root`, password `Northwind2026!`.
2.5. Next.
2.6. Selecciona **"Select from a list of tables and views to choose the data to import"** → Next.
2.7. Marca las siguientes tablas:
   - ✅ `dim_tiempo`
   - ✅ `dim_cliente`
   - ✅ `dim_producto`
   - ✅ `dim_empleado`
   - ✅ `dim_geografia`
   - ✅ `dim_transportista`
   - ✅ `dim_metas`
   - ✅ `fact_ventas`

   **NO importes:** `etl_control`, `fact_landing`, `product_costos` (no las necesita el modelo semántico).
2.8. Finish. Espera que importe (~30-60 segundos).
2.9. Si te pregunta sobre relaciones automáticas, **dile "No"**: las crearás manualmente para tener control.
2.10. **CAPTURA:** las 8 tablas importadas con sus filas.

---

## Paso 3 — Vista de diagrama y relaciones

3.1. En la esquina inferior derecha de Visual Studio, cambia a **Diagram View**.
3.2. Verás las 8 tablas como cajas. Acomódalas en forma de estrella: `fact_ventas` al centro, dimensiones alrededor.
3.3. Crea las relaciones arrastrando desde la SK del hecho a la SK de la dimensión:

| Tabla origen | Columna origen | Tabla destino | Columna destino | Tipo |
|---|---|---|---|---|
| fact_ventas | tiempo_sk | dim_tiempo | tiempo_sk | Many-to-One (single direction) |
| fact_ventas | cliente_sk | dim_cliente | cliente_sk | Many-to-One |
| fact_ventas | producto_sk | dim_producto | producto_sk | Many-to-One |
| fact_ventas | empleado_sk | dim_empleado | empleado_sk | Many-to-One |
| fact_ventas | geografia_sk | dim_geografia | geografia_sk | Many-to-One |
| fact_ventas | transportista_sk | dim_transportista | transportista_sk | Many-to-One |
| dim_metas | empleado_sk | dim_empleado | empleado_sk | Many-to-One |

3.4. **CAPTURA:** diagrama con 7 líneas de relación.

---

## Paso 4 — Marcar `dim_tiempo` como tabla de tiempo

DAX necesita saber cuál es la tabla de tiempo para que funciones como SAMEPERIODLASTYEAR operen.

4.1. Vista **Data View** → pestaña `dim_tiempo`.
4.2. Clic en el encabezado de la columna `fecha`.
4.3. Menú **Table → Date → Mark as Date Table**.
4.4. En el diálogo, selecciona `fecha` como la columna de fecha. OK.
4.5. **CAPTURA:** el aviso de "Date Table marked".

---

## Paso 5 — Crear la jerarquía Año › Trimestre › Mes › Día

5.1. En Diagram View → tabla `dim_tiempo` → clic en el ícono de jerarquía (a la derecha del header) → **Create Hierarchy**.
5.2. Nombre: `Calendario`.
5.3. Arrastra a la jerarquía, en orden:
   - `anio` (renombra el nivel a "Año")
   - `trimestre` (Trimestre)
   - `mes` (Mes)
   - `dia` (Día)
5.4. **CAPTURA:** jerarquía completa.

---

## Paso 6 — Ocultar columnas técnicas en Tableau

Las SK no aportan al usuario final.

6.1. En cada tabla, selecciona las columnas SK (`*_sk`) → clic derecho → **Hide from Client Tools**.
6.2. También oculta `customer_id`, `product_id`, `employee_id`, `shipper_id` (claves de negocio que no se usan en visualizaciones).
6.3. **CAPTURA:** las columnas hidden marcadas con ícono diferente.

---

## Paso 7 — Crear las 10 medidas DAX

En la **Data View**, abre la tabla `fact_ventas`. En el área "Measure Grid" abajo, escribe cada medida en una celda diferente.

> **Cómo crear una medida:** clic en una celda vacía del Measure Grid → escribe `NombreMedida := <fórmula>` → Enter. La medida queda asociada a la tabla.

### Medida 1 — Ventas Netas (pregunta 1, 2, 4, 6, 10)
```
Ventas Netas := SUM ( fact_ventas[venta_neta] )
```
Formato: número con 2 decimales, separador de miles.

### Medida 2 — Ventas Año Anterior
```
Ventas Año Anterior :=
CALCULATE ( [Ventas Netas], SAMEPERIODLASTYEAR ( dim_tiempo[fecha] ) )
```

### Medida 3 — Variación YoY %
```
Ventas YoY % :=
VAR _act = [Ventas Netas]
VAR _ant = [Ventas Año Anterior]
RETURN
DIVIDE ( _act - _ant, _ant )
```
Formato: porcentaje.

### Medida 4 — Cantidad Vendida (pregunta 3)
```
Cantidad Vendida := SUM ( fact_ventas[cantidad] )
```

### Medida 5 — % Contribución a Ventas Totales (preguntas 3, 4)
```
% Contribucion :=
DIVIDE (
    [Ventas Netas],
    CALCULATE ( [Ventas Netas], ALL ( fact_ventas ) )
)
```
Formato: porcentaje.

### Medida 6 — Meta Mensual (pregunta 5)
```
Meta Mensual := SUM ( dim_metas[meta_mensual] )
```

### Medida 7 — Cumplimiento Meta % (pregunta 5)
```
Cumplimiento Meta % := DIVIDE ( [Ventas Netas], [Meta Mensual] )
```
Formato: porcentaje.

### Medida 8 — Días Entrega Promedio (pregunta 7)
```
Dias Entrega Promedio :=
AVERAGEX (
    FILTER ( fact_ventas, NOT ISBLANK ( fact_ventas[dias_entrega] ) ),
    fact_ventas[dias_entrega]
)
```
Formato: número con 1 decimal.

### Medida 9 — Margen Total (pregunta 8)
```
Margen := SUM ( fact_ventas[margen] )
```

### Medida 10 — Clientes Activos / Inactivos (pregunta 9)
```
Clientes Activos :=
CALCULATE (
    DISTINCTCOUNT ( fact_ventas[cliente_sk] ),
    DATESINPERIOD ( dim_tiempo[fecha], MAX ( dim_tiempo[fecha] ), -365, DAY )
)

Clientes Inactivos :=
VAR _total = DISTINCTCOUNT ( dim_cliente[cliente_sk] )
VAR _activos = [Clientes Activos]
RETURN _total - _activos
```

7.1. **CAPTURA:** las 10 medidas visibles en el Measure Grid (puede ser 2 capturas).

---

## Paso 8 — Validar las medidas con un Pivot rápido

8.1. Visual Studio → menú **Model → Analyze in Excel** (si tienes Excel instalado). Esto abre Excel con una tabla dinámica conectada al modelo.
8.2. Arrastra `dim_tiempo[anio]` a filas, `[Ventas Netas]` a valores.
8.3. Debe mostrar 3 filas (1996, 1997, 1998) con sumas distintas.
8.4. Comparar contra el SELECT del paso 11.2 de la Fase 4 — los números deben coincidir EXACTOS.
8.5. **CAPTURA:** la tabla dinámica + el SELECT comparativo.

> Si no tienes Excel: usa SSMS → New Query (sobre la BD del workspace) → escribe DAX directamente:
> ```
> EVALUATE
> SUMMARIZECOLUMNS ( dim_tiempo[anio], "Ventas", [Ventas Netas] )
> ```

---

## Paso 9 — Desplegar a `localhost\TABULAR`

9.1. En el Solution Explorer, clic derecho sobre el proyecto **Northwind_Semantico → Properties**.
9.2. **Deployment Server:**
   - **Server:** `localhost\TABULAR`.
   - **Database:** `Northwind_Semantico`.
   - **Cube Name:** `Northwind_Semantico`.
9.3. Apply → OK.
9.4. Clic derecho sobre el proyecto → **Deploy**.
9.5. Espera. Al final debe decir "Deploy succeeded".
9.6. Abre SSMS → conecta a `localhost\TABULAR` (Analysis Services) → expande **Databases**. Debe aparecer **Northwind_Semantico**.
9.7. **CAPTURA:** SSMS mostrando la base desplegada con sus tablas y medidas.

---

## Paso 10 — Probar la base desplegada con consultas MDX/DAX desde SSMS

10.1. En SSMS, clic derecho sobre `Northwind_Semantico` → **New Query → MDX**.
10.2. Escribe:
   ```
   EVALUATE
   SUMMARIZECOLUMNS (
     dim_producto[category_name],
     "Ventas", [Ventas Netas],
     "Contribucion", [% Contribucion]
   )
   ORDER BY [Ventas] DESC
   ```
10.3. Ejecuta (F5). Debe retornar las 8 categorías con totales.
10.4. **CAPTURA:** resultado de la query.

---

## Paso 11 — Documentar las medidas para Tableau

11.1. Crea `ssas\diccionario_medidas.md` con la tabla de las 10 medidas, su fórmula y la pregunta de negocio que responden. (Este archivo te sirve para el manual del visualizador en Fase 7.)

---

## Paso 12 — (Opcional pero recomendado) Refrescar el modelo con datos nuevos

Cuando corras el ETL otra vez (más datos en el DW), tienes que refrescar el modelo:

12.1. SSMS → clic derecho sobre `Northwind_Semantico` → **Process Database** → Process Mode: **Process Full** → OK.
12.2. Espera. Las medidas se recalculan al vuelo, no hace falta volver a desplegar.

---

## Checklist de cierre de la Fase 6

- [ ] Proyecto VS `Northwind_Semantico` creado en `ssas\`
- [ ] 8 tablas importadas desde el DW MySQL via DSN ODBC
- [ ] 7 relaciones creadas en el diagrama (estrella)
- [ ] `dim_tiempo` marcada como Date Table
- [ ] Jerarquía `Calendario` (Año › Trimestre › Mes › Día) creada
- [ ] Columnas técnicas (`*_sk`, BKs) ocultas para Tableau
- [ ] 10 medidas DAX escritas y validadas
- [ ] Suma de ventas en el modelo coincide con SELECT del DW
- [ ] Modelo desplegado a `localhost\TABULAR` como `Northwind_Semantico`
- [ ] Consulta DAX desde SSMS retorna resultados correctos
- [ ] `ssas\diccionario_medidas.md` creado
- [ ] Capturas en `capturas\06\` (mínimo 10)

**"Fase 6 lista"** → pasamos a la Fase 7 (Tableau).
