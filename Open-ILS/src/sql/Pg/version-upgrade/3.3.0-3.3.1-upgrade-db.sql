--Upgrade Script for 3.3.0 to 3.3.1
\set eg_version '''3.3.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.3.1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1160', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'catalog.record.holds.prefetch', 'cat', 'bool',
    oils_i18n_gettext(
        'catalog.record.holds.prefetch',
        'Pre-Fetch Record Holds',
        'cwst', 'label'
    )
);

SELECT evergreen.upgrade_deps_block_check('1162', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.print.config.default', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.default',
        'Print config for default context',
        'cwst', 'label'
    )
), (
    'eg.print.config.receipt', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.receipt',
        'Print config for receipt context',
        'cwst', 'label'
    )
), (
    'eg.print.config.label', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.label',
        'Print config for label context',
        'cwst', 'label'
    )
), (
    'eg.print.config.mail', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.mail',
        'Print config for mail context',
        'cwst', 'label'
    )
), (
    'eg.print.config.offline', 'gui', 'object',
    oils_i18n_gettext (
        'eg.print.config.offline',
        'Print config for offline context',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1163', :eg_version); -- JBoyer/Dyrcona/bshum/JBoyer

CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $func$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_AGG(tag || (COALESCE(subfield, ''))),
            ARRAY_AGG(value)
        )
        FROM (
            SELECT  tag, subfield, ARRAY_AGG(value)::TEXT AS value
              FROM  (SELECT tag,
                            subfield,
                            CASE WHEN tag = '020' THEN -- caseless -- isbn
                                LOWER((SELECT REGEXP_MATCHES(value,$$^(\S{10,17})$$))[1] || '%')
                            WHEN tag = '022' THEN -- caseless -- issn
                                LOWER((SELECT REGEXP_MATCHES(value,$$^(\S{4}[- ]?\S{4})$$))[1] || '%')
                            WHEN tag = '024' THEN -- caseless -- upc (other)
                                LOWER(value || '%')
                            ELSE
                                value
                            END AS value
                      FROM  vandelay.flatten_marc(record_xml)) x
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

-- No transaction needed. This can be run on a live, production server.
SELECT evergreen.upgrade_deps_block_check('1161', :eg_version); -- jboyer/stompro/gmcharlt

CREATE INDEX CONCURRENTLY atev_template_output ON action_trigger.event (template_output);
CREATE INDEX CONCURRENTLY atev_async_output ON action_trigger.event (async_output);
CREATE INDEX CONCURRENTLY atev_error_output ON action_trigger.event (error_output);
