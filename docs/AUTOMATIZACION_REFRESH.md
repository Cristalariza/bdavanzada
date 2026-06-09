# Automatización del refresh end-to-end

Documento que describe **cómo orquestar el flujo completo del ETL + refresh del modelo semántico sin intervención humana**.

El proyecto en su estado actual está pensado para sustentación (Run Once manual), pero la arquitectura está preparada para automatización completa. Este documento describe el plan de producción.

---

## El problema a resolver

Un usuario humano corriendo Run Once en NiFi y F5 en SSMS no es sostenible. En producción se necesita que el pipeline completo corra sin intervención.

### Flujo de dependencias

```
SQL Server (fuente OLTP)
    ↓
NiFi Pipeline 1 (Fuente → Staging)        ← se programa con CRON
    ↓ (debe terminar antes que el 2)
NiFi Pipeline 2 (Staging → DW)            ← se programa con CRON después del 1
    ↓ (debe terminar antes del refresh)
SSAS Process Full (DW → modelo semántico) ← se programa con Task Scheduler
    ↓
Tableau (refresh automático al abrir)
```

Cada flecha es una dependencia temporal. Hay 2 enfoques para resolverla:

| Enfoque | Pros | Contras |
|---|---|---|
| **A. Cascada de horarios** | Simple, fácil de configurar | Si el Pipeline 1 demora más de lo esperado, el 2 corre con datos viejos |
| **B. Orquestación con NiFi** | Sin ventanas de tiempo, encadena automático | Más complejo de configurar |

Recomendado: empezar con A para producción inicial, migrar a B cuando crezca el volumen.

---

## Enfoque A — Cascada de horarios (recomendado para iniciar)

### Componente 1 — NiFi Pipeline 1 (02:00 AM)

**Configurar todos los Triggers de Pipeline 1 así:**

| Property | Valor |
|---|---|
| Scheduling Strategy | **CRON driven** |
| Run Schedule | `0 0 2 * * ?` |

Esto los hace correr todos los días a las 02:00:00.

**Triggers a configurar** (8 en total):
- Trigger Categories
- Trigger Suppliers
- Trigger Products
- Trigger Customers
- Trigger Employees
- Trigger Shippers
- EXTRACT Orders (incremental)
- EXTRACT Order Details (incremental)

Tiempo estimado de Pipeline 1: **2-3 minutos** para el dataset Northwind. En un DW con millones de filas, podría tardar 30-60 min.

### Componente 2 — NiFi Pipeline 2 (02:30 AM)

Configurar los Triggers de Pipeline 2 con un offset de 30 minutos:

| Property | Valor |
|---|---|
| Scheduling Strategy | **CRON driven** |
| Run Schedule | `0 30 2 * * ?` |

**Triggers a configurar** (7 en total):
- Trigger dim_cliente, dim_producto, dim_empleado, dim_transportista, dim_geografia, product_costos, fact_landing, fact_ventas.

### Componente 3 — Refresh SSAS (03:00 AM)

El refresh de SSAS no se programa en NiFi — se programa en **Windows Task Scheduler** porque SSAS está fuera del ecosistema Docker.

**Script PowerShell**: [scripts/refresh_ssas.ps1](../scripts/refresh_ssas.ps1)

#### Configurar en Task Scheduler

1. Win+R → `taskschd.msc` → Enter.
2. Panel derecho → **Crear tarea básica...** (o "Create Basic Task").
3. **Nombre**: `BI Northwind - SSAS Refresh Diario`.
4. **Descripción**: `Refresh diario del modelo semantico Northwind_Semantico despues del ETL`.
5. **Desencadenador**: **Diariamente** → hora **03:00:00**.
6. **Acción**: **Iniciar un programa**.
7. **Programa**: `powershell.exe`
8. **Argumentos**:
   ```
   -ExecutionPolicy Bypass -File "C:\Users\crist\OneDrive\Pictures\Desktop\PROYECTOBD\scripts\refresh_ssas.ps1"
   ```
9. **Iniciar en**: `C:\Users\crist\OneDrive\Pictures\Desktop\PROYECTOBD\`
10. Pestaña **Configuración** → marcar **Ejecutar con los permisos más altos**.
11. OK → te pide credenciales Windows → ingresar tu password.

#### Validar la tarea

Después de crearla:

1. Selecciona la tarea en la lista.
2. Panel derecho → **Ejecutar** (manual, para test).
3. Espera 30 segundos.
4. Revisa el log en `logs/ssas_refresh.log`. Debe terminar con `===== Fin refresh OK =====`.

#### Tiempo total automático

```
02:00 → NiFi Pipeline 1 arranca   (3 min)
02:30 → NiFi Pipeline 2 arranca   (1 min)
03:00 → SSAS refresh              (1 min)
03:01 → Dashboards en Tableau actualizados
```

Al día siguiente cuando alguien abra Tableau, los datos están frescos.

---

## Enfoque B (RECOMENDADO) — File trigger: NiFi → Windows en tiempo real

Este enfoque es **event-driven**: NiFi avisa a Windows que el ETL terminó, y Windows refresca SSAS inmediatamente. Sin ventanas de tiempo, sin polling.

### Arquitectura

```
Pipeline 2 termina → NiFi PutFile escribe nifi-triggers\refresh.flag
                                              ↓
                  Volumen compartido entre Docker (Linux) y Windows
                                              ↓
                  PowerShell watch_and_refresh.ps1 detecta el archivo
                                              ↓
                  Ejecuta refresh_ssas.ps1 → SSAS actualiza
                                              ↓
                  Borra el .flag y vuelve a esperar
```

### Componentes ya implementados en el repo

| Componente | Ubicación | Estado |
|---|---|---|
| Volumen Docker para triggers | `docker-compose.yml` línea `./nifi-triggers:/opt/nifi/nifi-current/triggers` | ✓ |
| Carpeta compartida | `nifi-triggers/` | ✓ creada |
| Watcher PowerShell | `scripts/watch_and_refresh.ps1` | ✓ |
| Script de refresh | `scripts/refresh_ssas.ps1` | ✓ probado |

### Setup en 4 pasos

#### Paso 1 — Reiniciar el contenedor NiFi para montar el volumen nuevo

```powershell
docker compose down nifi
docker compose up -d nifi
```

> Espera 2-3 min a que NiFi vuelva a estar disponible en `https://localhost:8443/nifi`.

#### Paso 2 — Agregar el procesador PutFile al final de Pipeline 2

En NiFi → Pipeline 2 → al final del subflujo `fact_ventas` (después de `LOAD fact_ventas + dim_metas`):

1. Arrastra **Processor → PutFile**.
2. Doble clic → Settings → Name: `Trigger SSAS Refresh`.
3. Properties:

| Property | Value |
|---|---|
| Directory | `/opt/nifi/nifi-current/triggers` |
| Conflict Resolution Strategy | `replace` |
| Create Missing Directories | `true` |

4. Relationships → ☑ terminate en `success`, `failure`.
5. Apply.

#### Paso 3 — Conectar `LOAD fact_ventas + dim_metas` → `Trigger SSAS Refresh`

Arrastra una flecha entre los 2 procesadores → relación `success` → Add.

#### Paso 4 — Programar el watcher en Task Scheduler (que arranque automático)

1. Win+R → `taskschd.msc` → Enter.
2. **Crear tarea** (no "tarea básica").
3. Pestaña **General**:
   - Nombre: `BI Northwind - Watcher Refresh SSAS`
   - ☑ Ejecutar tanto si el usuario está conectado como si no.
   - ☑ Ejecutar con los privilegios más altos.
   - Configurar para: Windows 10.
4. Pestaña **Desencadenadores** → Nuevo:
   - Iniciar la tarea: **Al iniciar el sistema**.
   - ☑ Habilitado.
5. Pestaña **Acciones** → Nueva:
   - Acción: **Iniciar un programa**.
   - Programa: `powershell.exe`
   - Argumentos: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\crist\OneDrive\Pictures\Desktop\PROYECTOBD\scripts\watch_and_refresh.ps1"`
   - Iniciar en: `C:\Users\crist\OneDrive\Pictures\Desktop\PROYECTOBD\`
6. Pestaña **Configuración** → desmarcar "Detener la tarea si se ejecuta más de..."
7. OK → pide password Windows.

#### Paso 5 — Iniciar el watcher manualmente (primera vez, para validar)

```powershell
.\scripts\watch_and_refresh.ps1
```

Déjalo corriendo. En otra ventana de PowerShell, simula NiFi:

```powershell
echo "test" > nifi-triggers\refresh-test.flag
```

El watcher debe detectarlo en <1 segundo, ejecutar el refresh, y borrar el archivo. Revisa `logs/watcher.log` y `logs/ssas_refresh.log`.

### Cómo se ve en producción

```
03:00:00 - NiFi (cron) ejecuta Pipeline 1 (extracción incremental)
03:02:34 - Pipeline 1 termina
03:30:00 - NiFi (cron) ejecuta Pipeline 2 (transformaciones)
03:30:45 - LOAD fact_ventas termina → escribe nifi-triggers\refresh-20260609-033045.flag
03:30:46 - Watcher detecta el flag → ejecuta refresh_ssas.ps1
03:30:48 - SSAS terminado de refrescar
03:30:48 - Watcher borra el flag y vuelve a esperar
```

**Total**: <3 segundos entre que termina el ETL y los dashboards de Tableau están actualizados.

### Ventajas vs el Enfoque A (cascada de horarios)

| | Enfoque A (horarios fijos) | Enfoque B (file trigger) |
|---|---|---|
| Sincronización | Asume tiempos | Event-driven, sin asunciones |
| Riesgo si ETL demora más | Refresh corre con datos viejos | Refresh espera a que termine |
| Latencia entre ETL y refresh | 30 min de espera fija | <3 segundos |
| Configuración | 2 tareas separadas | 1 watcher continuo |
| Resiliencia | Falla silenciosa si ETL demora | El flag asegura el orden |

---

## Enfoque C — Orquestación con NiFi (avanzado)

NiFi puede llamar al refresh de SSAS al final de Pipeline 2, eliminando las ventanas de tiempo fijas.

### Cómo

Al final del subflujo `fact_ventas` (después del `LOAD fact_ventas + dim_metas`), agregar 1 procesador:

**`ExecuteStreamCommand`**:
- **Command Path**: `powershell.exe`
- **Command Arguments**: `-ExecutionPolicy Bypass -File /opt/nifi/nifi-current/scripts/refresh_ssas.ps1`
- **Working Directory**: `/opt/nifi/nifi-current/scripts/`

> Esto requiere montar el script dentro del contenedor NiFi como volumen y que SSAS sea accesible desde el contenedor (en Linux, complejo). Para una versión local Windows, mejor el Enfoque A.

### Alternativa con InvokeHTTP

SSAS Tabular expone un endpoint HTTP/XMLA en `/xmla`. NiFi puede hacer POST directo:

**`InvokeHTTP`**:
- **HTTP Method**: `POST`
- **URL**: `http://localhost:2382/xmla`
- **Content-Type**: `text/xml`
- **Request Body**: el TMSL del refresh envuelto en XMLA SOAP.

Requiere autenticación Kerberos o configurar HTTP en SSAS — más complejo de configurar pero es la solución "cloud-ready".

---

## Monitoreo y alertas

### Log de refresh

`logs/ssas_refresh.log` — incremental, cada ejecución agrega líneas:

```
[2026-06-09 03:00:01] [INFO] ===== Iniciando refresh =====
[2026-06-09 03:00:01] [INFO] Servidor: localhost\TABULAR
[2026-06-09 03:00:32] [INFO] Refresh completado en 31.42 segundos.
[2026-06-09 03:00:32] [INFO] ===== Fin refresh OK =====
```

Si hay error:

```
[2026-06-09 03:00:15] [ERROR] ERROR despues de 14.5s : The connection either timed out or was lost...
```

### Notificación por correo si falla

Modificar el script para que envíe email en caso de error. Agregar al final del bloque `catch`:

```powershell
Send-MailMessage `
    -SmtpServer "smtp.office365.com" `
    -From "etl-alerts@empresa.com" `
    -To "datateam@empresa.com" `
    -Subject "ETL Northwind FALLO - SSAS refresh" `
    -Body "Revisar log en $LogPath. Error: $_" `
    -Port 587 -UseSsl -Credential $cred
```

(Requiere configurar credenciales SMTP. Para producción: usar Azure Application Insights o un sistema de monitoreo dedicado.)

---

## Validación end-to-end (1 vez al mes)

Para garantizar que el flujo automático sigue funcionando, hay un script de validación cruzada que compara la fuente con el modelo semántico:

```sql
-- 1. En SQL Server (fuente):
USE Northwind;
SELECT ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS total_fuente
FROM [Order Details] od;
```

```sql
-- 2. En MySQL DW (warehouse):
SELECT ROUND(SUM(venta_neta), 2) AS total_dw FROM dw_northwind.fact_ventas;
```

```dax
// 3. En SSAS (modelo semantico) - via SSMS New Query MDX:
EVALUATE { [Ventas Netas] }
```

Los 3 números deben coincidir al centavo. Si difieren, algo está mal en el ETL — el log de NiFi y el log de ssas_refresh dicen cuál fue la corrida fallida.

---

## Resumen

| Estado actual del proyecto | Estado de producción |
|---|---|
| Run Once manual en NiFi | NiFi con `0 0 2 * * ?` (CRON) |
| F5 manual en SSMS | Task Scheduler ejecuta `refresh_ssas.ps1` a las 03:00 |
| Refresh a demanda en Tableau | Automático al abrir el dashboard |

El cambio de "demostración" a "producción" requiere **2 acciones de configuración** (cambiar el `Run Schedule` de los Triggers de NiFi + crear 1 tarea programada de Windows). Cero cambios de código.
