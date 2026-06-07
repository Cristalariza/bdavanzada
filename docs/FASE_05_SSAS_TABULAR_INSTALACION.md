# Fase 5 — Servidor 4: Instalación de SSAS Tabular + herramientas

**Objetivo:** instalar SQL Server 2022 Developer con **Analysis Services en modo Tabular** (Servidor 4 / puerto 2383), más SSMS, Visual Studio + extensión Analysis Services Projects, Tabular Editor 2, y el conector ODBC para que SSAS pueda leer del DW MySQL.
**Tiempo estimado:** 2 horas (gran parte es descarga + instalación).
**Prerrequisitos:** Fases 0-4 completadas. El DW debe estar poblado.

---

## Paso 1 — Descargar SQL Server 2022 Developer

1.1. Ve a https://www.microsoft.com/en-us/sql-server/sql-server-downloads
1.2. Busca la sección "Developer" (gratis, full features) → "Download now".
1.3. Se descarga un instalador pequeño (`SQL2022-SSEI-Dev.exe`).
1.4. Ejecútalo.

---

## Paso 2 — Instalar SQL Server Developer con Analysis Services Tabular

2.1. En la primera pantalla del instalador, elige **Custom** (NO "Basic", porque queremos seleccionar componentes).
2.2. **Install Location:** déjala por defecto (`C:\SQL2022`).
2.3. Clic en Install. Descargará ~2 GB.
2.4. Cuando termine la descarga, se abre el **SQL Server Installation Center**.
2.5. Lateral izquierdo → **Installation** → "New SQL Server standalone installation or add features".
2.6. **Edition:** selecciona **Developer**. Next.
2.7. Acepta los términos. Next.
2.8. **Feature Selection** → marca:
   - **Database Engine Services** (recomendado, te sirve para tener SQL Server local nativo si lo necesitas).
   - **Analysis Services** ✅ (este es el importante).
2.9. Next.
2.10. **Instance Configuration**:
   - Selecciona **Named instance**.
   - Nombre: `TABULAR`.
   - Instance ID: déjalo `TABULAR`.
2.11. Next hasta llegar a **Analysis Services Configuration**:
   - **Server Mode:** ✅ **Tabular Mode** (NO Multidimensional).
   - **Specify Analysis Services administrators** → clic en **Add Current User**.
2.12. Next → Database Engine Configuration:
   - Authentication: **Mixed Mode**.
   - Password: `Northwind2026!` (para uniformidad).
   - Add Current User.
2.13. Next → Install.
2.14. Espera 15-30 minutos. Cuando termine, verifica que aparezca todo en verde.
2.15. **CAPTURA:** la pantalla final de "Complete" con los checks verdes.

---

## Paso 3 — Validar que SSAS está corriendo

3.1. Win+R → escribe `services.msc` → Enter.
3.2. Busca **SQL Server Analysis Services (TABULAR)**. Estado: **Running**. Startup Type: **Automatic**.
3.3. Si no está Running, clic derecho → Start.
3.4. Verifica también **SQL Server (TABULAR)** corriendo (el motor relacional asociado).
3.5. **CAPTURA:** services.msc filtrado por "SQL".

---

## Paso 4 — Instalar SSMS (SQL Server Management Studio)

4.1. Ve a https://aka.ms/ssmsfullsetup
4.2. Descarga e instala con valores por defecto.
4.3. Abre SSMS.
4.4. **Connect → Analysis Services**:
   - **Server name:** `localhost\TABULAR`
   - **Authentication:** Windows Authentication.
   - Connect.
4.5. En el Object Explorer debe aparecer el servidor SSAS con carpetas **Databases** (vacía) y **Connections**.
4.6. **CAPTURA:** SSMS conectado a SSAS Tabular.

---

## Paso 5 — Instalar Visual Studio 2022 Community

5.1. Ve a https://visualstudio.microsoft.com/vs/community/ y descarga.
5.2. En el **Visual Studio Installer**, en "Workloads", marca:
   - **Data storage and processing** (carga grande, ~5 GB).
5.3. NO necesitas Web/Desktop/Mobile a menos que ya lo uses para otra cosa.
5.4. Install. Espera 20-30 min.
5.5. Al terminar, abre Visual Studio.
5.6. **CAPTURA:** VS abierto en la pantalla de inicio.

---

## Paso 6 — Instalar la extensión "Microsoft Analysis Services Projects"

6.1. En Visual Studio: **Extensions → Manage Extensions**.
6.2. Pestaña **Online** → busca **"Microsoft Analysis Services Projects"**.
6.3. Download. La instalación se completa cuando cierres Visual Studio.
6.4. Cierra VS. Aparecerá el **VSIX Installer** → Modify → Close.
6.5. Vuelve a abrir VS → **File → New → Project** → busca "Analysis Services".
6.6. Debe aparecer **"Analysis Services Tabular Project"**. Si está, la extensión funciona.
6.7. **CAPTURA:** plantilla de proyecto Tabular visible.

---

## Paso 7 — Instalar Tabular Editor 2 (recomendado, opcional pero MUY útil)

7.1. Ve a https://github.com/TabularEditor/TabularEditor/releases/latest
7.2. Descarga el archivo `TabularEditor.Installer.msi`.
7.3. Instala. Es ligero (~30 MB).
7.4. Ábrelo → **File → Open → From DB** → Server: `localhost\TABULAR` → Cancel (todavía no hay BD).
7.5. **CAPTURA:** Tabular Editor abierto.

---

## Paso 8 — Instalar MySQL Connector/ODBC

Este conector lo necesita SSAS para leer del DW MySQL.

8.1. Ve a https://dev.mysql.com/downloads/connector/odbc/
8.2. Descarga la versión **8.x Windows MSI Installer 64-bit**.
8.3. Ejecuta el MSI → Typical → Install.
8.4. **CAPTURA:** wizard de instalación al final.

---

## Paso 9 — Crear el DSN de sistema para el DW

El DSN (Data Source Name) es lo que SSAS verá como "MySQL DW".

9.1. Win+R → `odbcad32.exe` (la versión 64-bit; cuidado, hay una 32-bit en `%WINDIR%\SysWOW64\odbcad32.exe` que NO debes usar).
9.2. Pestaña **System DSN** → Add.
9.3. Selecciona **MySQL ODBC 8.x Unicode Driver** → Finish.
9.4. Llena:
   - **Data Source Name:** `DW_NORTHWIND`
   - **Description:** `Data Warehouse Northwind para SSAS Tabular`
   - **TCP/IP Server:** `localhost`
   - **Port:** `3306`
   - **User:** `root` (o `etl_user` si confirmaste sus permisos)
   - **Password:** `Northwind2026!`
   - **Database:** `dw_northwind`
9.5. Clic en **Test**. Debe decir "Connection Successful". Si falla, revisa que `dw_mysql` esté corriendo (`docker ps`).
9.6. Pestaña **Connection** → marca **Allow big result sets**.
9.7. OK.
9.8. **CAPTURA:** DSN creado en la lista + el "Test Successful".

---

## Paso 10 — Probar que SSMS conecta a SSAS y al DW desde el mismo equipo

10.1. En SSMS, ya tienes la conexión a SSAS Tabular abierta.
10.2. Abre otra ventana de Connect → **Database Engine** → Server: `localhost\TABULAR` → Connect (este es el motor relacional, NO el Tabular).
10.3. Verifica que aparezcan en el Object Explorer **dos** nodos diferentes:
   - `localhost\TABULAR` (Analysis Services, ícono cubo verde).
   - `localhost\TABULAR` (Database Engine, ícono cilindro).
10.4. **CAPTURA:** SSMS con ambas conexiones.

---

## Paso 11 — Crear backup de la configuración

11.1. Crea un archivo `ssas\config_servidor_4.md` en tu proyecto con:

```
Servidor 4 - SSAS Tabular

- Versión: SQL Server 2022 Developer Edition
- Instancia: localhost\TABULAR
- Modo: Tabular
- Puerto: 2383 (estándar SSAS)
- Autenticación: Windows
- Administrador: <tu_usuario_windows>
- Base de datos a crear: Northwind_Semantico

DSN ODBC para origen de datos:
- Nombre: DW_NORTHWIND
- Driver: MySQL ODBC 8.x Unicode Driver
- Servidor: localhost:3306
- Base: dw_northwind
- Usuario: root / Northwind2026!

Herramientas instaladas:
- SSMS (gestión)
- Visual Studio 2022 Community + Analysis Services Projects (desarrollo)
- Tabular Editor 2 (edición rápida de DAX)
```

---

## Checklist de cierre de la Fase 5

- [ ] SQL Server Developer instalado con instancia `TABULAR`
- [ ] Servicio "SQL Server Analysis Services (TABULAR)" en estado Running
- [ ] SSMS conecta a `localhost\TABULAR` (modo Analysis Services)
- [ ] Visual Studio 2022 + extensión Analysis Services Projects instalada
- [ ] Tabular Editor 2 instalado
- [ ] MySQL Connector/ODBC 8.x instalado
- [ ] DSN `DW_NORTHWIND` creado y conexión exitosa
- [ ] `ssas\config_servidor_4.md` creado
- [ ] Capturas en `capturas\05\` (mínimo 7)

**"Fase 5 lista"** → pasamos a la Fase 6 (construir el modelo semántico + medidas DAX).
