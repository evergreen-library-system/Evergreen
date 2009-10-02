BEGIN;

-- Generate the equivalent of compound subject entries from the existing rows
-- so that we don't have to laboriously reindex them

INSERT INTO config.upgrade_log (version) VALUES ('0030'); -- dbs

INSERT INTO config.metabib_field (field_class, name, format, xpath ) VALUES
    ( 'subject', 'complete', 'mods32', $$//mods32:mods/mods32:subject//text()$$ );

INSERT INTO metabib.subject_field_entry (source, field, value)
    SELECT source, (
            SELECT id 
            FROM config.metabib_field
            WHERE field_class = 'subject' AND name = 'complete'
        ), 
        ARRAY_TO_STRING ( 
            ARRAY (
                SELECT value 
                FROM metabib.subject_field_entry msfe
                WHERE msfe.source = groupee.source
                ORDER BY source 
            ), ' ' 
        ) AS grouped
    FROM ( 
        SELECT source
        FROM metabib.subject_field_entry
        GROUP BY source
    ) AS groupee
    ORDER BY source;

COMMIT;
