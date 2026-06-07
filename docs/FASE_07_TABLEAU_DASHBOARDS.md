# Fase 7 — Tableau: instalación, conexión a SSAS y dashboards

**Objetivo:** instalar/activar Tableau Desktop, conectarlo al modelo semántico SSAS Tabular, construir una hoja por cada pregunta de negocio y ensamblar los dashboards finales.
**Tiempo estimado:** 3 horas (puede dividirse en 2 sesiones).
**Prerrequisitos:** Fase 6 completada (modelo `Northwind_Semantico` desplegado).

---

## Paso 1 — Activar Tableau Desktop con licencia de estudiante

1.1. Si todavía no llegó tu correo de Tableau for Students, primero ve a https://www.tableau.com/academic/students y solicítala.
1.2. Mientras tanto, abre Tableau Desktop instalado en la Fase 0.
1.3. Pantalla de bienvenida → si pide product key, ingrésalo. Si no llegó, clic en **"Start trial now"** (14 días).
1.4. Verifica tu versión: **Help → About Tableau**. Anótala (mínimo 2022.1 para conector SSAS estable).
1.5. **CAPTURA:** Tableau abierto con la licencia activa.

---

## Paso 2 — Conectar Tableau a SSAS Tabular

2.1. En la pantalla de inicio de Tableau, panel izquierdo **Connect → To a Server → More**.
2.2. Selecciona **Microsoft Analysis Services**.
2.3. Llena:
   - **Server:** `localhost\TABULAR`
   - **Authentication:** **Use Windows Authentication**
2.4. Sign In.
2.5. En el panel de la izquierda, despliega **Database** → selecciona `Northwind_Semantico`.
2.6. Tableau muestra el cubo único con todas las medidas y tablas.
2.7. **CAPTURA:** pestaña Data Source con el modelo conectado.

> **Si falla la conexión:**
> - Verifica que el servicio SSAS esté Running (services.msc).
> - El firewall puede estar bloqueando el puerto 2383 — agrega excepción para `localhost`.
> - Si Tableau no encuentra el conector, descarga el **Analysis Services Connector** desde la página de drivers de Tableau.

---

## Paso 3 — Verificar las medidas y dimensiones

3.1. En el panel izquierdo (Data), debes ver:
   - **Medidas (Measures)**: las 10 que creaste en DAX.
   - **Dimensiones**: las tablas con sus columnas visibles (las `*_sk` no aparecen porque las ocultaste).
   - **Jerarquía Calendario** en `dim_tiempo`.
3.2. Si falta algo, vuelve al modelo en VS, revisa lo oculto y re-despliega.
3.3. **CAPTURA:** panel Data expandido mostrando medidas y dimensiones.

---

## Paso 4 — Hoja 1: "Ventas por periodo" (pregunta 1)

4.1. Nueva hoja → renómbrala `Q1_Ventas_Por_Periodo`.
4.2. Arrastra **dim_tiempo.Calendario** → Columns. Tableau muestra la jerarquía (drill-down).
4.3. Arrastra **[Ventas Netas]** → Rows.
4.4. En el panel Marks, cambia el tipo a **Line**.
4.5. Arrastra **[Ventas YoY %]** a Rows también → genera un dual axis.
4.6. Clic derecho en el eje secundario → **Synchronize Axis** (deja distintos si quieres comparación clara).
4.7. Filtra por años: Filters → dim_tiempo[anio] → marca 1996, 1997, 1998.
4.8. Título de la hoja: "Evolución de ventas por mes y año".
4.9. **CAPTURA:** la hoja terminada.

---

## Paso 5 — Hoja 2: "Top 10 Clientes" (pregunta 2)

5.1. Nueva hoja → `Q2_Top10_Clientes`.
5.2. Rows: **dim_cliente[company_name]**.
5.3. Columns: **[Ventas Netas]**.
5.4. Filters → arrastra company_name → Top → By field: Top 10 by [Ventas Netas].
5.5. Sort descending por [Ventas Netas].
5.6. Marks → Bar. Color: gradient azul.
5.7. Agrega tabla auxiliar: duplica la hoja → cambia a Text Table → agrega [Cantidad Vendida] y [Margen]. Renómbrala `Q2_Top10_Detalle`.
5.8. **CAPTURA:** ambas hojas.

---

## Paso 6 — Hoja 3: "Productos más vendidos" (pregunta 3)

6.1. Nueva hoja → `Q3_Productos_Top`.
6.2. Rows: **dim_producto[product_name]** (Top 15 by [Cantidad Vendida]).
6.3. Columns: **[Cantidad Vendida]**.
6.4. Etiqueta con **[% Contribucion]** en Label.
6.5. Sort desc.
6.6. **CAPTURA.**

---

## Paso 7 — Hoja 4: "Categorías" (pregunta 4)

7.1. Nueva hoja → `Q4_Categorias`.
7.2. Marks: **Treemap** (Show Me → Treemap, segundo de arriba).
7.3. Tamaño: **[Ventas Netas]**.
7.4. Color: **dim_producto[category_name]**.
7.5. Etiqueta: category_name + [% Contribucion].
7.6. **CAPTURA.**

---

## Paso 8 — Hoja 5: "Empleados vs Metas" (pregunta 5)

8.1. Nueva hoja → `Q5_Empleados_vs_Metas`.
8.2. Rows: **dim_empleado[nombre_completo]**.
8.3. Columns: **[Ventas Netas]** y **[Meta Mensual]** (lado a lado).
8.4. Crea una hoja gemela con **[Cumplimiento Meta %]** como barras horizontales y línea de referencia en 100%.
8.5. **CAPTURA.**

> Si `dim_metas` no genera valores razonables (porque depende del cálculo de Fase 4 paso 9), revísalo. Para la sustentación puede usarse una meta fija si los promedios salen distorsionados.

---

## Paso 9 — Hoja 6: "Territorios" (pregunta 6)

9.1. Nueva hoja → `Q6_Territorios`.
9.2. Doble clic en **dim_geografia[pais]**. Tableau lo reconoce como geográfico automáticamente y crea el mapa.
9.3. Color: **[Ventas Netas]** (gradient).
9.4. Tamaño: **[Cantidad Vendida]**.
9.5. Si algunos países no se reconocen (ej. "USA" vs "United States"): clic en el ícono naranja "X countries unknown" → asigna manualmente.
9.6. **CAPTURA.**

---

## Paso 10 — Hoja 7: "Tiempos de entrega" (pregunta 7)

10.1. Nueva hoja → `Q7_Tiempos_Entrega`.
10.2. Rows: **dim_geografia[pais]**.
10.3. Columns: **[Dias Entrega Promedio]**.
10.4. Sort desc.
10.5. Línea de referencia en el promedio global.
10.6. Versión adicional: por **dim_cliente[company_name]**, top 10 peores.
10.7. **CAPTURA.**

---

## Paso 11 — Hoja 8: "Margen por producto" (pregunta 8)

11.1. Nueva hoja → `Q8_Margen_Producto`.
11.2. Rows: **dim_producto[product_name]** (Top 15 by [Margen]).
11.3. Columns: **[Margen]**.
11.4. Color: **[% Contribucion]**.
11.5. **CAPTURA.**

---

## Paso 12 — Hoja 9: "Clientes inactivos" (pregunta 9)

12.1. Nueva hoja → `Q9_Clientes_Inactivos`.
12.2. KPI grande con **[Clientes Inactivos]**.
12.3. Tabla auxiliar: lista de clientes con su **última fecha de compra** (usando dim_cliente + Max(dim_tiempo[fecha])).
12.4. Para la lista crea un cálculo en Tableau:
   - Analysis → Create Calculated Field → "Ultima Compra" = `MAX([fecha])`
12.5. **CAPTURA.**

---

## Paso 13 — Hoja 10: "Estacionalidad" (pregunta 10)

13.1. Nueva hoja → `Q10_Estacionalidad`.
13.2. Rows: **dim_tiempo[anio]**.
13.3. Columns: **dim_tiempo[nombre_mes]** (ordenado por mes).
13.4. Marks: **Square** (heatmap).
13.5. Color: **[Ventas Netas]** (gradient verde-rojo).
13.6. **CAPTURA.**

---

## Paso 14 — Dashboard 1: "Resumen Ejecutivo"

14.1. New Dashboard → tamaño Desktop (1366×768) o "Automatic".
14.2. Arrastra **floating** o **tiled**:
   - Q1 arriba (línea de ventas).
   - Q4 abajo-izquierda (treemap categorías).
   - Q6 abajo-derecha (mapa).
14.3. Agrega título: "Northwind BI — Resumen Ejecutivo".
14.4. Filtros globales: año, país. Clic derecho en el filtro → **Apply to Worksheets → All Using This Data Source**.
14.5. **CAPTURA.**

---

## Paso 15 — Dashboard 2: "Clientes y Productos"

15.1. New Dashboard.
15.2. Q2 (top 10 clientes), Q3 (productos), Q8 (margen), Q9 (inactivos).
15.3. **CAPTURA.**

---

## Paso 16 — Dashboard 3: "Operaciones"

16.1. Q5 (empleados vs metas), Q7 (tiempos), Q10 (estacionalidad).
16.2. **CAPTURA.**

---

## Paso 17 — Guardar el archivo Tableau

17.1. **File → Save As → Tableau Workbook (.twb)**, **NO** .twbx (twbx empaqueta datos, lo cual no queremos porque vivimos en SSAS).
17.2. Guarda en `tableau\Northwind_BI.twb`.
17.3. Cierra Tableau, ábrelo de nuevo, abre el archivo, verifica que reconecte a SSAS sin pedir nada.
17.4. **CAPTURA:** archivo guardado.

---

## Paso 18 — Probar el refresco completo

Para asegurar que todo el flujo funciona end-to-end:

18.1. En SQL Server, agrega un pedido nuevo (como en Fase 3 paso 9.1).
18.2. En NiFi, corre Pipeline 1 (incremental) y luego Pipeline 2 (full reload del fact).
18.3. En SSMS, **Process Full** sobre `Northwind_Semantico`.
18.4. En Tableau, **Data → Refresh** (o cierra y reabre el workbook).
18.5. El nuevo pedido debe reflejarse en las hojas (incremento en Q1, posiblemente nuevo cliente en Q2).
18.6. **CAPTURA:** Q1 antes y después.

---

## Checklist de cierre de la Fase 7

- [ ] Tableau Desktop activado (licencia o trial)
- [ ] Conexión a `localhost\TABULAR / Northwind_Semantico` funcional
- [ ] 10 hojas creadas (una por pregunta), todas con datos coherentes
- [ ] 3 dashboards ensamblados con filtros globales (año, país)
- [ ] Workbook guardado como `tableau\Northwind_BI.twb`
- [ ] Refresco end-to-end probado (inserto en fuente → cambio en dashboard)
- [ ] Capturas en `capturas\07\` (mínimo 14)

**"Fase 7 lista"** → pasamos a la Fase 8 (documentación final + sustentación).
