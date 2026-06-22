// ======================================================
// LABORATORIO 3 - INF325 BASES DE DATOS AVANZADAS
// Grafo de Explicabilidad para Auditoría de Clasificación Normativa
// Versión FINAL corregida
// ======================================================
//
// INSTRUCCIONES DE USO:
// 1. Guardar normativas_clasificadas_IA.csv como "UTF-8 (sin BOM)" y copiarlo a la
//    carpeta import de Neo4j (en Neo4j Desktop: botón derecho sobre la BD > Open
//    folder > Import). El BOM es importante: si el archivo tiene BOM, la primera
//    columna se lee como "\uFEFFname" en vez de "name" y NO se carga ninguna fila.
// 2. Ejecutar este script COMPLETO de una sola vez en Neo4j Browser
//    (no es necesario ejecutar bloque por bloque, pero se puede).
// 3. Las consultas de la sección 9 son las que se deben capturar para el informe.
//
// VERIFICACIÓN RÁPIDA tras la carga (sección 8): deben aparecer 129 normativas
// (20 Relevante / 109 No Relevante). Si aparece 0, el problema es el BOM del CSV.


// ------------------------------------------------------
// 0. Limpieza inicial de la base de datos
// ------------------------------------------------------
// Borra los datos existentes para que el laboratorio sea reproducible.
// Si ejecutamos el script varias veces, evitamos duplicados.

MATCH (n)
DETACH DELETE n;


// ------------------------------------------------------
// 1. Restricciones de unicidad
// ------------------------------------------------------
// Las restricciones evitan nodos repetidos.
// Las dejamos antes de cargar datos para que Neo4j controle duplicados
// desde el comienzo del proceso.

CREATE CONSTRAINT normativa_name_unique IF NOT EXISTS
FOR (n:Normativa)
REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT fuente_nombre_unique IF NOT EXISTS
FOR (f:Fuente)
REQUIRE f.nombre IS UNIQUE;

CREATE CONSTRAINT tipo_nombre_unique IF NOT EXISTS
FOR (t:TipoDocumento)
REQUIRE t.nombre IS UNIQUE;

CREATE CONSTRAINT regla_nombre_unique IF NOT EXISTS
FOR (r:ReglaNegocio)
REQUIRE r.nombre IS UNIQUE;

CREATE CONSTRAINT agente_nombre_unique IF NOT EXISTS
FOR (a:AgenteIA)
REQUIRE a.nombre IS UNIQUE;

CREATE CONSTRAINT clasificacion_id_unique IF NOT EXISTS
FOR (c:ClasificacionIA)
REQUIRE c.id IS UNIQUE;

CREATE CONSTRAINT explicacion_id_unique IF NOT EXISTS
FOR (e:ExplicacionIA)
REQUIRE e.id IS UNIQUE;

CREATE CONSTRAINT evidencia_id_unique IF NOT EXISTS
FOR (ev:EvidenciaTextual)
REQUIRE ev.id IS UNIQUE;

CREATE CONSTRAINT auditoria_id_unique IF NOT EXISTS
FOR (ah:AuditoriaHumana)
REQUIRE ah.id IS UNIQUE;


// ------------------------------------------------------
// 2. Creación del agente IA
// ------------------------------------------------------
// El dataset ya fue clasificado por un agente IA normativo.
// Aquí NO creamos una IA nueva; solo representamos la decisión
// para poder auditarla en forma explicable.

MERGE (:AgenteIA {
    nombre: "Agente IA Normativo",
    tecnica: "Procesamiento de lenguaje natural y RAG",
    objetivo: "Clasificar normativas como Relevante o No Relevante"
});


// ------------------------------------------------------
// 3. Carga del dataset CSV y creación de nodos principales
// ------------------------------------------------------
// Cada fila del CSV representa una normativa clasificada por la IA.
// Para que esto funcione, el archivo normativas_clasificadas_IA.csv
// debe estar en la carpeta import de Neo4j.

LOAD CSV WITH HEADERS FROM 'file:///normativas_clasificadas_IA.csv' AS row

WITH row
WHERE row.name IS NOT NULL AND trim(row.name) <> ""

// ------------------------------------------------------
// 3.1 Crear nodo Normativa
// ------------------------------------------------------
// MERGE evita duplicados: si existe la normativa, la reutiliza;
// si no existe, la crea.

MERGE (n:Normativa {name: trim(row.name)})

SET n.description = coalesce(row.description, ""),
    n.url = coalesce(row.url, ""),
    n.cuerpo = coalesce(row.cuerpo, ""),
    n.relevancia_ia = coalesce(row.relevancia, ""),
    n.explicacion_ia = coalesce(row.explicacion, ""),
    n.tipo_documento = coalesce(row.tipo_documento, ""),
    n.fuente = coalesce(row.fuente, "")

// ------------------------------------------------------
// 3.2 Etiquetas por tipo documental
// ------------------------------------------------------
// Etiquetas obligatorias solicitadas por el laboratorio:
// :Circular y :Resolucion.

FOREACH (_ IN CASE
    WHEN toLower(coalesce(row.tipo_documento, "")) CONTAINS "circular"
    THEN [1] ELSE [] END |
    SET n:Circular
)

FOREACH (_ IN CASE
    WHEN toLower(coalesce(row.tipo_documento, "")) CONTAINS "resol"
    THEN [1] ELSE [] END |
    SET n:Resolucion
)

// ------------------------------------------------------
// 3.3 Etiquetas por clasificación IA
// ------------------------------------------------------
// Etiquetas obligatorias:
// :Relevante y :NoRelevante.

FOREACH (_ IN CASE
    WHEN toLower(trim(coalesce(row.relevancia, ""))) = "relevante"
    THEN [1] ELSE [] END |
    SET n:Relevante
)

FOREACH (_ IN CASE
    WHEN toLower(trim(coalesce(row.relevancia, ""))) <> "relevante"
    THEN [1] ELSE [] END |
    SET n:NoRelevante
)

// ------------------------------------------------------
// 3.4 Fuente
// ------------------------------------------------------
// Convertimos la fuente en nodo para poder consultar normativas por fuente.

MERGE (f:Fuente {
    nombre: CASE
        WHEN trim(coalesce(row.fuente, "")) = "" THEN "Sin fuente"
        ELSE trim(row.fuente)
    END
})

MERGE (n)-[:PROVIENE_DE]->(f)

// ------------------------------------------------------
// 3.5 Tipo documental
// ------------------------------------------------------
// Convertimos el tipo documental en nodo para navegar el grafo.

MERGE (t:TipoDocumento {
    nombre: CASE
        WHEN trim(coalesce(row.tipo_documento, "")) = "" THEN "Sin tipo documental"
        ELSE trim(row.tipo_documento)
    END
})

MERGE (n)-[:ES_TIPO]->(t)

// ------------------------------------------------------
// 3.6 Clasificación IA
// ------------------------------------------------------
// Creamos un nodo de clasificación por normativa.
// Esto permite auditar cada decisión individual.

MERGE (c:ClasificacionIA {id: "clasificacion_" + trim(row.name)})

SET c.valor = coalesce(row.relevancia, ""),
    c.descripcion = "Clasificación generada automáticamente por el agente IA"

MERGE (n)-[:CLASIFICADA_COMO]->(c)

// ------------------------------------------------------
// 3.7 Explicación IA
// ------------------------------------------------------
// La explicación es clave porque permite justificar la decisión de la IA.

MERGE (e:ExplicacionIA {id: "explicacion_" + trim(row.name)})

SET e.texto = coalesce(row.explicacion, ""),
    e.origen = "Explicación generada por IA"

MERGE (n)-[:TIENE_EXPLICACION]->(e)
MERGE (c)-[:SE_JUSTIFICA_CON]->(e)

// ------------------------------------------------------
// 3.8 Conectar agente IA con clasificación y explicación
// ------------------------------------------------------

WITH n, c, e

MATCH (a:AgenteIA {nombre: "Agente IA Normativo"})

MERGE (a)-[:GENERO_CLASIFICACION]->(c)
MERGE (a)-[:GENERO_EXPLICACION]->(e);


// ------------------------------------------------------
// 4. Creación de reglas de negocio preestablecidas
// ------------------------------------------------------
// El enunciado entrega referencias normativas (Tabla 2) y palabras
// clave de negocio (Tabla 3). Cada una se representa como nodo
// :ReglaNegocio, con sus patrones de detección asociados.
//
// NOTA sobre los patrones: se guardan ya normalizados (minúsculas, sin
// puntuación, con variantes con/sin tilde) porque la detección de la
// sección 5 hace coincidencia por PALABRA COMPLETA. Esto evita falsos
// positivos como que "pos" coincida dentro de "disposiciones", "posible"
// o "depositar". Por eso, p.ej., POS se busca como la palabra " pos "
// y P.O.S como " p o s ".

UNWIND [

    {
        nombre: "Resolución 176 de 2020",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones a la Resolución Exenta N° 176 de 2020",
        patrones: ["176 de 2020"]
    },
    {
        nombre: "Resolución 76 de 2021",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones a la Resolución Exenta N° 76 de 2021",
        patrones: ["76 de 2021"]
    },
    {
        nombre: "Resolución 79 de 2025",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones a la Resolución Exenta N° 79 de 2025",
        patrones: ["79 de 2025"]
    },
    {
        nombre: "Resolución 59 de 2025",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones a la Resolución N° 59 de 2025",
        patrones: ["59 de 2025"]
    },
    {
        nombre: "Circular 38 de 2025",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones a la Circular N° 38 de 2025",
        patrones: ["38 de 2025"]
    },
    {
        nombre: "Artículo 68 del Código Tributario",
        tipo: "Referencia normativa",
        descripcion: "Detecta menciones al Artículo 68 del Código Tributario",
        patrones: ["artículo 68 del código tributario", "articulo 68 del codigo tributario"]
    },
    {
        nombre: "Contiene boleta",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a boletas",
        patrones: ["boleta", "boletas"]
    },
    {
        nombre: "Contiene comprobante electrónico",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a comprobantes electrónicos",
        patrones: ["comprobante electrónico", "comprobante electronico"]
    },
    {
        nombre: "Contiene registro de compra",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones al registro de compra",
        patrones: ["registro de compra", "registro de compras"]
    },
    {
        nombre: "Contiene registro de venta",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones al registro de venta",
        patrones: ["registro de venta", "registro de ventas"]
    },
    {
        nombre: "Contiene cumplimiento tributario",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a cumplimiento tributario",
        patrones: ["cumplimiento tributario"]
    },
    {
        nombre: "Contiene inicio de actividades",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a inicio de actividades",
        patrones: ["inicio de actividades"]
    },
    {
        nombre: "Contiene medios de pago electrónicos",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a medios de pago electrónicos",
        patrones: ["medios de pago electrónicos", "medios de pago electronicos"]
    },
    {
        nombre: "Contiene POS",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a la sigla POS (terminal de pago) como palabra completa",
        patrones: ["pos"]
    },
    {
        nombre: "Contiene P.O.S",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a P.O.S",
        patrones: ["p o s"]
    },
    {
        nombre: "Contiene puntos de venta",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a puntos de venta",
        patrones: ["puntos de venta", "punto de venta"]
    },
    {
        nombre: "Contiene operadores y administradores",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a operadores y administradores",
        patrones: ["operadores y administradores"]
    },
    {
        nombre: "Contiene comercio electrónico",
        tipo: "Palabra clave",
        descripcion: "Detecta menciones a comercio electrónico",
        patrones: ["comercio electrónico", "comercio electronico"]
    }

] AS regla

MERGE (r:ReglaNegocio {nombre: regla.nombre})

SET r.tipo = regla.tipo,
    r.descripcion = regla.descripcion,
    r.patrones = regla.patrones;


// ------------------------------------------------------
// 5. Detección de reglas activadas y evidencia textual
// ------------------------------------------------------
// DECISIÓN METODOLÓGICA IMPORTANTE (a explicar en el informe):
//
// (1) La evidencia textual se busca SOLO en los campos objetivos de la
//     normativa: name, description y cuerpo. NO se busca en el campo
//     "explicacion" (explicacion_ia).
//     Motivo: el campo "explicacion" contiene el razonamiento de la IA, y
//     en este dataset la IA suele listar TODAS las palabras clave dentro de
//     su explicación incluso cuando la normativa es "No Relevante"
//     (ej.: "...no se relaciona con boletas, comprobantes electrónicos,
//     POS, comercio electrónico..."). Buscar ahí generaría evidencia falsa.
//     La evidencia debe respaldarse en el TEXTO DE LA NORMATIVA, no en la
//     opinión de la IA sobre ese texto. La explicación de la IA se compara
//     DESPUÉS contra estas reglas objetivas (sección 6).
//
// (2) La coincidencia es por PALABRA COMPLETA, no por substring. Para ello
//     normalizamos el texto reemplazando puntuación por espacios y luego
//     comparamos el patrón envuelto en espacios (" patron "). Así "pos"
//     coincide solo con la palabra POS y no con "disposiciones", "posible",
//     "depositar", etc. (que es el error clásico del substring matching).

MATCH (n:Normativa)
MATCH (r:ReglaNegocio)

WITH n, r,
     " " + toLower(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
        coalesce(n.name, ""),
        ".", " "), ",", " "), ";", " "), ":", " "), "(", " "), ")", " "), "[", " "), "]", " "), "/", " "), "\\", " "), "-", " "), "\"", " "), "'", " "), "\n", " ")) + " " AS txt_name,
     " " + toLower(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
        coalesce(n.description, ""),
        ".", " "), ",", " "), ";", " "), ":", " "), "(", " "), ")", " "), "[", " "), "]", " "), "/", " "), "\\", " "), "-", " "), "\"", " "), "'", " "), "\n", " ")) + " " AS txt_description,
     " " + toLower(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
        coalesce(n.cuerpo, ""),
        ".", " "), ",", " "), ";", " "), ":", " "), "(", " "), ")", " "), "[", " "), "]", " "), "/", " "), "\\", " "), "-", " "), "\"", " "), "'", " "), "\n", " ")) + " " AS txt_cuerpo

// Lista de patrones que efectivamente aparecen como palabra completa.
WITH n, r, txt_name, txt_description, txt_cuerpo,
     [patron IN r.patrones WHERE
        txt_name CONTAINS (" " + patron + " ") OR
        txt_description CONTAINS (" " + patron + " ") OR
        txt_cuerpo CONTAINS (" " + patron + " ")
     ] AS patrones_detectados

WHERE size(patrones_detectados) > 0

WITH n, r, txt_name, txt_description, txt_cuerpo,
     patrones_detectados[0] AS patron_detectado

// Identificamos en qué campo objetivo se encontró la evidencia.
WITH n, r, patron_detectado,
     (" " + patron_detectado + " ") AS patron_norm,
     txt_name, txt_description, txt_cuerpo

WITH n, r, patron_detectado,
CASE
    WHEN txt_name CONTAINS patron_norm
        THEN "name"
    WHEN txt_description CONTAINS patron_norm
        THEN "description"
    WHEN txt_cuerpo CONTAINS patron_norm
        THEN "cuerpo"
    ELSE "sin campo identificado"
END AS campo_evidencia

MERGE (n)-[ar:ACTIVA_REGLA]->(r)

SET ar.campo_detectado = campo_evidencia,
    ar.patron_detectado = patron_detectado,
    ar.motivo = "La normativa contiene en su texto un patrón asociado a esta regla de negocio"

MERGE (ev:EvidenciaTextual {
    id: "evidencia_" + n.name + "_" + r.nombre
})

SET ev.campo = campo_evidencia,
    ev.patron_detectado = patron_detectado,
    ev.descripcion = "Evidencia textual objetiva (nombre, descripción o cuerpo) que respalda la activación de una regla de negocio",
    ev.texto = CASE campo_evidencia
        WHEN "name" THEN n.name
        WHEN "description" THEN n.description
        WHEN "cuerpo" THEN "El cuerpo de la normativa contiene el patrón detectado: '" + patron_detectado + "'. Fragmento inicial: " + substring(coalesce(n.cuerpo, ""), 0, 500)
        ELSE "Sin evidencia textual específica"
    END

MERGE (r)-[:RESPALDADA_POR]->(ev)
MERGE (ev)-[:EVIDENCIA_DE]->(n)

WITH n, r
MATCH (n)-[:TIENE_EXPLICACION]->(e:ExplicacionIA)
MERGE (e)-[:ACTIVA_REGLA]->(r);


// ------------------------------------------------------
// 6. Evaluación automática de la explicabilidad
// ------------------------------------------------------
// Criterio usado para considerar que la clasificación de la IA
// está alineada con las reglas de negocio objetivas:
// - Relevante + al menos una regla activada (en texto objetivo) = alineada.
// - No Relevante + cero reglas activadas = alineada.
// - Relevante sin reglas o No Relevante con reglas = inconsistencia,
//   requiere revisión humana.
// - Una explicación demasiado corta (menos de 80 caracteres) también
//   se considera débil, independiente de la alineación de reglas.

MATCH (n:Normativa)-[:TIENE_EXPLICACION]->(e:ExplicacionIA)

OPTIONAL MATCH (n)-[:ACTIVA_REGLA]->(r:ReglaNegocio)

WITH n, e, count(DISTINCT r) AS total_reglas

WITH n, e, total_reglas,
     toLower(trim(coalesce(n.relevancia_ia, ""))) AS relevancia,
     size(trim(coalesce(e.texto, ""))) AS largo_explicacion

WITH n, e, total_reglas, relevancia, largo_explicacion,
     (
        (relevancia = "relevante" AND total_reglas > 0)
        OR
        (relevancia <> "relevante" AND total_reglas = 0)
     ) AS clasificacion_alineada,
     (largo_explicacion < 80) AS explicacion_corta

SET e.total_reglas_activadas = total_reglas,
    e.largo_explicacion = largo_explicacion,
    e.clasificacion_alineada_con_reglas = clasificacion_alineada,
    e.explicacion_corta = explicacion_corta

FOREACH (_ IN CASE
    WHEN clasificacion_alineada = true AND explicacion_corta = false
    THEN [1] ELSE [] END |
    SET n:ExplicacionValida,
        e:ExplicacionValida
)

FOREACH (_ IN CASE
    WHEN clasificacion_alineada = false OR explicacion_corta = true
    THEN [1] ELSE [] END |
    SET n:ExplicacionDebil,
        e:ExplicacionDebil,
        n:RequiereRevision
)

SET n.total_reglas_activadas = total_reglas,
    n.clasificacion_alineada_con_reglas = clasificacion_alineada,
    n.explicacion_corta = explicacion_corta;


// ------------------------------------------------------
// 7. Auditoría humana simulada
// ------------------------------------------------------
// Se auditan cinco normativas, tal como exige el laboratorio.
// Se registra clasificación IA, reglas activadas, evidencia,
// juicio del grupo y justificación.
//
// Casos elegidos para mostrar variedad de escenarios de auditoría:
// - 3 Relevantes correctamente respaldadas por reglas objetivas (Validada).
// - 1 No Relevante correctamente sin reglas activadas (Validada).
// - 1 No Relevante que SÍ activa una regla objetiva: inconsistencia real
//   detectada por el script -> Requiere más antecedentes.

UNWIND [

    {
        normativa: "Circular N° 38 del 30 de Abril del 2025",
        juicio: "Validada",
        justificacion: "La clasificación Relevante es correcta: el cuerpo y la descripción de la normativa contienen evidencia textual objetiva asociada a cumplimiento tributario, inicio de actividades, medios de pago electrónicos y Artículo 68 del Código Tributario, lo que respalda directamente la decisión de la IA."
    },

    {
        normativa: "Resolución Exenta SII N° 12 del 17 de Enero del 2025",
        juicio: "Validada",
        justificacion: "La clasificación Relevante se valida porque el texto de la normativa contiene evidencia objetiva vinculada a boleta, medios de pago electrónicos, cumplimiento tributario y referencias a la Resolución 176 de 2020 y 76 de 2021, conceptos directamente asociados a las reglas de negocio establecidas."
    },

    {
        normativa: "Resolución Exenta SII N° 79 del 26 de Junio del 2025",
        juicio: "Validada",
        justificacion: "La clasificación Relevante se valida porque la normativa activa reglas de negocio relacionadas con inicio de actividades, cumplimiento tributario y Artículo 68 del Código Tributario, evidenciadas directamente en su cuerpo y descripción."
    },

    {
        normativa: "Circular N° 10 del 30 de Enero del 2025",
        juicio: "Validada",
        justificacion: "La clasificación No Relevante es correcta: la normativa trata precios de transferencia y operaciones transfronterizas, y no activa ninguna regla de negocio al revisar su texto objetivo (nombre, descripción, cuerpo) con coincidencia por palabra completa."
    },

    {
        normativa: "Circular N° 35 del 30 de Abril del 2025",
        juicio: "Requiere más antecedentes",
        justificacion: "Aunque la IA clasificó esta normativa como No Relevante, el análisis de evidencia textual objetiva detecta la activación de una regla de negocio (inicio de actividades) en su texto. Esta inconsistencia entre la clasificación de la IA y la evidencia textual debe ser revisada por un analista humano antes de aceptar la decisión automatizada."
    }

] AS auditoria

MATCH (n:Normativa {name: auditoria.normativa})

OPTIONAL MATCH (n)-[:ACTIVA_REGLA]->(r:ReglaNegocio)
OPTIONAL MATCH (r)-[:RESPALDADA_POR]->(ev:EvidenciaTextual)-[:EVIDENCIA_DE]->(n)

WITH n, auditoria,
     collect(DISTINCT r.nombre) AS reglas_activadas,
     collect(DISTINCT ev.texto)[0..3] AS evidencias_textuales

MERGE (ah:AuditoriaHumana {
    id: "auditoria_" + auditoria.normativa
})

SET ah.normativa_revisada = auditoria.normativa,
    ah.clasificacion_ia = n.relevancia_ia,
    ah.reglas_activadas = reglas_activadas,
    ah.evidencias_textuales = evidencias_textuales,
    ah.juicio_grupo = auditoria.juicio,
    ah.justificacion = auditoria.justificacion,
    ah.revisor = "Grupo de laboratorio",
    ah.fecha_revision = date()

MERGE (n)-[:REVISADA_EN]->(ah)

SET n:Auditada

FOREACH (_ IN CASE
    WHEN auditoria.juicio = "Requiere más antecedentes"
    THEN [1] ELSE [] END |
    SET n:RequiereRevision
);


// ------------------------------------------------------
// 7.1 Relaciones adicionales para fortalecer la ruta explicable
// ------------------------------------------------------
// Esto deja explícita la ruta esperada por el enunciado:
// Normativa -> Clasificación -> Explicación -> Regla -> Evidencia -> Auditoría.

MATCH (n:Auditada)-[:REVISADA_EN]->(ah:AuditoriaHumana)
MATCH (n)-[:CLASIFICADA_COMO]->(c:ClasificacionIA)
MATCH (n)-[:TIENE_EXPLICACION]->(e:ExplicacionIA)
MERGE (ah)-[:REVISA_CLASIFICACION]->(c)
MERGE (ah)-[:REVISA_EXPLICACION]->(e);

MATCH (n:Auditada)-[:REVISADA_EN]->(ah:AuditoriaHumana)
MATCH (r:ReglaNegocio)-[:RESPALDADA_POR]->(ev:EvidenciaTextual)-[:EVIDENCIA_DE]->(n)
MERGE (ev)-[:CONSIDERADA_EN_AUDITORIA]->(ah);


// ======================================================
// 8. CONSULTAS DE VALIDACIÓN RÁPIDA (opcional, no son entregable)
// ======================================================
// Estas consultas sirven solo para comprobar que la carga funcionó.
// No son las capturas finales del informe.
//
// Resultados esperados con el dataset entregado:
//   8.1 -> 129 :Normativa, y conteos por etiqueta combinada.
//   8.2 -> Relevante: 20 | No Relevante: 109.
//   8.3 -> total de relaciones ACTIVA_REGLA distintas de cero (sin falsos
//          positivos de POS).


// 8.1 Cantidad de nodos por etiqueta
MATCH (n)
RETURN labels(n) AS etiquetas, count(n) AS total
ORDER BY total DESC;


// 8.2 Cantidad de normativas por clasificación IA
MATCH (n:Normativa)
RETURN n.relevancia_ia AS clasificacion_ia, count(n) AS total;


// 8.3 Cantidad de reglas activadas
MATCH (:Normativa)-[ar:ACTIVA_REGLA]->(:ReglaNegocio)
RETURN count(ar) AS total_reglas_activadas;


// 8.4 Activaciones por regla (útil para verificar que POS ya no genera basura)
MATCH (:Normativa)-[:ACTIVA_REGLA]->(r:ReglaNegocio)
RETURN r.nombre AS regla, count(*) AS veces_activada
ORDER BY veces_activada DESC;


// ======================================================
// 9. CONSULTAS DE EXPLICABILIDAD OBLIGATORIAS
// ======================================================
// Estas son las 5 consultas que exige el enunciado (sección 4).
// Ejecutar una por una en Neo4j Browser y capturar pantalla de cada
// resultado para el informe (sección 2.4 de la plantilla).


// ------------------------------------------------------
// Consulta 1: Clasificación general
// ------------------------------------------------------
// Visualiza normativas Relevantes y No Relevantes con nombre, tipo
// documental, fuente, descripción y explicación de la IA.

MATCH (n:Normativa)-[:ES_TIPO]->(t:TipoDocumento)
MATCH (n)-[:PROVIENE_DE]->(f:Fuente)
MATCH (n)-[:TIENE_EXPLICACION]->(e:ExplicacionIA)
RETURN n.name AS normativa,
       n.relevancia_ia AS clasificacion_ia,
       t.nombre AS tipo_documental,
       f.nombre AS fuente,
       n.description AS descripcion,
       e.texto AS explicacion_ia
ORDER BY clasificacion_ia DESC, normativa
LIMIT 30;


// ------------------------------------------------------
// Consulta 2: Explicación de una normativa específica
// ------------------------------------------------------
// Muestra clasificación, explicación, reglas activadas y evidencia
// textual asociada para una normativa puntual.
// Se usa Circular N° 38 porque es un caso Relevante con buen respaldo.

MATCH (n:Normativa {name: "Circular N° 38 del 30 de Abril del 2025"})
MATCH (n)-[:CLASIFICADA_COMO]->(c:ClasificacionIA)
MATCH (c)-[:SE_JUSTIFICA_CON]->(e:ExplicacionIA)
OPTIONAL MATCH (e)-[:ACTIVA_REGLA]->(r:ReglaNegocio)
OPTIONAL MATCH (r)-[:RESPALDADA_POR]->(ev:EvidenciaTextual)-[:EVIDENCIA_DE]->(n)
RETURN n.name AS normativa,
       c.valor AS clasificacion_ia,
       e.texto AS explicacion_ia,
       collect(DISTINCT r.nombre) AS reglas_activadas,
       collect(DISTINCT ev.texto)[0..5] AS evidencias_textuales;


// ------------------------------------------------------
// Consulta 3: Normativas relevantes con respaldo de negocio
// ------------------------------------------------------
// Identifica normativas Relevantes que activan reglas de negocio
// y cuentan con evidencia textual objetiva.

MATCH (n:Normativa:Relevante)-[:ACTIVA_REGLA]->(r:ReglaNegocio)
MATCH (r)-[:RESPALDADA_POR]->(ev:EvidenciaTextual)-[:EVIDENCIA_DE]->(n)
RETURN n.name AS normativa,
       n.relevancia_ia AS clasificacion_ia,
       count(DISTINCT r) AS total_reglas,
       collect(DISTINCT r.nombre)[0..5] AS reglas,
       collect(DISTINCT ev.patron_detectado)[0..5] AS patrones_detectados
ORDER BY total_reglas DESC, normativa;


// ------------------------------------------------------
// Consulta 4: Posibles inconsistencias
// ------------------------------------------------------
// Detecta:
// - No Relevantes que activan reglas de negocio (la IA dijo que no
//   importaba, pero el texto objetivo contiene evidencia de que sí).
// - Relevantes que no activan ninguna regla (la IA dijo que sí
//   importaba, pero no hay evidencia textual objetiva que lo respalde).
// Con el dataset entregado esto devuelve ~16 casos
// (2 Relevantes sin regla + 14 No Relevantes con regla).

MATCH (n:Normativa)
OPTIONAL MATCH (n)-[:ACTIVA_REGLA]->(r:ReglaNegocio)
WITH n, count(DISTINCT r) AS total_reglas, collect(DISTINCT r.nombre) AS reglas
WHERE
    (toLower(n.relevancia_ia) = "relevante" AND total_reglas = 0)
    OR
    (toLower(n.relevancia_ia) <> "relevante" AND total_reglas > 0)
RETURN n.name AS normativa,
       n.relevancia_ia AS clasificacion_ia,
       total_reglas,
       reglas,
       n.clasificacion_alineada_con_reglas AS alineada_con_reglas
ORDER BY total_reglas DESC, normativa;


// ------------------------------------------------------
// Consulta 5: Revisión humana
// ------------------------------------------------------
// Identifica normativas con explicación débil, insuficiente o poco
// alineada con las reglas de negocio (incluye las inconsistencias
// de la Consulta 4 más explicaciones demasiado cortas).

MATCH (n:Normativa)-[:TIENE_EXPLICACION]->(e:ExplicacionIA)
OPTIONAL MATCH (n)-[:REVISADA_EN]->(ah:AuditoriaHumana)
WHERE n:RequiereRevision OR n:ExplicacionDebil
RETURN n.name AS normativa,
       n.relevancia_ia AS clasificacion_ia,
       e.total_reglas_activadas AS total_reglas_activadas,
       e.largo_explicacion AS largo_explicacion,
       e.clasificacion_alineada_con_reglas AS alineada_con_reglas,
       labels(n) AS etiquetas,
       ah.juicio_grupo AS juicio_humano,
       ah.justificacion AS justificacion_auditoria
ORDER BY alineada_con_reglas ASC, total_reglas_activadas DESC, normativa;


// ------------------------------------------------------
// Consulta extra para captura gráfica: ruta explicable completa
// ------------------------------------------------------
// Muestra visualmente la cadena conceptual pedida por el enunciado:
// Normativa -> Clasificación -> Explicación -> Regla -> Evidencia -> Auditoría.
// Útil para la captura de "vista general del grafo" que pide la plantilla.

MATCH path =
(n:Normativa {name: "Circular N° 35 del 30 de Abril del 2025"})
-[:CLASIFICADA_COMO]->(c:ClasificacionIA)
-[:SE_JUSTIFICA_CON]->(e:ExplicacionIA)
-[:ACTIVA_REGLA]->(r:ReglaNegocio)
-[:RESPALDADA_POR]->(ev:EvidenciaTextual)
-[:CONSIDERADA_EN_AUDITORIA]->(ah:AuditoriaHumana)
RETURN path
LIMIT 10;
