# Fase 0 — Preparación del ambiente

**Objetivo:** dejar la máquina lista con todo el software base instalado antes de tocar contenedores, bases de datos o ETL.
**Tiempo estimado:** 1 hora.
**Prerrequisitos:** Windows 10/11 con permisos de administrador y al menos 16 GB de RAM.

---

## Convenciones del proyecto

Voy a usar estas constantes en TODOS los documentos siguientes. Anótalas:

| Concepto | Valor |
|---|---|
| Contraseña SQL Server (`sa`) | `Northwind2026!` |
| Contraseña MySQL (`root`) | `Northwind2026!` |
| Contraseña SSAS (auth Windows) | tu usuario Windows |
| Ruta del proyecto | `C:\Users\<TU_USUARIO>\OneDrive\Pictures\Desktop\PROYECTOBD\` |
| Carpeta de capturas | `<RUTA_PROYECTO>\capturas\<NUMERO_FASE>\` |

---

## Paso 1 — Verificar requisitos de Windows

1.1. Abre **PowerShell** (NO administrador todavía).
1.2. Escribe `winver` y presiona Enter. Debe abrirse una ventana mostrando "Windows 11" o "Windows 10 versión 21H2 o superior".
1.3. Cierra esa ventana.
1.4. En PowerShell escribe `systeminfo | findstr /B /C:"Total Physical Memory"`. Debe mostrar **al menos 16 GB**. Si tienes 8 GB el proyecto correrá lento pero funcional; si tienes menos, considera otro equipo.
1.5. **CAPTURA:** la ventana de `winver` + la línea de memoria.

---

## Paso 2 — Habilitar WSL2

WSL2 es lo que Docker Desktop usa por debajo para correr los contenedores Linux.

2.1. Cierra PowerShell y vuelve a abrirlo **como Administrador** (clic derecho → "Ejecutar como administrador").
2.2. Ejecuta:
```
wsl --install
```
2.3. Si dice "ya está instalado", ejecuta:
```
wsl --set-default-version 2
wsl --update
```
2.4. Reinicia el equipo si te lo pide.
2.5. Tras reiniciar, abre PowerShell normal y ejecuta `wsl --status`. Debe decir "Default Version: 2".
2.6. **CAPTURA:** la salida de `wsl --status`.

---

## Paso 3 — Instalar Docker Desktop

3.1. Ve a https://www.docker.com/products/docker-desktop/ y descarga el instalador para Windows.
3.2. Ejecuta el `.exe`. Cuando pregunte, **marca** "Use WSL 2 instead of Hyper-V".
3.3. Acepta y deja que termine. Te pedirá cerrar sesión o reiniciar — hazlo.
3.4. Al iniciar Docker Desktop por primera vez, salta el tutorial.
3.5. Ve a **Settings (engranaje) → General** y verifica que esté marcado "Use the WSL 2 based engine".
3.6. Ve a **Settings → Resources → Advanced** y asigna:
   - **Memory:** mínimo 8 GB (recomendado 10 GB si tienes 16 GB).
   - **CPUs:** mínimo 4.
   - **Disk image size:** 60 GB.
3.7. Clic en **Apply & Restart**.
3.8. En PowerShell, ejecuta:
```
docker --version
docker run hello-world
```
La segunda línea debe imprimir "Hello from Docker!". Si falla, espera a que Docker Desktop termine de arrancar (ícono ballena en bandeja del sistema, ojo a que diga "Engine running").
3.9. **CAPTURA:** la salida de `docker --version` y el "Hello from Docker!".

---

## Paso 4 — Descargar drivers JDBC para NiFi

NiFi corre dentro de un contenedor Docker (lo levantaremos en la Fase 1) pero necesita los drivers JDBC para hablar con SQL Server y MySQL. Esos drivers se montan al contenedor desde la carpeta local `nifi\drivers\`.

> **Ya NO necesitas:** instalar Java 21 ni descargar el binario de NiFi. Todo eso vive dentro del contenedor `nifi` declarado en `docker-compose.yml`.

4.1. **SQL Server JDBC:** ve a https://learn.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server y descarga el ZIP del driver más reciente. Extrae solamente el archivo `mssql-jdbc-X.X.X.jre11.jar` (o `jre17.jar`) a `<RUTA_PROYECTO>\nifi\drivers\`.
4.2. **MySQL JDBC:** ve a https://dev.mysql.com/downloads/connector/j/ y descarga "Platform Independent" (ZIP). Extrae `mysql-connector-j-X.X.X.jar` a `<RUTA_PROYECTO>\nifi\drivers\`.
4.3. Verifica que en `nifi\drivers\` haya 2 archivos `.jar`.
4.4. **CAPTURA:** explorador mostrando los dos `.jar`.

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

- [ ] `wsl --status` muestra "Default Version: 2"
- [ ] `docker run hello-world` funciona
- [ ] `nifi\drivers\` tiene 2 `.jar` (SQL Server + MySQL)
- [ ] DBeaver abre sin error
- [ ] Tableau Desktop instalado (con trial o licencia)
- [ ] `sql\instnwnd.sql` descargado
- [ ] Estructura de carpetas del proyecto creada
- [ ] 7 capturas guardadas en `capturas\00\`

Cuando esté listo, avísame con **"Fase 0 lista"** y pasamos a la Fase 1.
