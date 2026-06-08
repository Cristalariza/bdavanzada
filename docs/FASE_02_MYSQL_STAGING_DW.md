# Fase 2 — Servidores 2 y 3: MySQL Staging + MySQL Data Warehouse

**Objetivo:** levantar dos instancias **independientes** de MySQL 8 (Servidor 2 = Staging en puerto 3307, Servidor 3 = DW en puerto 3306) y crear sus estructuras: tablas espejo del Staging y esquema estrella del DW.
**Tiempo estimado:** 1.5 horas.
**Prerrequisitos:** Fase 1 completada (SQL Server corriendo, Northwind cargado).

---

## Paso 1 — Revisar los servicios MySQL en `docker-compose.yml`

Los dos MySQL **ya están declarados** en el `docker-compose.yml` del repo. Revísalos para entender qué hacen antes de levantarlos:

```yaml
staging_mysql:
  image: mysql:8.0
  container_name: staging_mysql
  hostname: staging_mysql
  environment:
    MYSQL_ROOT_PASSWORD: "Northwind2026!"
    MYSQL_DATABASE: "staging_northwind"
    MYSQL_USER: "etl_user"
    MYSQL_PASSWORD: "EtlUser2026!"
  ports:
    - "3307:3306"
  volumes:
    - staging_data:/var/lib/mysql
    - ./sql/staging-init:/docker-entrypoint-initdb.d
  networks:
    - bi_network

dw_mysql:
  image: mysql:8.0
  container_name: dw_mysql
  hostname: dw_mysql
  environment:
    MYSQL_DATABASE: "dw_northwind"
    ... (similar)
  ports:
    - "3306:3306"
  volumes:
    - dw_data:/var/lib/mysql
    - ./sql/dw-init:/docker-entrypoint-initdb.d
  networks:
    - bi_network
```

1.1. Puntos clave:
   - **Dos servicios MySQL distintos** (`staging_mysql` y `dw_mysql`) con volúmenes y bases distintas. Son **servidores independientes**.
   - El puerto **interno** de MySQL es siempre 3306. El **mapeo externo** es lo que los diferencia desde Windows: **3307** para staging, **3306** para DW.
   - Desde el contenedor `nifi`, sin embargo, los ves por nombre: `staging_mysql:3306` y `dw_mysql:3306` (puerto interno).
   - `./sql/staging-init` y `./sql/dw-init` se mapean a `/docker-entrypoint-initdb.d/`. MySQL ejecuta automáticamente cualquier `.sql` ahí **la primera vez** que arranca con el volumen vacío.

## Paso 1.B — (Opcional) Pre-cargar DDL para auto-arranque

Si pones tu DDL en `sql\staging-init\01_staging.sql` y `sql\dw-init\02_dw.sql` ANTES de arrancar los contenedores por primera vez, MySQL crea las tablas automáticamente. Si los pones después, tendrás que hacer `docker compose down -v staging_mysql dw_mysql` para recrear los volúmenes.

Para esta guía vamos a crear las tablas **manualmente desde DBeaver** (Pasos 4 y 5), así controlas qué pasa y no dependes del auto-arranque.

---

## Paso 2 — Verificar los dos MySQL

Ya corren desde el bootstrap de Fase 0. Validar:

2.1. En PowerShell:
   ```powershell
   docker ps --filter "name=staging_mysql" --filter "name=dw_mysql"
   ```
2.2. Si alguno falta, levántalo:
   ```powershell
   docker compose up -d staging_mysql dw_mysql
   ```
2.4. Inspecciona los puertos:
```powershell
docker port staging_mysql
docker port dw_mysql
```
Deben mostrar `3306/tcp -> 0.0.0.0:3307` y `3306/tcp -> 0.0.0.0:3306` respectivamente.
2.5. **CAPTURA:** `docker ps` con los 3 contenedores + las dos salidas de `docker port`.

---

## Paso 3 — Conectar DBeaver a los dos MySQL

3.1. En DBeaver, **Database → New Database Connection** → **MySQL** → Next.
3.2. Primera conexión = **Staging**:
   - **Server Host:** `localhost`
   - **Port:** `3307`
   - **Database:** `staging_northwind`
   - **Username:** `root`
   - **Password:** `Northwind2026!`
   - **Test Connection** (acepta descarga de driver si lo pide) → Finish.
   - Renómbrala a **"MySQL Staging (3307)"**.
3.3. Repite para el **DW**:
   - **Port:** `3306`
   - **Database:** `dw_northwind`
   - Resto igual.
   - Renómbrala a **"MySQL DW (3306)"**.
3.4. Ambas conexiones deben aparecer en el panel izquierdo de DBeaver.
3.5. **CAPTURA:** DBeaver mostrando las 3 conexiones (SQL Server + Staging + DW).

---

## Paso 4 — Crear las tablas del Staging (Servidor 2)

El Staging es **espejo 1:1** de Northwind. Nombres en `snake_case`, sin transformaciones.

4.1. En DBeaver, doble clic en **MySQL Staging (3307)** → confirma que la base activa es `staging_northwind`.
4.2. Abre un **SQL Editor nuevo** y escribe el siguiente DDL. **Léelo entendiendo cada decisión** antes de ejecutarlo:

```sql
-- =============================================
-- STAGING NORTHWIND — Servidor 2 (puerto 3307)
-- Regla: copia 1:1 de la fuente. Sin transformar.
-- =============================================

-- Tabla de control para carga incremental
CREATE TABLE etl_control (
    proceso        VARCHAR(50) PRIMARY KEY,
    ultimo_valor   VARCHAR(100),
    fecha_ejecucion DATETIME DEFAULT CURRENT_TIMESTAMP,
    registros_cargados INT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Categorías
CREATE TABLE stg_categories (
    CategoryID   INT PRIMARY KEY,
    CategoryName VARCHAR(15),
    Description  TEXT
    -- Picture (binario) NO se carga, decisión documentada en Anexo D
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Proveedores
CREATE TABLE stg_suppliers (
    SupplierID   INT PRIMARY KEY,
    CompanyName  VARCHAR(40),
    ContactName  VARCHAR(30),
    ContactTitle VARCHAR(30),
    Address      VARCHAR(60),
    City         VARCHAR(15),
    Region       VARCHAR(15),
    PostalCode   VARCHAR(10),
    Country      VARCHAR(15),
    Phone        VARCHAR(24),
    Fax          VARCHAR(24),
    HomePage     TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Productos
CREATE TABLE stg_products (
    ProductID       INT PRIMARY KEY,
    ProductName     VARCHAR(40),
    SupplierID      INT,
    CategoryID      INT,
    QuantityPerUnit VARCHAR(20),
    UnitPrice       DECIMAL(10,2),
    UnitsInStock    SMALLINT,
    UnitsOnOrder    SMALLINT,
    ReorderLevel    SMALLINT,
    Discontinued    TINYINT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Clientes
CREATE TABLE stg_customers (
    CustomerID   VARCHAR(5) PRIMARY KEY,
    CompanyName  VARCHAR(40),
    ContactName  VARCHAR(30),
    ContactTitle VARCHAR(30),
    Address      VARCHAR(60),
    City         VARCHAR(15),
    Region       VARCHAR(15),
    PostalCode   VARCHAR(10),
    Country      VARCHAR(15),
    Phone        VARCHAR(24),
    Fax          VARCHAR(24)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Empleados
CREATE TABLE stg_employees (
    EmployeeID      INT PRIMARY KEY,
    LastName        VARCHAR(20),
    FirstName       VARCHAR(10),
    Title           VARCHAR(30),
    TitleOfCourtesy VARCHAR(25),
    BirthDate       DATE,
    HireDate        DATE,
    Address         VARCHAR(60),
    City            VARCHAR(15),
    Region          VARCHAR(15),
    PostalCode      VARCHAR(10),
    Country         VARCHAR(15),
    HomePhone       VARCHAR(24),
    Extension       VARCHAR(4),
    Notes           TEXT,
    ReportsTo       INT
    -- Photo (binario) NO se carga
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Transportistas
CREATE TABLE stg_shippers (
    ShipperID   INT PRIMARY KEY,
    CompanyName VARCHAR(40),
    Phone       VARCHAR(24)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Pedidos (cabecera)
CREATE TABLE stg_orders (
    OrderID        INT PRIMARY KEY,
    CustomerID     VARCHAR(5),
    EmployeeID     INT,
    OrderDate      DATETIME,
    RequiredDate   DATETIME,
    ShippedDate    DATETIME,
    ShipVia        INT,
    Freight        DECIMAL(10,2),
    ShipName       VARCHAR(40),
    ShipAddress    VARCHAR(60),
    ShipCity       VARCHAR(15),
    ShipRegion     VARCHAR(15),
    ShipPostalCode VARCHAR(10),
    ShipCountry    VARCHAR(15)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Detalle de pedidos
CREATE TABLE stg_order_details (
    OrderID    INT,
    ProductID  INT,
    UnitPrice  DECIMAL(10,2),
    Quantity   SMALLINT,
    Discount   FLOAT,
    PRIMARY KEY (OrderID, ProductID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Inicializar control ETL
INSERT INTO etl_control (proceso, ultimo_valor) VALUES
('stg_orders_max_orderid', '0'),
('stg_order_details_max_orderid', '0');
```

4.3. Ejecuta todo el script (Alt+X).
4.4. Verifica con:
```sql
SHOW TABLES;
```
Debe listar **9 tablas**: las 8 `stg_*` + `etl_control`.
4.5. **CAPTURA:** `SHOW TABLES` con el resultado.

---

## Paso 5 — Crear las tablas del Data Warehouse (Servidor 3)

El DW usa **esquema estrella**: dimensiones con surrogate keys + tabla de hechos central.

5.1. En DBeaver, doble clic en **MySQL DW (3306)** → base activa `dw_northwind`.
5.2. Abre SQL Editor nuevo y ejecuta:

```sql
-- =============================================
-- DATA WAREHOUSE NORTHWIND — Servidor 3 (puerto 3306)
-- Modelo: esquema estrella, SCD Tipo 1.
-- =============================================

-- Dimensión Tiempo
CREATE TABLE dim_tiempo (
    tiempo_sk    INT PRIMARY KEY,           -- formato YYYYMMDD
    fecha        DATE NOT NULL,
    anio         SMALLINT NOT NULL,
    trimestre    TINYINT NOT NULL,
    mes          TINYINT NOT NULL,
    nombre_mes   VARCHAR(15) NOT NULL,
    dia          TINYINT NOT NULL,
    dia_semana   TINYINT NOT NULL,
    nombre_dia   VARCHAR(15) NOT NULL,
    es_fin_semana TINYINT NOT NULL,
    UNIQUE KEY uk_fecha (fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Cliente
CREATE TABLE dim_cliente (
    cliente_sk    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   VARCHAR(5) NOT NULL,      -- BK
    company_name  VARCHAR(40),
    contact_name  VARCHAR(30),
    city          VARCHAR(15),
    country       VARCHAR(15),
    UNIQUE KEY uk_customer_id (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Producto (desnormalizada: producto + categoría + proveedor)
CREATE TABLE dim_producto (
    producto_sk   INT AUTO_INCREMENT PRIMARY KEY,
    product_id    INT NOT NULL,              -- BK
    product_name  VARCHAR(40),
    category_name VARCHAR(15),
    supplier_name VARCHAR(40),
    supplier_country VARCHAR(15),
    unit_price    DECIMAL(10,2),
    discontinued  TINYINT,
    UNIQUE KEY uk_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Empleado
CREATE TABLE dim_empleado (
    empleado_sk      INT AUTO_INCREMENT PRIMARY KEY,
    employee_id      INT NOT NULL,           -- BK
    nombre_completo  VARCHAR(50),
    titulo           VARCHAR(30),
    pais             VARCHAR(15),
    fecha_contratacion DATE,
    UNIQUE KEY uk_employee_id (employee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Geografía (derivada de Ship* de Orders)
CREATE TABLE dim_geografia (
    geografia_sk  INT AUTO_INCREMENT PRIMARY KEY,
    ciudad        VARCHAR(15),
    region        VARCHAR(15),
    pais          VARCHAR(15),
    UNIQUE KEY uk_geo (ciudad, region, pais)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Transportista
CREATE TABLE dim_transportista (
    transportista_sk INT AUTO_INCREMENT PRIMARY KEY,
    shipper_id       INT NOT NULL,           -- BK
    company_name     VARCHAR(40),
    UNIQUE KEY uk_shipper_id (shipper_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dimensión Metas (calculada en transformaciones)
CREATE TABLE dim_metas (
    meta_sk        INT AUTO_INCREMENT PRIMARY KEY,
    empleado_sk    INT NOT NULL,
    anio           SMALLINT NOT NULL,
    mes            TINYINT NOT NULL,
    meta_mensual   DECIMAL(12,2),
    UNIQUE KEY uk_meta (empleado_sk, anio, mes),
    FOREIGN KEY (empleado_sk) REFERENCES dim_empleado(empleado_sk)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabla auxiliar de costos (supuesto del proyecto)
CREATE TABLE product_costos (
    product_id   INT PRIMARY KEY,
    costo_unitario DECIMAL(10,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabla intermedia para landing (paso 1 del Pipeline 2)
CREATE TABLE fact_landing (
    order_id       INT,
    product_id     INT,
    customer_id    VARCHAR(5),
    employee_id    INT,
    shipper_id     INT,
    ship_city      VARCHAR(15),
    ship_region    VARCHAR(15),
    ship_country   VARCHAR(15),
    order_date     DATE,
    shipped_date   DATE,
    cantidad       SMALLINT,
    precio_unitario DECIMAL(10,2),
    descuento      FLOAT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabla de hechos
CREATE TABLE fact_ventas (
    venta_sk         BIGINT AUTO_INCREMENT PRIMARY KEY,
    tiempo_sk        INT NOT NULL,
    cliente_sk       INT NOT NULL,
    producto_sk      INT NOT NULL,
    empleado_sk      INT NOT NULL,
    geografia_sk    INT NOT NULL,
    transportista_sk INT NOT NULL,
    order_id         INT NOT NULL,           -- dimensión degenerada
    cantidad         SMALLINT,
    precio_unitario  DECIMAL(10,2),
    descuento        FLOAT,
    venta_bruta      DECIMAL(12,2),
    venta_neta       DECIMAL(12,2),
    costo_total      DECIMAL(12,2),
    margen           DECIMAL(12,2),
    dias_entrega     INT,
    FOREIGN KEY (tiempo_sk)        REFERENCES dim_tiempo(tiempo_sk),
    FOREIGN KEY (cliente_sk)       REFERENCES dim_cliente(cliente_sk),
    FOREIGN KEY (producto_sk)      REFERENCES dim_producto(producto_sk),
    FOREIGN KEY (empleado_sk)      REFERENCES dim_empleado(empleado_sk),
    FOREIGN KEY (geografia_sk)     REFERENCES dim_geografia(geografia_sk),
    FOREIGN KEY (transportista_sk) REFERENCES dim_transportista(transportista_sk),
    INDEX idx_tiempo (tiempo_sk),
    INDEX idx_cliente (cliente_sk),
    INDEX idx_producto (producto_sk)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

5.3. Ejecuta todo. Si alguna FK falla, revisa que las dimensiones se crearon antes.
5.4. Valida:
```sql
SHOW TABLES;
```
Esperado: 10 tablas (6 dimensiones + dim_metas + product_costos + fact_landing + fact_ventas).
5.5. **CAPTURA:** `SHOW TABLES` del DW.

---

## Paso 6 — Poblar `dim_tiempo` (la única dimensión que se llena ahora)

`dim_tiempo` es completamente derivada — no viene de la fuente. Vamos a llenarla con un rango que cubre Northwind: 1994-01-01 a 1999-12-31 (5 años de margen por seguridad).

6.1. En el editor SQL del DW, ejecuta:

```sql
-- Generar dim_tiempo: 1994-01-01 a 1999-12-31
DROP PROCEDURE IF EXISTS sp_poblar_dim_tiempo;
DELIMITER //
CREATE PROCEDURE sp_poblar_dim_tiempo()
BEGIN
    DECLARE v_fecha DATE DEFAULT '1994-01-01';
    DECLARE v_fin   DATE DEFAULT '1999-12-31';

    WHILE v_fecha <= v_fin DO
        INSERT IGNORE INTO dim_tiempo (
            tiempo_sk, fecha, anio, trimestre, mes, nombre_mes,
            dia, dia_semana, nombre_dia, es_fin_semana
        ) VALUES (
            CAST(DATE_FORMAT(v_fecha, '%Y%m%d') AS UNSIGNED),
            v_fecha,
            YEAR(v_fecha),
            QUARTER(v_fecha),
            MONTH(v_fecha),
            MONTHNAME(v_fecha),
            DAY(v_fecha),
            DAYOFWEEK(v_fecha),
            DAYNAME(v_fecha),
            IF(DAYOFWEEK(v_fecha) IN (1,7), 1, 0)
        );
        SET v_fecha = DATE_ADD(v_fecha, INTERVAL 1 DAY);
    END WHILE;
END //
DELIMITER ;

CALL sp_poblar_dim_tiempo();
```

6.2. Valida:
```sql
SELECT COUNT(*) FROM dim_tiempo;          -- esperado: 2191 (6 años × 365 + 1 bisiesto)
SELECT * FROM dim_tiempo ORDER BY fecha LIMIT 5;
SELECT * FROM dim_tiempo ORDER BY fecha DESC LIMIT 5;
```
6.3. **CAPTURA:** conteo + primeras y últimas 5 filas.

---

## Paso 7 — Poblar `product_costos` (supuesto del proyecto)

Como Northwind no trae costos, definimos uno = 60% del precio de venta.

7.1. En el DW:
```sql
-- Plantilla: por ahora vacía; la carga real ocurrirá en Pipeline 2.
-- Aquí solo confirmamos que la tabla existe y describimos el cálculo.
SELECT * FROM product_costos;             -- 0 filas, correcto
```
7.2. Documenta en el Anexo D del MD principal: "costo_unitario = UnitPrice × 0.60, ajustable manualmente". (Ya está documentado.)

---

## Paso 8 — Ajustar permisos del `etl_user` en ambos MySQL

El `etl_user` debe poder hacer todo dentro de su base, pero nada fuera.

8.1. Conectado como `root` al **Staging** (3307), ejecuta:
```sql
GRANT ALL PRIVILEGES ON staging_northwind.* TO 'etl_user'@'%';
FLUSH PRIVILEGES;
```
8.2. Lo mismo en el **DW** (3306):
```sql
GRANT ALL PRIVILEGES ON dw_northwind.* TO 'etl_user'@'%';
FLUSH PRIVILEGES;
```
8.3. Valida desde otra conexión DBeaver: crea una conexión nueva con `etl_user` / `EtlUser2026!` al puerto 3307 y prueba un `SELECT` y un `INSERT INTO etl_control`. Ambos deben funcionar.
8.4. **CAPTURA:** prueba de login del `etl_user`.

---

## Checklist de cierre de la Fase 2

- [ ] `docker compose up -d` levanta 3 contenedores (SQL Server + 2 MySQL)
- [ ] DBeaver tiene 3 conexiones activas y se conecta a cada una
- [ ] Staging tiene 9 tablas (`stg_*` + `etl_control`)
- [ ] DW tiene 10 tablas (6 dim + dim_metas + product_costos + fact_landing + fact_ventas)
- [ ] `dim_tiempo` poblada con 2191 filas (1994-1999)
- [ ] `etl_user` puede leer/escribir en su base correspondiente
- [ ] Capturas en `capturas\02\` (mínimo 6)

Cuando esté listo, **"Fase 2 lista"** y pasamos a la Fase 3 (NiFi + Pipeline 1).
