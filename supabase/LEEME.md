# Conectar el CRM a Supabase

Esta guía es para quien administra el CRM, no requiere saber programar.
Al terminar, las capturas de Banco y Comercio se guardarán en una base de
datos real (Supabase) en vez de solo en el navegador de cada persona, y
tú (el administrador) podrás entrar con correo y contraseña para
gestionar asesores y registros.

Si NO sigues esta guía, el CRM sigue funcionando exactamente igual que
antes (todo se guarda en el navegador de cada quien, sin este paso).

## 1. Crear el proyecto en Supabase

1. Entra a [supabase.com](https://supabase.com) y crea una cuenta (o inicia
   sesión) con tu correo.
2. Da clic en **New project**.
3. Ponle un nombre (por ejemplo `crm-san-miguel-de-allende`), elige una
   contraseña para la base de datos (guárdala en un lugar seguro, no la
   necesitarás para el CRM pero sí si algún día quieres conectarte
   directamente a la base de datos) y elige la región más cercana.
4. Espera unos minutos a que el proyecto termine de crearse.

## 2. Ejecutar el esquema (las tablas)

1. En el menú lateral izquierdo del proyecto, entra a **SQL Editor**.
2. Da clic en **New query**.
3. Abre el archivo [`migrations/0001_init.sql`](./migrations/0001_init.sql)
   de esta carpeta, copia **todo** su contenido, y pégalo en el editor.
4. Da clic en **Run** (o Ctrl/Cmd+Enter).
5. Debe decir "Success. No rows returned". Esto crea las tablas
   `asesores`, `capturas` y `admin_users`, además de las reglas de
   seguridad y las funciones que usa el CRM.

Si en el futuro necesitas cambiar algo del esquema, crea un archivo nuevo
en esta carpeta (por ejemplo `0002_algo.sql`) en vez de editar
`0001_init.sql`, así queda un historial de los cambios.

## 3. Crear tu usuario de administrador

1. En el menú lateral, entra a **Authentication > Users**.
2. Da clic en **Add user > Create new user**.
3. Captura tu correo y una contraseña. Marca la casilla para que el
   correo quede confirmado automáticamente (**Auto Confirm User**), así
   no dependes de que llegue un correo de confirmación.
4. Da clic en **Create user**. Copia el **User UID** que aparece en la
   lista (es un identificador largo, algo como
   `3fa1c2e4-9c11-4d2a-8b7e-...`).
5. Regresa a **SQL Editor > New query** y pega esto, reemplazando los dos
   valores marcados:

   ```sql
   insert into public.admin_users (user_id, email)
   values ('PEGA-AQUI-EL-USER-UID', 'tu-correo@ejemplo.com');
   ```

6. Da clic en **Run**. A partir de aquí, ese correo y esa contraseña son
   los que usarás para entrar a Administración en el CRM.

### Desactivar el registro público (importante)

Por defecto, Supabase permite que cualquiera cree una cuenta nueva. Como
el CRM solo debe tener un administrador (o los que tú decidas agregar a
mano con el paso anterior), desactiva el registro público:

1. Ve a **Authentication > Providers > Email**.
2. Desactiva la opción **Allow new users to sign up**.
3. Guarda los cambios.

Esto no afecta el login del administrador (esa cuenta ya existe); solo
evita que alguien más pueda crear una cuenta nueva desde fuera.

Para agregar un segundo administrador más adelante, repite el paso 3
completo (crear el usuario en Authentication > Users y luego insertar su
`user_id` en `admin_users`).

## 4. Obtener la URL y la clave pública ("anon key")

1. Ve a **Project Settings > API** (ícono de engrane, abajo a la
   izquierda).
2. Copia el valor de **Project URL**.
3. Copia el valor de **anon public** (dentro de "Project API keys").

Estos dos valores son públicos por diseño (la seguridad real la dan las
reglas de RLS que ya quedaron creadas en el paso 2), pero **nunca copies
la "service_role" key** — esa sí es secreta y no debe usarse en el CRM.

## 5. Configurar el CRM

1. En la carpeta del CRM (junto a `index.html`), copia el archivo
   `config.example.js` y renómbralo a `config.js`.
2. Ábrelo y reemplaza los dos valores vacíos con lo que copiaste en el
   paso 4:

   ```js
   window.SUPABASE_CONFIG = {
     url: "https://tu-proyecto.supabase.co",
     anonKey: "tu-anon-key-aquí"
   };
   ```

3. Guarda el archivo y súbelo junto con `index.html` a donde publiques el
   CRM (mismo servidor, misma carpeta).

Listo. La próxima vez que se abra el CRM, verás un mensaje breve de
carga y luego el CRM funcionará igual que antes, pero cada captura de
Banco o Comercio se guardará en Supabase, visible desde cualquier
dispositivo. Para entrar a Administración se pedirá el correo y
contraseña que creaste en el paso 3.

## 6. Importar el catálogo de asesores

El catálogo de 101 asesores que ya está en `index.html` (la lista
`seedAdvisors`) **no se copia automáticamente a Supabase** — sirve solo
para el modo local (sin `config.js`). Una vez conectado a Supabase, la
tabla `asesores` empieza vacía.

Para llenarla, entra a Administración (con tu usuario de administrador),
pestaña **Asesores**, y usa la sección **Importar asesores desde CSV**
para subir el mismo archivo `asesores_final_101.csv` que se usó para
construir el catálogo (debe tener columnas `emp`, `name`, `branch` y
`puesto`). También puedes dar de alta asesores uno por uno con el botón
**+ Nuevo asesor**.

## Cómo probar que quedó bien

1. Abre el CRM. Debe cargar sin errores y, al entrar a Administración,
   debe pedir correo y contraseña.
2. Inicia sesión con el usuario que creaste en el paso 3.
3. Importa el catálogo de asesores (paso 6) o da de alta uno manualmente.
4. Ve a **Registrar avance**, elige una sucursal y un asesor, y guarda
   una captura de prueba. Debe aparecer un folio y, si regresas a
   Administración > Registros, el registro debe estar ahí.
5. Abre el CRM desde otro navegador o dispositivo (sin haber iniciado
   sesión como administrador): el Resumen ejecutivo y el catálogo de
   asesores deben verse igual, incluyendo la captura de prueba, sin
   pedir ningún login.

## Notas técnicas (para quien dé mantenimiento al código)

- Si `config.js` no existe, o existe pero `url`/`anonKey` están vacíos,
  el CRM ignora Supabase por completo y usa exactamente el mismo
  almacenamiento local (localStorage) que usaba antes de este cambio.
- Todas las escrituras de capturas (`crear_captura`, `actualizar_captura`)
  y toda la lectura pública (`asesores_publico`, `capturas_resumen`) pasan
  por funciones `SECURITY DEFINER` con `search_path` fijo, no por acceso
  directo a las tablas desde el navegador. Esto evita que alguien con la
  anon key pueda mandar folios, semanas o totales inventados.
- Las altas/ediciones de asesores sí usan acceso directo a la tabla
  `asesores` desde el navegador (`insert`/`update`), protegidas por las
  políticas de RLS que exigen `is_admin()` — es decir, requieren que el
  navegador tenga una sesión de administrador activa (haber iniciado
  sesión). Sin sesión de administrador, esas políticas rechazan la
  operación aunque alguien tenga la anon key.
- La generación del número de folio (`BAN-DDMMYY-NNNN` /
  `COM-DDMMYY-NNNN`) usa un conteo simple dentro de la función; en el caso
  muy improbable de que dos capturas se guarden en el mismo instante
  exacto, podría repetirse un folio. Para el volumen de esta región no
  debería ser un problema práctico, pero si en el futuro se vuelve
  relevante, se puede cambiar a una secuencia de PostgreSQL.
