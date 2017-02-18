BEGIN;

SELECT evergreen.upgrade_deps_block_check('1016', :eg_version);

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartName',
        '//mods32:mods/mods32:titleInfo/mods32:partName',
        'mods32'
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartNumber',
        '//mods32:mods/mods32:titleInfo/mods32:partNumber',
        'mods32'
    );

COMMIT;
