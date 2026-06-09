# Servidor 4 — SSAS Tabular

Configuración del cuarto servidor del proyecto BI Northwind: motor analítico OLAP en memoria que aloja el modelo semántico consumido por Tableau.

## Motor

| | |
|---|---|
| Producto | Microsoft SQL Server 2025 |
| Edición | Enterprise Developer Edition (gratis para uso no productivo) |
| Componente | SQL Server Analysis Services (SSAS) |
| Modo | **Tabular Mode** (in-memory, modelo columnar Vertipaq) |
| Hospedaje | Nativo en Windows (Microsoft no publica imagen Docker para SSAS) |

> ¿Por qué Tabular y no Multidimensional? Tabular usa el motor in-memory Vertipaq + DAX, optimizado para Power BI / Tableau / Excel y para modelos derivados de un esquema estrella relacional. Multidimensional usa cubos OLAP con MDX, más adecuado para jerarquías muy complejas y modelos legacy.

## Instancia

| | |
|---|---|
| Nombre de instancia | `TABULAR` |
| Host de conexión | `localhost\TABULAR` (o `KARASU\TABULAR`) |
| Puerto | Dinámico, redireccionado por SQL Server Browser (estándar SSAS para instancias nombradas) |
| Autenticación | Windows Authentication |
| Administrador | Usuario Windows actual (agregado durante el setup como SSAS admin) |

## Bases de datos a desplegar

| Base | Origen | Propósito |
|---|---|---|
| `Northwind_Semantico` | Visual Studio Tabular Project | Modelo semántico con dimensiones, medidas DAX, jerarquías; consumido por Tableau |

## DSN ODBC para origen de datos

SSAS lee del DW MySQL vía este DSN del sistema. Se creó como **System DSN** (no User DSN) para que el servicio `SQL Server Analysis Services (TABULAR)` pueda usarlo aunque corra bajo una cuenta distinta a la del usuario.

| | |
|---|---|
| Nombre del DSN | `DW_NORTHWIND` |
| Driver | MySQL ODBC 9.7 Unicode Driver (64-bit) |
| Servidor | `localhost:3306` |
| Base de datos | `dw_northwind` |
| Usuario | `root` |
| Contraseña | `Northwind2026!` |
| Tipo | System DSN |
| Allow big result sets | activado |

## Herramientas del cliente instaladas

| Herramienta | Versión | Para qué |
|---|---|---|
| SQL Server Management Studio | 19.3 (clásico) | Conectarse a SSAS, ejecutar DAX/MDX, validar despliegue |
| Visual Studio 2022 Community | 17.x | IDE principal del modelo semántico |
| Extensión Microsoft Analysis Services Projects | 2022+ | Plantilla "Analysis Services Tabular Project" |
| Tabular Editor 2 | 2.x | Editor especializado para medidas DAX y refactor del modelo |

> **Nota:** se usó SSMS 19 clásico porque las versiones SSMS 20+/21 (basadas en VS 2022) aún no implementan conexiones a Analysis Services en su UI al momento de la instalación (junio 2026). SSMS 19 sigue soportado oficialmente por Microsoft.

## Servicios de Windows

Verificables en `services.msc`:

| Servicio | Estado esperado | Notas |
|---|---|---|
| `SQL Server (TABULAR)` | Running | Motor relacional asociado a la instancia (opcional para SSAS, útil si se quiere usar el motor SQL local) |
| `SQL Server Analysis Services (TABULAR)` | Running | **El servicio crítico** — es el SSAS Tabular |
| `SQL Server Browser` | Running | Resuelve los puertos dinámicos de las instancias nombradas |
| `SQL Server Analysis Services CEIP (TABULAR)` | Stopped | Telemetría, opcional |

Validación rápida del proceso por línea de comandos:
```powershell
Get-Process msmdsrv -ErrorAction SilentlyContinue | Select-Object Name, Id, StartTime
```
Si aparece `msmdsrv` con PID, SSAS está corriendo.

## Conexión desde otras herramientas

| Cliente | Cadena de conexión |
|---|---|
| SSMS | Server type: Analysis Services, Server name: `localhost\TABULAR`, Auth: Windows |
| Tabular Editor | File → Open → From DB → Server: `localhost\TABULAR` |
| Tableau Desktop | Microsoft Analysis Services → Server: `localhost\TABULAR`, Database: `Northwind_Semantico` |
| Excel | Data → Get Data → From Database → From Analysis Services |

## Origen de datos del modelo

El modelo Tabular importa estas 8 tablas del DW vía el DSN `DW_NORTHWIND`:

- `dim_tiempo` (~2191 filas)
- `dim_cliente` (91)
- `dim_producto` (77)
- `dim_empleado` (9)
- `dim_geografia` (~70)
- `dim_transportista` (3)
- `dim_metas` (192)
- `fact_ventas` (2155)

No se importan `etl_control`, `fact_landing` ni `product_costos` — son zonas internas del ETL que no aportan al modelo semántico.
