# Fase 0 — Preparación del ambiente

**Objetivo:** dejar la máquina lista. Como ya tienes Docker funcionando, esto es bootstrapear los contenedores con un script y luego instalar lo poco que **no** puede vivir en Docker (cliente DB, Tableau, etc.).
**Tiempo estimado:** 30 minutos.
**Prerrequisitos:** Docker Desktop corriendo. Cliente PowerShell.

---

## Convenciones del proyecto

| Concepto | Valor |
|---|---|
| Contraseña SQL Server (`sa`) | `Northwind2026!` |
| Contraseña MySQL (`root` / `etl_user`) | `Northwind2026!` / `EtlUser2026!` |
| Contraseña NiFi UI | `admin` / `NifiAdmin2026!` |
| Contraseña SSAS | autenticación Windows (tu usuario) |
| Ruta del proyecto | `C:\Users\<TU_USUARIO>\OneDrive\Pictures\Desktop\PROYECTOBD\` |
| Carpeta de capturas | `<RUTA_PROYECTO>\capturas\<NUMERO_FASE>\` |

---

## Paso 1 — Verificar Docker

1.1. Abre PowerShell.
1.2. Ejecuta:
   ```powershell
   docker info | Select-String "Server Version"
   ```
   Debe imprimir una línea con la versión. Si da error, abre Docker Desktop y espera a que el ícono de ballena diga "Engine running".

---

## Paso 2 — Ejecutar el bootstrap (descarga drivers + levanta contenedores)

2.1. Desde la raíz del proyecto, en PowerShell:
   ```powershell
   .\scripts\setup_containers.ps1
   ```
2.2. El script hace TODO esto por ti:
   - Descarga `mssql-jdbc-12.8.1.jre11.jar` y `mysql-connector-j-8.4.0.jar` a `nifi\drivers\` (solo si faltan).
   - `docker compose pull` para imágenes al día.
   - `docker compose up -d` (levanta los 4 contenedores).
   - Espera 30 s y muestra el estado final con `docker ps`.

2.3. **Si PowerShell bloquea el script** por política de ejecución, una sola vez:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
   y reintenta.

2.4. Al final debes ver los 4 contenedores en estado `Up`:
   ```
   NAMES               STATUS              PORTS
   source_sqlserver    Up X minutes        0.0.0.0:1433->1433/tcp
   staging_mysql       Up X minutes        0.0.0.0:3307->3306/tcp
   dw_mysql            Up X minutes        0.0.0.0:3306->3306/tcp
   nifi                Up X minutes        0.0.0.0:8443->8443/tcp
   ```
2.5. **CAPTURA:** salida del script + `docker ps`.

> NiFi tarda **2-3 minutos adicionales** en estar accesible vía web después de aparecer como `Up`. Es normal.

---

## Paso 5 — Instalar DBeaver Community (cliente universal)

DBeaver es el cliente que vas a usar para conectarte a SQL Server, MySQL Staging y MySQL DW.

5.1. Ve a https://dbeaver.io/download/ y descarga "Community Edition · Windows (installer)".
5.2. Instala con valores por defecto.
5.3. Ábrelo. Cierra los wizards iniciales (no crees conexiones todavía).
5.4. **CAPTURA:** DBeaver abierto con su workspace vacío.

---

## Paso 6 — Descargar Tableau Desktop

6.1. Ve a https://www.tableau.com/academic/students y solicita la licencia gratuita de estudiante (requiere correo institucional + carnet/certificado).
6.2. Mientras llega el correo de activación, descarga el instalador desde el mismo sitio.
6.3. Ejecuta el `.exe`. Instala con valores por defecto.
6.4. Al abrir Tableau pedirá un product key — pégalo cuando llegue (24-48 h normalmente). Si no ha llegado, usa el **trial de 14 días** para no bloquearte.
6.5. **CAPTURA:** Tableau Desktop abierto en la pantalla de inicio.

> Nota: la activación del producto se hace al inicio de la Fase 7. Si por ahora solo lo instalas y registras el trial, es suficiente.

---

## Paso 7 — Descargar el script de Northwind

7.1. Ve a https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/northwind-pubs.
7.2. Descarga el archivo **`instnwnd.sql`** (clic en el archivo → botón "Download raw file").
7.3. Guárdalo en `<RUTA_PROYECTO>\sql\instnwnd.sql`.
7.4. **CAPTURA:** el archivo en el explorador.

---

## Paso 8 — Verificar estructura de carpetas del proyecto

Dentro de `<RUTA_PROYECTO>\` deben quedar estas carpetas (la mayoría ya están en el repo de Git):

```
PROYECTOBD\
├── docs\                  (los 9 FASE_XX_*.md)
├── sql\
│   ├── instnwnd.sql       (lo descargas en el paso 7)
│   ├── staging-init\      (DDL del staging para auto-arranque MySQL)
│   └── dw-init\           (DDL del DW para auto-arranque MySQL)
├── nifi\
│   └── drivers\           (drivers JDBC del paso 4)
├── nifi-templates\        (crea tú; aquí guardarás los .json exportados)
├── tableau\               (crea tú; aquí guardarás los .twb)
├── ssas\                  (crea tú; proyecto Visual Studio)
├── capturas\
│   ├── 00\ ... 08\        (crea tú)
├── docker-compose.yml     (ya está en el repo)
├── DOCUMENTO_PROYECTO_BI.md
└── PLAN_DE_TRABAJO.md
```

8.1. Crea las carpetas que falten (`nifi-templates\`, `tableau\`, `ssas\`, `capturas\00\` … `capturas\08\`) desde el Explorador de Windows.
8.2. **CAPTURA:** la estructura final en el explorador.

---

## Checklist de cierre de la Fase 0

Antes de pasar a la Fase 1 verifica que **TODO** esté en verde:

- [ ] `docker info` responde
- [ ] `setup_containers.ps1` ejecutado sin errores
- [ ] 4 contenedores corriendo (`docker ps`)
- [ ] `nifi\drivers\` tiene 2 `.jar` (descargados por el script)
- [ ] DBeaver abre sin error
- [ ] Tableau Desktop instalado (con trial o licencia)
- [ ] `sql\instnwnd.sql` descargado
- [ ] Estructura de carpetas del proyecto creada
- [ ] Capturas guardadas en `capturas\00\`

Cuando esté listo, avísame con **"Fase 0 lista"** y pasamos a la Fase 1.
