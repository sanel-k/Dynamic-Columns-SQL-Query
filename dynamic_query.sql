DECLARE
    attr_descs_select VARCHAR2(32767);
    attr_descs_pivot  VARCHAR2(32767);
    dynamic_sql       VARCHAR2(32767);
BEGIN
    -- Generate column names using double quotes and prefixes (COL_#)
    SELECT LISTAGG(
               CASE 
                   WHEN attr_desc = 'Party Name' THEN 'COL_' || rn || ' AS "Entity"'
                   ELSE 'COL_' || rn || ' AS "' || REPLACE(attr_desc, '"', '""') || '"'
               END, 
               ', ') 
           WITHIN GROUP (ORDER BY attr_desc)
    INTO attr_descs_select
    FROM (
        SELECT attr_desc, ROWNUM AS rn
        FROM (
            SELECT DISTINCT attr_desc
            FROM table3
            WHERE SYSDATE BETWEEN valid_from AND NVL(valid_to, SYSDATE)
            ORDER BY attr_desc
        )
    );

    -- Generate PIVOT IN clause with single-quoted values and prefixes (COL_#)
    SELECT LISTAGG( '''' || REPLACE(attr_desc, '''', '''''') || ''' AS COL_' || rn, ', ') 
           WITHIN GROUP (ORDER BY attr_desc)
    INTO attr_descs_pivot
    FROM (
        SELECT attr_desc, ROWNUM AS rn
        FROM (
            SELECT DISTINCT attr_desc
            FROM table3
            WHERE SYSDATE BETWEEN valid_from AND NVL(valid_to, SYSDATE)
            ORDER BY attr_desc
        )
    );

    -- Dynamic SQL
    dynamic_sql := q'$  
        SELECT /*+ MATERIALIZE */ party_id, party_name AS "Entita", #attr_descs_select#
        FROM (
            SELECT
                a.party_id,
                p.party_name,
                l.crr_lov_item_value AS attr_value,
                n.attr_desc
            FROM 
                table1 a
                JOIN table2 p ON a.party_id = p.party_id
                JOIN table3 n ON a.attr_name = n.attr_name
                JOIN table4 l ON n.attr_lov = l.crr_lov_name AND a.attr_value = l.crr_lov_item_name
            WHERE
                SYSDATE BETWEEN a.valid_from AND NVL(a.valid_to, SYSDATE)
                AND SYSDATE BETWEEN p.valid_from AND NVL(p.valid_to, SYSDATE)
                AND SYSDATE BETWEEN n.valid_from AND NVL(n.valid_to, SYSDATE)
                AND SYSDATE BETWEEN l.valid_from AND NVL(l.valid_to, SYSDATE)
        )
        PIVOT (
            MAX(attr_value)
            FOR attr_desc IN ( #attr_descs_pivot# )
        )$';

    -- Replace placeholders with generated lists
    dynamic_sql := REPLACE(dynamic_sql, '#attr_descs_select#', attr_descs_select);
    dynamic_sql := REPLACE(dynamic_sql, '#attr_descs_pivot#', attr_descs_pivot);

    RETURN dynamic_sql;
END;
