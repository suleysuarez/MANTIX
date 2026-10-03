# Prompts para Google Stitch — Mantenimiento de Equipos Tecnológicos

Pega primero el **Prompt base** en Stitch (modo Web / Desktop, tablet 1280–1440 px) y después un prompt por pantalla. Adjunta tu imagen de referencia en cada generación.

## Prompt base (estilo global)

```
Diseña una aplicación web de gestión de mantenimiento de equipos tecnológicos
(laptops, servidores, impresoras, routers, cámaras) con el MISMO lenguaje visual
de la imagen de referencia adjunta:

- Marco general gris claro con un panel principal de esquinas muy redondeadas (32px).
- Sidebar vertical oscuro en azul pizarra profundo (#2B4257, versión oscura de
  #3E5C76), angosto, solo iconos, con el ícono activo resaltado en un círculo
  blanco; logo arriba y avatar de usuario abajo.
- Tarjetas blancas con esquinas redondeadas (20–24px), sombras suaves, mucho aire.
- PALETA (varía tonos y opacidades de estos colores, no uses verde):
  #ADD7F6 azul cielo claro, #A2D2FF azul brillante suave, #778DA9 azul grisáceo,
  #3E5C76 azul pizarra, #CED4DA gris claro (fondos, bordes, marco general).
  Acento cálido: MOSTAZA (#E3A72F, con variantes #F2C14E y #B8841F) para botones
  principales, KPIs destacados, barra activa de gráficos y etiquetas. Usa también
  un terracota suave (#D1603D) solo para alertas. Degradados azules suaves
  (#ADD7F6 → #A2D2FF) en los hero.
- Tipografía sans moderna (Inter / Plus Jakarta Sans), títulos grandes en
  MAYÚSCULAS en los hero, números grandes en KPIs.
- MUCHO uso de imágenes: ilustraciones/renders 3D isométricos y fotografías
  realistas de equipos (laptops, racks de servidores, técnicos trabajando,
  placas base, centros de datos) dentro de hero banners, tarjetas y listas.
  Nada de pantallas genéricas solo con tablas y texto.
- Chips de estado con la paleta: Operativo (azul cielo #A2D2FF con texto
  #3E5C76), En mantenimiento (mostaza), Fuera de servicio (terracota),
  Programado (azul grisáceo #778DA9).
- Gráficos: barras verticales con tooltip, barras apiladas azul pizarra/mostaza/gris,
  mini sparklines dentro de tarjetas.
- Buscador redondeado y campana de notificaciones arriba a la derecha.
- Idioma: español.
```

## 1. Login / Registro

```
Pantalla dividida en dos: a la izquierda tarjeta blanca con formulario (logo,
"Bienvenido de nuevo", correo, contraseña, botón negro con texto blanco,
enlace "Crear cuenta", botón de Google). A la derecha una gran imagen 3D
isométrica de una sala de servidores flotando sobre una isla azul-grisácea, con
degradado azul claro (#ADD7F6 → #A2D2FF) y 3 tarjetas flotantes de vidrio: "128 equipos",
"96 % operativos", "14 mantenimientos hoy". Misma pantalla variante "Crear cuenta".
```

## 2. Cuenta pendiente de aprobación

```
Pantalla centrada con ilustración 3D de un técnico con casco y un reloj de
arena junto a una laptop. Título "Tu cuenta está en revisión", texto breve,
línea de tiempo de 3 pasos (Registro ✓, Revisión del administrador ●,
Acceso concedido ○) y botón secundario "Cerrar sesión".
```

## 3. Dashboard

```
Dashboard idéntico en estructura a la referencia. Hero con degradado azul
claro: título "SISTEMA INTELIGENTE DE MANTENIMIENTO", subtítulo, dos tarjetas
de vidrio (Mantenimientos activos, Pendientes) con barra de progreso y
sparkline, y a la derecha una gran isla 3D con un centro de datos, torres de
servidores y vegetación; abajo a la derecha un cuadro con "Equipos operativos 94 %"
y "Salud del sistema 98 %". Fila de 3 KPIs con icono (Equipos totales,
Mantenimientos del mes, Técnicos activos). Debajo: tarjeta grande "Mantenimientos
por semana" (barras verticales Lu–Do con tooltip), tarjeta "Salud de equipos"
con una imagen 3D de una ciudad/isla con etiquetas flotantes (Laptops, Servidores,
Redes) y tarjeta "Eficiencia por técnico" con barras apiladas.
```

## 4. Listado de equipos

```
Encabezado hero más bajo con foto de un rack de servidores y título "INVENTARIO
DE EQUIPOS". Barra de herramientas: buscador, filtros (tipo, estado, ubicación),
botón mostaza "+ Nuevo equipo" y toggle vista Tarjetas / Tabla. Vista por
defecto en TARJETAS con foto del equipo (laptop, impresora, switch…), nombre,
código de serie, chip de estado, ubicación, fecha del último mantenimiento y
botón de acciones. Paginación inferior redondeada.
```

## 5. Formulario de equipo (crear / editar)

```
Layout de dos columnas dentro de tarjetas blancas. Izquierda: zona grande de
carga de foto con vista previa del equipo y miniaturas. Derecha: campos
(nombre, tipo, marca, modelo, serie, ubicación, fecha de compra, estado,
notas). Barra inferior fija con "Cancelar" y "Guardar equipo" (mostaza).
```

## 6. Lista de mantenimientos

```
Hero con foto de un técnico reparando una placa base y contadores
(Programados, En curso, Completados). Pestañas por estado y una vista tipo
tablero/línea de tiempo: cada mantenimiento es una tarjeta con miniatura del
equipo, tipo (preventivo/correctivo), técnico con avatar, fecha, prioridad y
barra de progreso. Botón "+ Programar mantenimiento".
```

## 7. Detalle de mantenimiento

```
Cabecera con foto grande del equipo y chips de estado/prioridad. Columna
izquierda: línea de tiempo vertical de actividades con fotos de evidencia
(antes/después) en galería. Columna derecha: tarjeta del técnico asignado con
avatar, tarjeta de datos del equipo con su render 3D, repuestos usados y
botones "Marcar completado" (mostaza) y "Reprogramar".
```

## 8. Técnicos

```
Cuadrícula de tarjetas con foto/retrato del técnico, nombre, especialidad,
carga de trabajo (anillo de progreso), mantenimientos completados y chip de
disponibilidad. Hero con foto de equipo de técnicos en un data center.
```

## 9. Administración — usuarios pendientes

```
Lista de tarjetas con avatar, nombre, correo, fecha de solicitud y botones
"Aprobar" (mostaza) / "Rechazar" (contorno). Ilustración 3D de llave de
acceso en el encabezado y contador "5 solicitudes pendientes".
```

## 10. Notificaciones (campana + bandeja)

```
Popover desde la campana con lista de notificaciones con miniatura del equipo,
icono de tipo, texto, tiempo relativo y punto mostaza para no leídas; botón
"Marcar todas como leídas". Además, vista completa de bandeja con filtros
(Todas, No leídas, Mantenimientos, Sistema) y un estado vacío con ilustración 3D.
```

## Después de Stitch

Exporta el HTML/CSS (o capturas) de cada pantalla y pásalos a `docs/stitch/` — las convierto en componentes Angular reutilizando los stores y servicios existentes (`equipment.store`, `maintenance.store`, `notifications.store`, etc.).
