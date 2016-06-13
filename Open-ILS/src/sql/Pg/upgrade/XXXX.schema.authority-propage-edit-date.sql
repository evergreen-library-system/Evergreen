
BEGIN;

DROP FUNCTION authority.propagate_changes (BIGINT, BIGINT);

CREATE OR REPLACE FUNCTION authority.propagate_changes 
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    bib_rec biblio.record_entry%ROWTYPE;
    new_marc TEXT;
BEGIN

    SELECT INTO bib_rec * FROM biblio.record_entry WHERE id = bid;

    new_marc := vandelay.merge_record_xml(
        bib_rec.marc, authority.generate_overlay_template(aid));

    IF new_marc = bib_rec.marc THEN
        -- Authority record change had no impact on this bib record.
        -- Nothing left to do.
        RETURN aid;
    END IF;

    PERFORM 1 FROM config.global_flag 
        WHERE name = 'ingest.disable_authority_auto_update_bib_meta' 
            AND enabled;

    IF NOT FOUND THEN 
        -- update the bib record editor and edit_date
        bib_rec.editor := (
            SELECT editor FROM authority.record_entry WHERE id = aid);
        bib_rec.edit_date = NOW();
    END IF;

    UPDATE biblio.record_entry SET
        marc = new_marc,
        editor = bib_rec.editor,
        edit_date = bib_rec.edit_date
    WHERE id = bid;

    RETURN aid;

END;
$func$ LANGUAGE PLPGSQL;


-- DATA
-- Disabled by default
INSERT INTO config.global_flag (name, enabled, label) VALUES (
    'ingest.disable_authority_auto_update_bib_meta',  FALSE, 
    oils_i18n_gettext(
        'ingest.disable_authority_auto_update_bib_meta',
        'Authority Automation: Disable automatic authority updates ' ||
            'from modifying bib record editor and edit_date',
        'cgf',
        'label'
    )
);


COMMIT;

