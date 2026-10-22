/* SESION 04 REGEX
 **********************************************************************************************
  LABORATORIO DE EXPRESIONES REGULARES EN SQL SERVER 2025 / AZURE SQL
  Contexto: notas de CRM, tickets de soporte y albaranes con datos españoles embebidos
            en texto libre (DNI, NIE, CIF, teléfonos, IBAN, matrículas, CP, importes...).

  REQUISITOS
  ----------
  * SQL Server 2025 o Azure SQL Database / Azure SQL Managed Instance.
  * REGEXP_LIKE, REGEXP_MATCHES y REGEXP_SPLIT_TO_TABLE exigen nivel de
    compatibilidad 170 o superior. El resto (REGEXP_COUNT, REGEXP_INSTR,
    REGEXP_REPLACE, REGEXP_SUBSTR) funciona en cualquier nivel.
  * El motor sigue el estándar POSIX y admite la mayor parte de la sintaxis PCRE2.

  FLAGS DISPONIBLES (parámetro "flags" de todas las funciones)
  -----------------------------------------------------------
    'c'  distingue mayúsculas/minúsculas  (valor por defecto)
    'i'  NO distingue mayúsculas/minúsculas
    'm'  modo multilínea: ^ y $ casan en cada salto de línea
    's'  el punto (.) también casa con el salto de línea

  FIRMAS (orden exacto de los parámetros: ¡es fácil equivocarse!)
  --------------------------------------------------------------
    REGEXP_LIKE            (cadena, patron [, flags])                                        -> bit 1/0
    REGEXP_COUNT           (cadena, patron [, inicio [, flags]])                             -> int
    REGEXP_INSTR           (cadena, patron [, inicio [, ocurrencia [, opcion_retorno [, flags [, grupo]]]]]) -> int
    REGEXP_REPLACE         (cadena, patron [, reemplazo [, inicio [, ocurrencia [, flags]]]]) -> cadena
    REGEXP_SUBSTR          (cadena, patron [, inicio [, ocurrencia [, flags [, grupo]]]])     -> cadena
    REGEXP_MATCHES         (cadena, patron [, flags])   -> TABLA (match_id, start_position,
                                                                  end_position, match_value,
                                                                  substring_matches JSON)
    REGEXP_SPLIT_TO_TABLE  (cadena, patron [, flags])   -> TABLA (ordinal, value)

  EN EL REEMPLAZO DE REGEXP_REPLACE
  ---------------------------------
    \1 .. \9  -> contenido del grupo de captura n
    &         -> coincidencia completa
    (OJO: se usa \1, no $1)
**********************************************************************************************/


-- LEN Y DATALENGHT
select
    len(t.x),
    datalength(t.y)
from
    ( values 
        ('FAC-2026-000123', 'patata   '), 
        ('regla', 'regla'), 
        ('ana.lopez@cliente.es','casa') ) as t(x, y);

-- LEFT, RIGHT Y SUBSTRING
select
    t.cod,
    left(t.cod, 3) c ,
    substring(t.cod, 5, 4) o,
    right(t.cod, 6) d
from
    ( values 
        ('FAC-2026-000123') ) as t(cod);


-- CHARINDEX Y PATINDEX
select
    t.cod,
    charindex('-', t.cod, 1) primera,
    charindex('-', t.cod, charindex('-', t.cod, 1) + 1) segunda,
    left(t.cod, charindex('-', t.cod, 1) - 1) c,
    substring(
        t.cod, 
        charindex('-', t.cod, 1) + 1,
        charindex('-', t.cod, charindex('-', t.cod, 1) + 1) - charindex('-', t.cod, 1) -1) o,
    right(t.cod, len(t.cod) - charindex('-', t.cod, charindex('-', t.cod, 1) + 1)) d
from
    ( values 
        ('FAC-2026-000123') ) as t(cod);

select
    t.cod,
    patindex('%6-%', t.cod) patron
from
    ( values 
        ('FAC-2026-000123') ) as t(cod);


-- REPLACE, STUFF, TRANSLATE, REPLICATE, REVERSE
select
    t.cod,
--    replace(t.cod, 'casa','@'),
--    stuff(t.cod, 5, 4, 'pera'),
--    translate(t.cod, 'cosa', 'pera'),
    right(replicate(0, 20) + 'patata', 20 ) padding
--    reverse(t.cod)
from
    ( values 
        ('casacosa') ) as t(cod);


-- TRIM, LTRIM, RTRIM, UPPER, LOWER
select
    len(t.cod),
    datalength(t.cod),
    len(trim(t.cod)),
    len(ltrim(t.cod)),
    len(rtrim(t.cod))
from
    ( values 
        ('     casacosa       ') ) as t(cod);

-- +, CONCAT, CONCAT_WS, ||
select
    t.cod + t.vacio,
    concat(t.cod, t.vacio) ,
    concat_ws('-', t.cod, t.vacio)
from
    ( values 
        ('casa', 'cosa') ) as t(cod, vacio);

-- STRING_AGG y STRING_SPLIT

select
    string_agg(value, '-')
from
    string_split('Lorem ipsum dolor sit amet.', ' ');

select
    string_agg(concat(t.cod, '=', t.texto), '  ') within group (
    order by t.cod) as entidades
from
    ( values 
        ('uno', 'patata'),
        ('dos', 'pera'),
        ('dos', 'casa')) as t(cod, texto);

with a as 
    (
    select
        distinct Producto as Region
    from
        dbo.Ventas v
    ), 
    b as 
    (
    select
        string_agg(Region, '@') within group(order by Region) as agregada
    from
        a
    )
select * from string_split('casa@perab', '@');


/*==============================================================================================
  0. PREPARACIÓN
==============================================================================================*/

-- 0.1 Comprobar versión y nivel de compatibilidad

select
    @@VERSION as version_motor,
    SERVERPROPERTY('ProductMajorVersio')   as version_mayor, -- 17 = SQL Server 2025
    SERVERPROPERTY('Editio')               as edicion,
    (
        select
            compatibility_level
        from
            sys.databases
        where
            name = DB_NAME()
    ) AS nivel_compatibilidad;

-- 0.2 Si el nivel es inferior a 170, súbelo (necesario para LIKE/MATCHES/SPLIT_TO_TABLE)
--     Descomenta y ajusta el nombre de la base de datos:
-- ALTER DATABASE [MiBaseDeDatos] SET COMPATIBILITY_LEVEL = 170;


-- 0.3 Tabla de trabajo
drop table if exists dbo.Frases;


create table dbo.Frases
    (
    id int not null primary key,
    canal nvarchar(20) not null, -- crm, ticket, albarán, email, llamada, chat
    asunto  nvarchar(60)  not null,
    texto   nvarchar(500) not null
    );

-- 0.4 Carga de datos (las mismas 40 frases que el fichero frases_regex.csv)
INSERT INTO dbo.Frases (id, canal, asunto, texto) VALUES
    (1, 'CRM', 'Alta de cliente', 'Alta de cliente: María López Ruiz, DNI 12345678Z, móvil 612 345 678, email maria.lopez@ejemplo.es, dirección Calle Alcalá 145, 28009 Madrid.'),
    (2, 'Ticket', 'Reclamación de factura', 'El cliente con NIE X1234567L reclama la factura FRA-2026-00871 de 1.234,56 € emitida el 03/02/2026. Teléfono de contacto +34 911 223 344.'),
    (3, 'Albará', 'Entrega completada', 'Albarán ALB/2026/0451 entregado el 12/03/2026 en Calle Mayor 45 3ºB, 46001 Valencia. Vehículo con matrícula 1234 BCD.'),
    (4, 'Email', 'Cambio de domiciliació', 'Ruego actualicen mi IBAN a ES91 2100 0418 4502 0005 1332. Titular: Juan Pérez Gómez, DNI 87654321X, teléfono 655112233.'),
    (5, 'Llamada', 'Segunda reclamació', 'Llamada de 34 minutos. Facilita dos teléfonos: 656-11-22-33 y 0034 934 567 890. No podemos verificar el DNI 11223344 porque falta la letra.'),
    (6, 'Chat', 'Error en el portal', 'Error 500 al abrir https://portal.belerofontech.com/facturas?id=8842 a las 09:15 del 04/08/2026 con Chrome 138.0.'),
    (7, 'CRM', 'Visita comercial', 'Visita a INDUSTRIAS BELEROFON SL, CIF B12345674, Polígono Norte nave 7, 50014 Zaragoza. Interlocutor Ana Gil (ana.gil@belerofon.es, ext 4021).'),
    (8, 'Ticket', 'Alta duplicada', 'Se han creado dos fichas para el mismo DNI: 45678901H y 45678901H. Revisar antes del 15/09/2026.'),
    (9, 'Albará', 'Incidencia en transporte', 'Bultos 3 de 4 recibidos. Matrículas implicadas: 4521 KLM y M-4521-BC. Peso total 128,50 kg. Contacto almacén 928 334 455.'),
    (10, 'Email', 'Presupuesto solicitado', 'Solicito presupuesto para 250 unidades. Nuestro CIF es A58818501 y el pedido anterior fue PED-2025-1187 por 18.900,00 €.'),
    (11, 'Llamada', 'Consulta de saldo', 'El titular Carlos Martín (DNI 33445566P) pregunta por el recibo de 89,99 € del 28/07/2026. Le devolvemos la llamada al 673 998 877.'),
    (12, 'Chat', 'Cambio de direcció', 'Nueva dirección: Avenida Diagonal 682 esc 2 piso 4, 08034 Barcelona. Antes vivía en 08015. Móvil de contacto 600 000 111.'),
    (13, 'CRM', 'Cliente potencial', 'Contacto en feria: Laura Sanz, laura.sanz+ferias@empresa.com, tel 971 223 344, móvil 611223344. Interesada en el plan PRO por 149,00 € al mes.'),
    (14, 'Ticket', 'Impago detectado', 'Impago del recibo REC-2026-00042 por 2.450,75 €. Cliente CIF B87654321. Teléfonos registrados: 913334455, 622334455 y 622334455.'),
    (15, 'Albará', 'Devolució', 'Devolución del albarán ALB/2026/0198 recogida el 01/08/2026 en 41013 Sevilla. Transportista matrícula 7788 XYZ. Motivo: producto dañado.'),
    (16, 'Email', 'Reclamación urgente', 'URGENTE: llevo TRES semanas esperando. Mi DNI es 09876543M y mi teléfono el 638 121 212. Adjunto la factura FRA-2026-00123 de 76,20 €.'),
    (17, 'Llamada', 'Verificación de identidad', 'Verificados DNI 55667788D y fecha de nacimiento 14/05/1979. El cliente aporta también el NIE de su cónyuge Y7654321F.'),
    (18, 'Chat', 'Etiquetas de la conversació', 'Etiquetas: urgente|facturación|impago|segunda-llamada|escalado-nivel-2'),
    (19, 'CRM', 'Notas de seguimiento', 'Seguimiento pendiente. Enviar email a soporte@belerofontech.com y copia a benito.cuezva@belerofontech.com antes del 2026-08-10.'),
    (20, 'Ticket', 'Datos incompletos', 'Ficha  incompleta: falta CP,  el teléfono 12345 no es válido y el email cliente@@correo es incorrecto.  DNI 22334455K correcto.'),
    (21, 'Albará', 'Recogida programada', 'Recogida programada para el 20/08/2026 entre las 10:00 y las 13:30 en 15703 Santiago de Compostela. Referencia ALB/2026/0512.'),
    (22, 'Email', 'Alta de proveedor', 'Alta de proveedor SUMINISTROS GADES SA, CIF A11111111, IBAN ES6621000418401234567891, contacto 956 112 233 (fijo) y 699 112 233 (móvil).'),
    (23, 'Llamada', 'Baja del servicio', 'Solicita baja el 31/12/2026. Titular con NIE Z0123456T. Pide confirmación al móvil 644 555 666 y al fijo 985 667 788.'),
    (24, 'Chat', 'Consulta de envío', 'Mi pedido PED-2026-0777 sale desde 03203 Elche. ¿Puedo cambiar la dirección a Calle Colón 12, 03001 Alicante?'),
    (25, 'CRM', 'Oportunidad cerrada', 'Cerrada oportunidad OPP-2026-0033 por 32.500,00 €. Firma prevista el 09/09/2026. Contacto: Pedro Ruiz, DNI 66778899E, tel +34 622 111 000.'),
    (26, 'Ticket', 'Acceso bloqueado', 'Usuario bloqueado tras 5 intentos a las 08:47. IP 192.168.10.45. Email de la cuenta: p.ruiz@cliente-ejemplo.org. Teléfono 917 000 111.'),
    (27, 'Albará', 'Entrega parcial', 'Entrega parcial: 12 de 30 cajas. Matrícula 0001 AAA. Pendiente el resto para el 07/08/2026. Almacén 08820, contacto 936 001 002.'),
    (28, 'Email', 'Duplicidad de cargos', 'Se han cargado dos veces 45,00 € el 30/06/2026 y el 30/06/2026. IBAN afectado ES79 0182 1234 5612 3456 7890. DNI 77889900B.'),
    (29, 'Llamada', 'Actualización de datos', 'Actualizados teléfono (de 913 111 222 a 913 111 333) y email (de old@ejemplo.es a new@ejemplo.es). DNI 10203040J sin cambios.'),
    (30, 'Chat', 'Texto con ruido', 'hola     necesito     AYUDA con mi   pedido    PED-2026-0421   gracias!!!'),
    (31, 'CRM', 'Contacto internacional', 'Contacto en Lisboa: +351 912 345 678. La filial española usa +34 963 112 233. El NIF portugués queda fuera de alcance.'),
    (32, 'Ticket', 'Datos sensibles en texto libre', 'El agente pegó datos sensibles: DNI 12312312L, IBAN ES1400491234561234567890 y tarjeta 4111 1111 1111 1111. Hay que anonimizar.'),
    (33, 'Albará', 'Ruta de reparto', 'Ruta 12: 28001, 28002, 28003 y 28900. Matrículas asignadas 3456 GHJ, 3457 GHK. Salida 06:30, regreso 14:45.'),
    (34, 'Email', 'Confirmación de cita', 'Cita confirmada el 18/08/2026 a las 11:00 en nuestra sede de 48009 Bilbao. Preguntar por Marta Ibáñez (m.ibanez@belerofontech.com).'),
    (35, 'Llamada', 'Queja por atenció', 'El cliente 99887766C indica que llamó al 902 100 200 tres veces y al 900 100 200 dos veces sin respuesta.'),
    (36, 'Chat', 'Lista separada por comas', 'Productos solicitados: SKU-001,SKU-002,SKU-0033,SKU-4,SKU-00055'),
    (37, 'CRM', 'Fusión de fichas', 'Fusionar fichas 45678901H y X1234567L. Conservar el teléfono 612345678 y descartar el 612 345 679.'),
    (38, 'Ticket', 'Formatos de fecha mezclados', 'Fechas encontradas: 01/02/2026, 2026-02-01, 1-2-26 y 01.02.2026. Normalizar todas a ISO.'),
    (39, 'Albará', 'Pesos y medidas', 'Bulto 1: 12,5 kg y 40x30x20 cm. Bulto 2: 7,25 kg y 60x40x30 cm. Total 19,75 kg. Portes 12,10 €.'),
    (40, 'Email', 'Firma con varios contactos', 'Un saludo. Tel 934 000 111 | Móvil 677 000 111 | Fax 934 000 112 | www.belerofontech.com | CIF B99999999');GO

    
select
    texto
from
    dbo.Frases;


select * from Patrones p ;

-- 0.5 Catálogo de patrones reutilizables (cópialos y pégalos en tus propias consultas)
drop table if exists dbo.Patrones;

create table dbo.Patrones
    (
    clave varchar(20) not null primary key,
    descripcion nvarchar(120) not null,
    patron nvarchar(300) not null
    );

insert into dbo.Patrones (clave, descripcion, patron) values
    ('DNI',      'DNI español: 8 dígitos + letra de control',                  '\b[0-9]{8}[A-Za-z]\b'),
    ('NIE',      'NIE: X/Y/Z + 7 dígitos + letra',                             '\b[XYZ][0-9]{7}[A-Za-z]\b'),
    ('DOC',      'DNI o NIE en un solo patró',                                '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b'),
    ('CIF',      'CIF/NIF de entidad: letra + 7 dígitos + dígito o letra',     '\b[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]\b'),
    ('TELEFONO', 'Teléfono español (9 dígitos, separadores libres, prefijo opcional)', '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b'),
    ('MOVIL',    'Solo móviles (empiezan por 6 o 7)',                          '\b[67](?:[ .-]?[0-9]){8}\b'),
    ('TEL_GRUPOS', 'Teléfono 3-3-3 con grupos de captura para reformatear',     '\b([6-9][0-9]{2})[ .-]?([0-9]{3})[ .-]?([0-9]{3})\b'),
    ('IBA',     'IBAN español, con o sin espacios',                           '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b'),
    ('MATRICULA','Matrícula actual: 4 dígitos + 3 consonantes válidas',         '\b[0-9]{4}[ -]?[BCDFGHJKLMNPRSTVWXYZ]{3}\b'),
    ('MAT_ANT',  'Matrícula antigua: 1-2 letras + 4 dígitos + 2 letras',        '\b[A-Z]{1,2}-?[0-9]{4}-?[A-Z]{2}\b'),
    ('CP',       'Código postal español (provincias 01-52)',                    '\b(?:0[1-9]|[1-4][0-9]|5[0-2])[0-9]{3}\b'),
    ('EMAIL',    'Dirección de correo electrónico',                             '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    ('FECHA_ES', 'Fecha dd/mm/aaaa con grupos de captura',                      '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b'),
    ('HORA',     'Hora hh:mm en formato 24 h',                                  '\b(?:[01][0-9]|2[0-3]):[0-5][0-9]\b'),
    ('IMPORTE',  'Importe en euros con formato español (1.234,56 €)',           '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€'),
    ('REFERENCIA', 'Referencia documental tipo ALB/2026/0451 o FRA-2026-00871', '\b[A-Z]{3}[-/][0-9]{4}[-/][0-9]{3,5}\b'),
    ('MAYUSCULAS', 'Palabras de 3+ letras en mayúsculas',                       '\b[A-Z]{3,}\b'),
    ('ESP_MULT', 'Dos o más espacios consecutivos',                            ' {2,}'),
    ('TARJETA',  'Número de tarjeta de 16 dígitos en 4 bloques',               '\b(?:[0-9]{4}[ -]?){3}[0-9]{4}\b'),
    ('URL',      'URL http/https',                                             'https?://[^\s]+');


-- 0.6 Vista de control: qué contiene cada frase
select
    id,
    canal,
    asunto,
    LEN(texto) as longitud,
    texto
from
    dbo.Frases
order by
    id;


select
    *
from
    dbo.Patrones p ;


select * from regexp_matches('0123456789', '\d');

select
    *
from
    REGEXP_SPLIT_TO_TABLE ('the quick brown fox jumps over the lazy  dog', '\s{2}');

select
    x,
    y,
    regexp_count(x, '\d{3}') as contar,     -- cuantos bloques aparecen
    regexp_instr(x, '\d{2}', 1, 1 , 1) as encontrar,
    regexp_substr(x, '\d{4}', 1) as substring,        
    regexp_replace(x, '\d{4}', 'casa') as sustituir,        
    regexp_matches(x, ) as 
from
    (
values 
        ('FAC-2026-000123', 'patata   '), 
        ('regla', 'regla'), 
        ('ana.lopez@cliente.es', 'casa') ) as t(x, y);
where 
    regexp_like(x, '\d');
/*==============================================================================================
  1. REGEXP_LIKE  -  ¿casa o no casa?  Ideal para filtrar y validar.

     REGEXP_LIKE (cadena, patron [, flags])  ->  booleano

     Devuelve un BOOLEANO, no un 1/0 almacenable: úsalo en WHERE, HAVING, CASE WHEN,
     IIF o en una restricción CHECK. Si necesitas una columna 0/1, envuélvelo en CASE.
==============================================================================================*/

-- 1.1 Frases que contienen un DNI español bien formado
--     (fíjate en la 5: el DNI le falta la letra, así que NO aparece)
select
    id,
    canal,
    texto
from
    dbo.Frases
where
    regexp_like(texto, '\b[0-9]{8}[A-Za-z]\b')
order by
    id;

-- 1.2 Clasificar cada frase según los datos personales que contiene (CASE WHEN)
select
    id,
    canal,
    case when regexp_like(texto, '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b') then 1 else 0 end as tiene_dni_nie,
    case when regexp_like(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b') then 1 else 0 end as tiene_telefono,
    case when regexp_like(texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b') then 1 else 0 end as tiene_iban,
    case when regexp_like(texto, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') then 1 else 0 end as tiene_email,
    texto
from
    dbo.Frases
order by
    id;

-- 1.3 El flag 'i': buscar "urgente" sin distinguir mayúsculas de minúsculas
--     Compara los dos resultados: con 'c' (por defecto) sólo sale la frase 18,
--     con 'i' sale también la 16 (escrita "URGENTE").
select 
    id, 
    'sensible (c)' as modo, 
    texto
from
    dbo.Frases
where
    regexp_like(texto, 'urgente')
union all
select
    id,
    'insensible (i)',
    texto
from
    dbo.Frases
where
    regexp_like(texto, 'urgente', 'i')
order by
    modo,
    id;


-- 1.4 Control de calidad: frases con una matrícula MAL formada
--     Una matrícula española actual no admite vocales ni las letras Ñ/Q en el bloque final,
--     así que "0001 AAA" (frase 27) es inválida aunque tenga la forma 4 dígitos + 3 letras.
select
    id,
    texto
from
    dbo.Frases
where
    regexp_like(texto, '\b[0-9]{4}[ -]?[A-Z]{3}\b')
    and not -- parece matrícula 
    regexp_like(texto, '\b[0-9]{4}[ -]?[BCDFGHJKLMNPRSTVWXYZ]{3}\b')   -- pero no es válida
order  by 
    id;



-- 1.5 Validación en la propia tabla: restricción CHECK con REGEXP_LIKE
--     Este es el gran caso de uso "de producción": validar el dato en la entrada.
drop table if exists dbo.Clientes;


create table dbo.Clientes
(
    cliente_id int identity primary key,
    nombre nvarchar(80) not null,
    documento nvarchar(12) not null
        constraint CK_Clientes_documento check (regexp_like(documento, '^(?:[XYZ][0-9]{7}|[0-9]{8})[A-Z]$')),
    telefono nvarchar(20) null
        constraint CK_Clientes_telefono check (regexp_like(telefono, '^(?:\+34)?[6-9][0-9]{8}$')),
    email nvarchar(120) null
        constraint CK_Clientes_email check (regexp_like(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),
    cp nchar(5) null
        constraint CK_Clientes_cp check (regexp_like(cp, '^(?:0[1-9]|[1-4][0-9]|5[0-2])[0-9]{3}$'))
);


-- Estas filas se insertan sin problema:
insert into dbo.Clientes (nombre, documento, telefono, email, cp) values 
    ( 'María López Ruiz', '12345678Z', '612345678', 'maria.lopez@ejemplo.es', '28009'),
    ( 'Cliente con NIE', 'X1234567L', '+34911223344', 'nie@ejemplo.es', '08034' );


-- Y estas fallan a propósito (ejecútalas una a una para ver el error de cada CHECK):
-- insert into dbo.Clientes (nombre, documento) values ('Sin letra', '11223344');    -- documento inválido
-- insert into dbo.Clientes (nombre, documento, telefono) values ('Tel corto', '22334455K', '12345'); -- teléfono inválido
-- insert into dbo.Clientes (nombre, documento, email) values ('Mail malo', '22334455K', 'cliente@@correo');-- email inválido
-- insert into dbo.Clientes (nombre, documento, cp) values ('CP malo', '22334455K', '99999'); -- CP inexistente
select * from clientes;

/*==============================================================================================
  2. REGEXP_COUNT  -  cuántas veces aparece el patrón. Perfecto para métricas de calidad.

     REGEXP_COUNT (cadena, patron [, inicio [, flags]])  ->  int
==============================================================================================*/

-- 2.1 ¿Cuántos teléfonos hay en cada nota? (la 14 y la 40 tienen tres)
select
    id,
    canal,
    regexp_count(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b') as n_telefonos,
    texto
from
    dbo.Frases
where
    regexp_count(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b') > 0
order by
    n_telefonos desc,
    id;

-- 2.2 Detectar fichas duplicadas: el mismo documento repetido dentro de una frase
select
    id,
    regexp_count(texto, '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b') as n_documentos,
    texto
from
    dbo.Frases
where
    regexp_count(texto, '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b') >= 2
order by
    id;


-- 2.3 Índice de "GRITO": proporción de palabras en mayúsculas (tono del cliente)
select
    id,
    canal,
    regexp_count(texto, '\b[A-Z]{3,}\b') as palabras_mayusculas,
    regexp_count(texto, '\b[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{3,}\b') as palabras_totales,
    cast(100.0 * regexp_count(texto, '\b[A-Z]{3,}\b')
              / nullif(regexp_count(texto, '\b[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{3,}\b'), 0) as DECIMAL(5, 1)) as pct_mayusculas,
    texto
from
    dbo.Frases
order by
    pct_mayusculas desc;

-- 2.4 Calidad del texto: espacios dobles, signos repetidos y cifras sueltas
select
    id,
    regexp_count(texto, ' {2,}') as bloques_espacios_multiples,
    regexp_count(texto, '[!?]{2,}') as signos_repetidos,
    regexp_count(texto, '[0-9]+') as grupos_numericos,
    texto
from
    dbo.Frases
where
    regexp_count(texto, ' {2,}') > 0
    or regexp_count(texto, '[!?]{2,}') > 0
order by
    bloques_espacios_multiples desc,
    id;

-- 2.5 El parámetro "inicio": contar sólo lo que aparece a partir del carácter 60
--     Útil cuando la cabecera de la nota siempre repite los mismos datos.
select
    id,
    regexp_count(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€') as importes_total,
    regexp_count(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€', 60) as importes_desde_pos_60,
    texto
from
    dbo.Frases
where
    regexp_count(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€') > 0
order by
    id;


/*==============================================================================================
  3. REGEXP_INSTR  -  ¿en qué posición está? Se combina muy bien con SUBSTRING/STUFF.

     REGEXP_INSTR (cadena, patron [, inicio [, ocurrencia [, opcion_retorno [, flags [, grupo]]]]])
       opcion_retorno: 0 = posición inicial (por defecto), 1 = posición final
       grupo         : 0 = coincidencia completa (por defecto), n = grupo de captura n
==============================================================================================*/

-- 3.1 Posición donde empieza el DNI (0 si no hay)
select
    id,
    regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b') as pos_dni,
    texto
from
    dbo.Frases
order by
    pos_dni desc,
    id;


-- 3.2 opcion_retorno = 1: posición inicial y final, y recorte con SUBSTRING
select
    id,
    regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b', 1, 1, 0) as pos_ini,
    regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b', 1, 1, 1) as pos_fin,
    SUBSTRING(texto,
              regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b', 1, 1, 0),
              regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b', 1, 1, 1)
            - regexp_instr(texto, '\b[0-9]{8}[A-Za-z]\b', 1, 1, 0)) as dni_recortado
from
    dbo.Frases
where
    regexp_like(texto, '\b[0-9]{8}[A-Za-z]\b')
order by
    id;

-- 3.3 El parámetro "ocurrencia": dónde está el 1.º, el 2.º y el 3.er teléfono
select
    id,
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b', 1, 1) as pos_tel_1,
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b', 1, 2) as pos_tel_2,
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b', 1, 3) as pos_tel_3,
    texto
from
    dbo.Frases
where
    regexp_count(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b') >= 2
order by
    id;


-- 3.4 El parámetro "inicio": buscar el siguiente teléfono a partir del anterior
--     Patrón clásico para recorrer un texto de izquierda a derecha.
select
    id,
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b') as primer_tel,
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b',
    regexp_instr(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b', 1, 1, 1)) as siguiente_tel,
    texto
from
    dbo.Frases
where
    regexp_count(texto, '\b[6-9](?:[ .-]?[0-9]){8}\b') >= 2
order by
    id;


-- 3.5 El parámetro "grupo": posición del año DENTRO de una fecha dd/mm/aaaa
--     grupo 3 = el tercer paréntesis del patrón, es decir el año.
select
    id,
    regexp_instr(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 0, 'c', 0) as pos_fecha_completa,
    regexp_instr(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 0, 'c', 3) as pos_del_anio,
    texto
from
    dbo.Frases
where
    regexp_like(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b')
order by
    id;



/*==============================================================================================
  4. REGEXP_SUBSTR  -  extraer el dato. La función estrella para sacar DNI, teléfonos, etc.

     REGEXP_SUBSTR (cadena, patron [, inicio [, ocurrencia [, flags [, grupo]]]])
     Devuelve NULL si no hay coincidencia.
==============================================================================================*/

-- 4.1 Extraer DNI, NIE, CIF y email de cada nota
select
    id,
    canal,
    REGEXP_SUBSTR(texto, '\b[0-9]{8}[A-Za-z]\b') as dni,
    REGEXP_SUBSTR(texto, '\b[XYZ][0-9]{7}[A-Za-z]\b') as nie,
    REGEXP_SUBSTR(texto, '\b[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]\b') as cif,
    REGEXP_SUBSTR(texto, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') as email
from
    dbo.Frases
where
    REGEXP_LIKE(texto, '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b')
    or REGEXP_LIKE(texto, '\b[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]\b')
    or REGEXP_LIKE(texto, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
order by
    id;


-- 4.2 El parámetro "ocurrencia": sacar el 1.º y el 2.º teléfono en columnas distintas
select
    id,
    REGEXP_SUBSTR(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b', 1, 1) as telefono_1,
    REGEXP_SUBSTR(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b', 1, 2) as telefono_2,
    REGEXP_SUBSTR(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b', 1, 3) as telefono_3,
    texto
from
    dbo.Frases
where
    REGEXP_COUNT(texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b') >= 2
order by
    id;


-- 4.3 El parámetro "grupo": trocear una fecha dd/mm/aaaa en día, mes y año
--     y reconstruirla como DATE. Sin grupos habría que usar SUBSTRING a pelo.
select
    id,
    REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 0) as fecha_texto,
    REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 1) as dia,
    REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 2) as mes,
    REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 3) as anio,
    try_convert(DATE,
        REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 3) + '-' +
        REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 2) + '-' +
        REGEXP_SUBSTR(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', 1, 1, 'c', 1)) as fecha_date
from
    dbo.Frases
where
    REGEXP_LIKE(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b')
order by
    id;


-- 4.4 Extraer un importe en formato español y convertirlo a DECIMAL
--     Truco: quitar el punto de millares y cambiar la coma decimal por punto.
select
    id,
    REGEXP_SUBSTR(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€') as importe_texto,
    TRY_CAST(
        REPLACE(REPLACE(REGEXP_REPLACE(
            REGEXP_SUBSTR(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€'),
            '[ €]', ''), '.', ''), ',', '.') as DECIMAL(12, 2)) as importe_num,
    texto
from
    dbo.Frases
where
    REGEXP_LIKE(texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€')
order by
    importe_num desc;

-- 4.5 El flag 'i' y el parámetro "inicio": IBAN escrito en minúsculas o a mitad del texto
select
    id,
    REGEXP_SUBSTR(texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b') as iban_sensible,
    REGEXP_SUBSTR(texto, '\bes[0-9]{2}(?:[ ]?[0-9]{4}){5}\b', 1, 1, 'i') as iban_insensible,
    REGEXP_SUBSTR(texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b', 40) as iban_desde_pos_40,
    texto
from
    dbo.Frases
where
    REGEXP_LIKE(texto, '\bes[0-9]{2}(?:[ ]?[0-9]{4}){5}\b', 'i')
order by
    id;

/*==============================================================================================
  5. REGEXP_REPLACE  -  modificar la frase: normalizar, enmascarar, limpiar.

     REGEXP_REPLACE (cadena, patron [, reemplazo [, inicio [, ocurrencia [, flags]]]])
     En el reemplazo:  \1..\9 = grupos de captura,  & = coincidencia completa.
==============================================================================================*/

-- 5.1 Anonimizar (pseudonimizar) datos personales: DNI/NIE, teléfonos, IBAN, email y tarjeta
select
    id,
    texto as original,
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(texto,
              '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b', 'ES**-ANONIMIZADO'), -- 1.º el IBAN
              '\b(?:[0-9]{4}[ -]?){3}[0-9]{4}\b',            '****-****-****-****'),   -- 2.º la tarjeta
              '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b',      '***DOC***'),             -- 3.º DNI/NIE
              '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b', '***TEL***'),     -- 4.º teléfonos
              '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',      '***MAIL***') AS anonimizado
    -- El ORDEN es crítico: si enmascaras la tarjeta antes que el IBAN, el patrón de 4x4
    -- dígitos se come los bloques centrales de un IBAN escrito con espacios (frase 4).
from 
    dbo.Frases
order by
    id;


-- 5.2 Enmascarado parcial con grupos de captura: dejar visibles los 3 últimos dígitos
--     \1 = los primeros dígitos que ocultamos, \2 = los que dejamos a la vista
select
    id,
    REGEXP_REPLACE(texto, '\b([0-9]{5})([0-9]{3})([A-Za-z])\b', '*****\2\3') as dni_enmascarado,
    REGEXP_REPLACE(texto, '\b([6-9][0-9]{2})[ .-]?([0-9]{3})[ .-]?([0-9]{3})\b', '\1 *** \3') as tel_enmascarado
from
    dbo.Frases
where
    REGEXP_LIKE(texto, '\b[0-9]{8}[A-Za-z]\b')
order by
    id;

-- 5.3 Limpieza del dato: colapsar espacios, quitar signos repetidos y recortar
select
    id,
    texto as original,
    TRIM(REGEXP_REPLACE(
           REGEXP_REPLACE(texto, '[!?]{2,}', '!'), -- gracias!!! -> gracias!
           '\s{2,}', ' ')) AS texto_limpio,
    -- IBAN sin espacios ni guiones, listo para comparar
    REGEXP_REPLACE(REGEXP_SUBSTR(texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b'), '[^0-9A-Za-z]', '') AS iban_compacto
from 
    dbo.Frases
where
    REGEXP_LIKE(texto, '\s{2,}')
    or REGEXP_LIKE(texto, '[!?]{2,}')
    or REGEXP_LIKE(texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b')
order by
    id;


-- 5.4 Reordenar con grupos y usar "ocurrencia": fechas dd/mm/aaaa -> aaaa-mm-dd
--     Compara: reemplazar TODAS (ocurrencia = 0) frente a sólo la SEGUNDA (ocurrencia = 2).
select
    id,
    texto as original,
    REGEXP_REPLACE(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', '\3-\2-\1') as todas_a_iso,
    REGEXP_REPLACE(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', '\3-\2-\1', 1, 2) as solo_la_segunda, -- El símbolo & inserta la coincidencia completa: útil para resaltar
    REGEXP_REPLACE(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b', '[[&]]')          AS resaltada
from dbo.Frases
where
    REGEXP_LIKE(texto, '\b([0-3][0-9])/([01][0-9])/([12][0-9]{3})\b')
order by
    id;



/*==============================================================================================
  6. REGEXP_MATCHES  -  función de tabla: TODAS las coincidencias, con posición y grupos.

     REGEXP_MATCHES (cadena, patron [, flags])
     Columnas: match_id (bigint), start_position (int), end_position (int),
               match_value, substring_matches (JSON con los grupos de captura)
     Se usa con CROSS APPLY / OUTER APPLY.
==============================================================================================*/

-- 6.1 Todos los teléfonos de todas las notas, en filas
select
    f.id,
    f.canal,
    m.match_id as n_coincidencia,
    m.match_value as telefono,
    m.start_position,
    m.end_position
from
    dbo.Frases as f
cross apply REGEXP_MATCHES(f.texto, '\b(?:(?:\+34|0034)[ .-]?)?[6-9](?:[ .-]?[0-9]){8}\b') as m
order by
    f.id,
    m.match_id;

-- 6.2 Inventario completo de códigos postales y de documentos, con su posición exacta
select
    f.id,
    'CP' as tipo,
    m.match_value as valor,
    m.start_position
from
    dbo.Frases as f
cross apply REGEXP_MATCHES(f.texto, '\b(?:0[1-9]|[1-4][0-9]|5[0-2])[0-9]{3}\b') as m
union all
select
    f.id,
    'DOC',
    m.match_value,
    m.start_position
from
    dbo.Frases as f
cross apply REGEXP_MATCHES(f.texto, '\b(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]\b') as m
order by
    id,
    tipo,
    start_position;


-- 6.3 Agregación sobre las coincidencias: todos los importes de cada nota, sumados
--     (REGEXP_MATCHES devuelve filas, así que puedes usar GROUP BY, SUM, STRING_AGG...)
select
    f.id,
    STRING_AGG(m.match_value, ' | ') within group (
    order by m.match_id) as importes_detectados,
    COUNT(*) as n_importes,
    SUM(TRY_CAST(REPLACE(REPLACE(REGEXP_REPLACE(m.match_value, '[ €]', ''), '.', ''), ',', '.') as DECIMAL(12, 2))) as suma_importes
from
    dbo.Frases as f
cross apply REGEXP_MATCHES(f.texto, '[0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2} ?€') as m
group by
    f.id
order by
    suma_importes desc;



/*==============================================================================================
  7. REGEXP_SPLIT_TO_TABLE  -  partir una cadena por un patrón (no por un único carácter).

     REGEXP_SPLIT_TO_TABLE (cadena, patron [, flags])
     Columnas: ordinal (int), value
     A diferencia de STRING_SPLIT, el separador puede ser una expresión regular.
==============================================================================================*/

-- 7.1 Partir la lista de etiquetas del chat (frase 18), separada por barras verticales
select
    s.ordinal,
    s.value as etiqueta
from
    dbo.Frases as f
cross apply REGEXP_SPLIT_TO_TABLE(REGEXP_REPLACE(f.texto, '^Etiquetas:\s*', ''), '\|') as s
where
    f.id = 18
order by
    s.ordinal;


-- 7.2 Separador múltiple: partir la firma de la frase 40 por " | " o por ". "
select
    s.ordinal,
    TRIM(s.value) as bloque
from
    dbo.Frases as f
cross apply REGEXP_SPLIT_TO_TABLE(f.texto, '\s*\|\s*|\.\s+') as s
where
    f.id = 40
    and TRIM(s.value) <> ''
order by
    s.ordinal;


-- 7.3 Tokenizar en palabras y quedarnos sólo con los "tokens interesantes"
select
    f.id,
    s.ordinal,
    s.value as palabra,
    case
        when REGEXP_LIKE(s.value, '^(?:[XYZ][0-9]{7}|[0-9]{8})[A-Za-z]$') then 'DOCUMENTO'
        when REGEXP_LIKE(s.value, '^[0-9]{9}$') then 'TELEFONO'
        when REGEXP_LIKE(s.value, '^(?:0[1-9]|[1-4][0-9]|5[0-2])[0-9]{3}$') then 'CP'
        when REGEXP_LIKE(s.value, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') then 'EMAIL'
        when REGEXP_LIKE(s.value, '^[A-Z]{3}[-/][0-9]{4}[-/][0-9]{3,5}$') then 'REFERENCIA'
        else 'texto'
    end as tipo_token
from
    dbo.Frases as f
cross apply REGEXP_SPLIT_TO_TABLE(f.texto, '[\s,;:()¿?¡!]+') as s
where
    f.id in (1, 4, 13, 19, 26)
order by
    f.id,
    s.ordinal;


-- 7.4 Frecuencia de palabras del corpus, descartando palabras vacías y cifras
with 
    palabras as (
        select
            LOWER(REGEXP_REPLACE(s.value, '[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]', '')) as palabra
        from
            dbo.Frases as f
            cross apply REGEXP_SPLIT_TO_TABLE(f.texto, '[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9@._+-]+') as s
        )
select
    top (25) palabra,
    COUNT(*) as veces
from
    palabras
where
    LEN(palabra) >= 4
    and palabra not in ('para', 'este', 'esta', 'todas', 'desde', 'hasta', 'como', 'entre')
group by
    palabra
order by
    veces desc,
    palabra;


-- 7.5 Partir el IBAN en sus 6 bloques de 4 y volver a montarlo formateado
select
    f.id,
    STRING_AGG(s.value, '-') within group ( order by s.ordinal) as iban_por_bloques,
    COUNT(*) as n_bloques
from
    dbo.Frases as f
cross apply REGEXP_SPLIT_TO_TABLE(
        -- primero compactamos el IBAN y luego insertamos un separador cada 4 caracteres
        REGEXP_REPLACE(
            REGEXP_REPLACE(REGEXP_SUBSTR(f.texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b'), '[^0-9A-Za-z]', ''),
            '(.{4})', '\1;'),
        ';') AS s
where REGEXP_LIKE(f.texto, '\bES[0-9]{2}(?:[ ]?[0-9]{4}){5}\b')
    and s.value <> ''
group by
    f.id
order by
    f.id;




/*==============================================================================================
  8. CASO COMBINADO: de texto libre a tabla normalizada de entidades
     Éste es el ejercicio que reúne casi todo: MATCHES para encontrar, SUBSTR/REPLACE para
     normalizar y LIKE para clasificar.
==============================================================================================*/

drop table if exists dbo.EntidadesExtraidas;

truncate table dbo.EntidadesExtraidas;

create table dbo.EntidadesExtraidas
(
    frase_id        INT not null,
    tipo            VARCHAR(20) not null,
    valor_bruto     nvarchar(100) not null,
    valor_norm      NVARCHAR(100) null,
    posicion        INT not null
);


insert into dbo.EntidadesExtraidas (frase_id, tipo, valor_bruto, valor_norm, posicion)
select
    f.id,
    p.clave,
    m.match_value,
    case
        p.clave
        when 'TELEFONO' then REGEXP_REPLACE(m.match_value, '[^0-9]', '')
        when 'IBA' then REGEXP_REPLACE(m.match_value, '[^0-9A-Za-z]', '')
        when 'IMPORTE' then REPLACE(REPLACE(REGEXP_REPLACE(m.match_value, '[ €]', ''), '.', ''), ',', '.')
        else UPPER(m.match_value)
    end,
    m.start_position
from
    dbo.Frases as f
cross join dbo.Patrones as p
cross apply regexp_matches(f.texto, p.patron) as m
where
    p.clave in ('DOC', 'CIF', 'TELEFONO', 'IBA', 'MATRICULA', 'CP', 'EMAIL', 'IMPORTE', 'REFERENCIA', 'FECHA_ES');


select * from dbo.EntidadesExtraidas ;
-- Resumen por tipo de entidad
select
    tipo,
    COUNT(*) as encontradas,
    COUNT(distinct valor_norm) as distintas
from
    dbo.EntidadesExtraidas
group by
    tipo
order by
    encontradas desc;


-- Detalle por frase
select
    f.id,
    f.canal,
    f.asunto,
    STRING_AGG(CONCAT(e.tipo, '=', e.valor_norm), '  ') within group (
    order by e.posicion) as entidades
from
    dbo.Frases as f
left join 
    dbo.EntidadesExtraidas as e on
        e.frase_id = f.id
group by
    f.id,
    f.canal,
    f.asunto
order by
    f.id;


/*==============================================================================================
  ANEXO: TRAMPAS Y CONSEJOS
  ------------------------------------------------------------------------------------------
  1. El ORDEN de los parámetros cambia entre funciones. REGEXP_INSTR mete "opcion_retorno"
     ANTES de "flags"; REGEXP_SUBSTR no lo tiene. Si mezclas los dos, obtendrás resultados
     silenciosamente incorrectos.
  2. En el reemplazo se usa \1, no $1. Y & es la coincidencia completa: si quieres un
     ampersand literal, escápalo.
  3. \b (frontera de palabra) es lo que evita que un patrón de teléfono "muerda" trozos de
     un IBAN o de un número de tarjeta. Pruébalo quitándolo en el ejemplo 2.1.
  4. El orden de las sustituciones importa (ejemplo 5.1): enmascara primero el IBAN, luego la
     tarjeta y sólo al final los teléfonos. Al revés, el patrón más corto se come trozos de
     los datos más largos y el resultado es basura difícil de depurar.
  5. Los patrones no validan la letra de control del DNI/NIE ni el dígito del CIF: eso es
     aritmética, no forma. Usa REGEXP para el formato y una función escalar para el dígito.
  6. Ojo con los prefijos internacionales: la frase 31 tiene un +351 portugués cuyos 9
     dígitos casan con el patrón de teléfono español. Ancla el +34 si eso te importa.
  7. Las clases como [A-Z] no incluyen acentos ni Ñ; añádelos explícitamente cuando trabajes
     con texto en español.
  8. Rendimiento: REGEXP_* no usa índices. Filtra antes por columnas indexadas, o
     materializa el resultado en una columna calculada persistida con índice.
==============================================================================================*/
