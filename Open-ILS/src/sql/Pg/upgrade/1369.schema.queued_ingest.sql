BEGIN;

SELECT evergreen.upgrade_deps_block_check('1369', :eg_version);

INSERT INTO config.global_flag (name, enabled, label) VALUES (
    'ingest.queued.max_threads',  TRUE,
    oils_i18n_gettext(
        'ingest.queued.max_threads',
        'Queued Ingest: Maximum number of database workers allowed for queued ingest processes',
        'cgf',
        'label'
    )),(
    'ingest.queued.abort_on_error',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.abort_on_error',
        'Queued Ingest: Abort transaction on ingest error rather than simply logging an error',
        'cgf',
        'label'
    )),(
    'ingest.queued.authority.propagate',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.authority.propagate',
        'Queued Ingest: Queue all bib record updates on authority change propagation, even if bib queuing is not generally enabled',
        'cgf',
        'label'
    )),(
    'ingest.queued.all',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.all',
        'Queued Ingest: Use Queued Ingest for all bib and authority record ingest',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.all',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.biblio.all',
        'Queued Ingest: Use Queued Ingest for all bib record ingest',
        'cgf',
        'label'
    )),(
    'ingest.queued.authority.all',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.authority.all',
        'Queued Ingest: Use Queued Ingest for all authority record ingest',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.insert.marc_edit_inline',  TRUE,
    oils_i18n_gettext(
        'ingest.queued.biblio.insert.marc_edit_inline',
        'Queued Ingest: Do NOT use Queued Ingest when creating a new bib, or undeleting a bib, via the MARC editor',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.insert',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.biblio.insert',
        'Queued Ingest: Use Queued Ingest for bib record ingest on insert and undelete',
        'cgf',
        'label'
    )),(
    'ingest.queued.authority.insert',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.authority.insert',
        'Queued Ingest: Use Queued Ingest for authority record ingest on insert and undelete',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.update.marc_edit_inline',  TRUE,
    oils_i18n_gettext(
        'ingest.queued.biblio.update.marc_edit_inline',
        'Queued Ingest: Do NOT Use Queued Ingest when editing bib records via the MARC Editor',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.update',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.biblio.update',
        'Queued Ingest: Use Queued Ingest for bib record ingest on update',
        'cgf',
        'label'
    )),(
    'ingest.queued.authority.update',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.authority.update',
        'Queued Ingest: Use Queued Ingest for authority record ingest on update',
        'cgf',
        'label'
    )),(
    'ingest.queued.biblio.delete',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.biblio.delete',
        'Queued Ingest: Use Queued Ingest for bib record ingest on delete',
        'cgf',
        'label'
    )),(
    'ingest.queued.authority.delete',  FALSE,
    oils_i18n_gettext(
        'ingest.queued.authority.delete',
        'Queued Ingest: Use Queued Ingest for authority record ingest on delete',
        'cgf',
        'label'
    )
);

UPDATE config.global_flag SET value = '20' WHERE name = 'ingest.queued.max_threads';

CREATE OR REPLACE FUNCTION search.symspell_maintain_entries () RETURNS TRIGGER AS $f$
DECLARE
    search_class    TEXT;
    new_value       TEXT := NULL;
    old_value       TEXT := NULL;
    _atag           INTEGER;
BEGIN

    IF TG_TABLE_SCHEMA = 'authority' THEN
        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            _atag = NEW.atag;
        ELSE
            _atag = OLD.atag;
        END IF;

        SELECT  m.field_class INTO search_class
          FROM  authority.control_set_auth_field_metabib_field_map_refs a
                JOIN config.metabib_field m ON (a.metabib_field=m.id)
          WHERE a.authority_field = _atag;

        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    ELSE
        search_class := COALESCE(TG_ARGV[0], SPLIT_PART(TG_TABLE_NAME,'_',1));
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        new_value := NEW.value;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        old_value := OLD.value;
    END IF;

    IF new_value = old_value THEN
        -- same, move along
    ELSE
        INSERT INTO search.symspell_dictionary_updates
            SELECT  txid_current(), *
              FROM  search.symspell_build_entries(
                        new_value,
                        search_class,
                        old_value
                    );
    END IF;

    -- PERFORM * FROM search.symspell_build_and_merge_entries(new_value, search_class, old_value);

    RETURN NULL; -- always fired AFTER
END;
$f$ LANGUAGE PLPGSQL;

CREATE TABLE action.ingest_queue (
    id          SERIAL      PRIMARY KEY,
    created     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    who         INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    start_time  TIMESTAMPTZ,
    end_time    TIMESTAMPTZ,
    threads     INT,
    why         TEXT
);

CREATE TABLE action.ingest_queue_entry (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL, -- points to a record id of the appropriate record_type
    record_type TEXT        NOT NULL,
    action      TEXT        NOT NULL,
    run_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    state_data  TEXT        NOT NULL DEFAULT '',
    queue       INT         REFERENCES action.ingest_queue (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    override_by BIGINT      REFERENCES action.ingest_queue_entry (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ingest_time TIMESTAMPTZ,
    fail_time   TIMESTAMPTZ
);
CREATE UNIQUE INDEX record_pending_once ON action.ingest_queue_entry (record_type,record,state_data) WHERE ingest_time IS NULL AND override_by IS NULL;
CREATE INDEX entry_override_by_idx ON action.ingest_queue_entry (override_by) WHERE override_by IS NOT NULL;

CREATE OR REPLACE FUNCTION action.enqueue_ingest_entry (
    record_id       BIGINT,
    rtype           TEXT DEFAULT 'biblio',
    when_to_run     TIMESTAMPTZ DEFAULT NOW(),
    queue_id        INT  DEFAULT NULL,
    ingest_action   TEXT DEFAULT 'update', -- will be the most common?
    old_state_data  TEXT DEFAULT ''
) RETURNS BOOL AS $F$
DECLARE
    new_entry       action.ingest_queue_entry%ROWTYPE;
    prev_del_entry  action.ingest_queue_entry%ROWTYPE;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    IF ingest_action = 'delete' THEN
        -- first see if there is an outstanding entry
        SELECT  * INTO prev_del_entry
          FROM  action.ingest_queue_entry
          WHERE qe.record = record_id
                AND qe.state_date = old_state_data
                AND qe.record_type = rtype
                AND qe.ingest_time IS NULL
                AND qe.override_by IS NULL;
    END IF;

    WITH existing_queue_entry_cte AS (
        SELECT  queue_id AS queue,
                rtype AS record_type,
                record_id AS record,
                qe.id AS override_by,
                ingest_action AS action,
                q.run_at AS run_at,
                old_state_data AS state_data
          FROM  action.ingest_queue_entry qe
                JOIN action.ingest_queue q ON (qe.queue = q.id)
          WHERE qe.record = record_id
                AND q.end_time IS NULL
                AND qe.record_type = rtype
                AND qe.state_data = old_state_data
                AND qe.ingest_time IS NULL
                AND qe.fail_time IS NULL
                AND qe.override_by IS NULL
    ), existing_nonqueue_entry_cte AS (
        SELECT  queue_id AS queue,
                rtype AS record_type,
                record_id AS record,
                qe.id AS override_by,
                ingest_action AS action,
                qe.run_at AS run_at,
                old_state_data AS state_data
          FROM  action.ingest_queue_entry qe
          WHERE qe.record = record_id
                AND qe.queue IS NULL
                AND qe.record_type = rtype
                AND qe.state_data = old_state_data
                AND qe.ingest_time IS NULL
                AND qe.fail_time IS NULL
                AND qe.override_by IS NULL
    ), new_entry_cte AS (
        SELECT * FROM existing_queue_entry_cte
          UNION ALL
        SELECT * FROM existing_nonqueue_entry_cte
          UNION ALL
        SELECT queue_id, rtype, record_id, NULL, ingest_action, COALESCE(when_to_run,NOW()), old_state_data
    ), insert_entry_cte AS (
        INSERT INTO action.ingest_queue_entry
            (queue, record_type, record, override_by, action, run_at, state_data)
          SELECT queue, record_type, record, override_by, action, run_at, state_data FROM new_entry_cte
            ORDER BY 4 NULLS LAST, 6
            LIMIT 1
        RETURNING *
    ) SELECT * INTO new_entry FROM insert_entry_cte;

    IF prev_del_entry.id IS NOT NULL THEN -- later delete overrides earlier unapplied entry
        UPDATE  action.ingest_queue_entry
          SET   override_by = new_entry.id
          WHERE id = prev_del_entry.id;

        UPDATE  action.ingest_queue_entry
          SET   override_by = NULL
          WHERE id = new_entry.id;

    ELSIF new_entry.override_by IS NOT NULL THEN
        RETURN TRUE; -- already handled, don't notify
    END IF;

    NOTIFY queued_ingest;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.process_ingest_queue_entry (qeid BIGINT) RETURNS BOOL AS $func$
DECLARE
    ingest_success  BOOL := NULL;
    qe              action.ingest_queue_entry%ROWTYPE;
    aid             authority.record_entry.id%TYPE;
BEGIN

    SELECT * INTO qe FROM action.ingest_queue_entry WHERE id = qeid;
    IF qe.ingest_time IS NOT NULL OR qe.override_by IS NOT NULL THEN
        RETURN TRUE; -- Already done
    END IF;

    IF qe.action = 'delete' THEN
        IF qe.record_type = 'biblio' THEN
            SELECT metabib.indexing_delete(r.*, qe.state_data) INTO ingest_success FROM biblio.record_entry r WHERE r.id = qe.record;
        ELSIF qe.record_type = 'authority' THEN
            SELECT authority.indexing_delete(r.*, qe.state_data) INTO ingest_success FROM authority.record_entry r WHERE r.id = qe.record;
        END IF;
    ELSE
        IF qe.record_type = 'biblio' THEN
            IF qe.action = 'propagate' THEN
                SELECT authority.apply_propagate_changes(qe.state_data::BIGINT, qe.record) INTO aid;
                SELECT aid = qe.state_data::BIGINT INTO ingest_success;
            ELSE
                SELECT metabib.indexing_update(r.*, qe.action = 'insert', qe.state_data) INTO ingest_success FROM biblio.record_entry r WHERE r.id = qe.record;
            END IF;
        ELSIF qe.record_type = 'authority' THEN
            SELECT authority.indexing_update(r.*, qe.action = 'insert', qe.state_data) INTO ingest_success FROM authority.record_entry r WHERE r.id = qe.record;
        END IF;
    END IF;

    IF NOT ingest_success THEN
        UPDATE action.ingest_queue_entry SET fail_time = NOW() WHERE id = qe.id;
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.queued.abort_on_error' AND enabled;
        IF FOUND THEN
            RAISE EXCEPTION 'Ingest action of % on %.record_entry % for queue entry % failed', qe.action, qe.record_type, qe.record, qe.id;
        ELSE
            RAISE WARNING 'Ingest action of % on %.record_entry % for queue entry % failed', qe.action, qe.record_type, qe.record, qe.id;
        END IF;
    ELSE
        UPDATE action.ingest_queue_entry SET ingest_time = NOW() WHERE id = qe.id;
    END IF;

    RETURN ingest_success;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.complete_duplicated_entries () RETURNS TRIGGER AS $F$
BEGIN
    IF NEW.ingest_time IS NOT NULL THEN
        UPDATE action.ingest_queue_entry SET ingest_time = NEW.ingest_time WHERE override_by = NEW.id;
    END IF;

    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;

CREATE TRIGGER complete_duplicated_entries_trigger
    AFTER UPDATE ON action.ingest_queue_entry
    FOR EACH ROW WHEN (NEW.override_by IS NULL)
    EXECUTE PROCEDURE action.complete_duplicated_entries();

CREATE OR REPLACE FUNCTION action.set_ingest_queue(INT) RETURNS VOID AS $$
    $_SHARED{"ingest_queue_id"} = $_[0];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.get_ingest_queue() RETURNS INT AS $$
    return $_SHARED{"ingest_queue_id"};
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.clear_ingest_queue() RETURNS VOID AS $$
    delete($_SHARED{"ingest_queue_id"});
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.set_queued_ingest_force(TEXT) RETURNS VOID AS $$
    $_SHARED{"ingest_queue_force"} = $_[0];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.get_queued_ingest_force() RETURNS TEXT AS $$
    return $_SHARED{"ingest_queue_force"};
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.clear_queued_ingest_force() RETURNS VOID AS $$
    delete($_SHARED{"ingest_queue_force"});
$$ LANGUAGE plperlu;

------------------ ingest functions ------------------

CREATE OR REPLACE FUNCTION metabib.indexing_delete (bib biblio.record_entry, extra TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    tmp_bool BOOL;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
    tmp_bool := FOUND;

    PERFORM metabib.remap_metarecord_for_bib(bib.id, bib.fingerprint, TRUE, tmp_bool);

    IF NOT tmp_bool THEN
        -- One needs to keep these around to support searches
        -- with the #deleted modifier, so one should turn on the named
        -- internal flag for that functionality.
        DELETE FROM metabib.record_attr_vector_list WHERE source = bib.id;
    END IF;

    DELETE FROM authority.bib_linking abl WHERE abl.bib = bib.id; -- Avoid updating fields in bibs that are no longer visible
    DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = bib.id; -- Separate any multi-homed items
    DELETE FROM metabib.browse_entry_def_map WHERE source = bib.id; -- Don't auto-suggest deleted bibs

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.indexing_update (bib biblio.record_entry, insert_only BOOL DEFAULT FALSE, extra TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    skip_facet   BOOL   := FALSE;
    skip_display BOOL   := FALSE;
    skip_browse  BOOL   := FALSE;
    skip_search  BOOL   := FALSE;
    skip_auth    BOOL   := FALSE;
    skip_full    BOOL   := FALSE;
    skip_attrs   BOOL   := FALSE;
    skip_luri    BOOL   := FALSE;
    skip_mrmap   BOOL   := FALSE;
    only_attrs   TEXT[] := NULL;
    only_fields  INT[]  := '{}'::INT[];
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    -- Record authority linking
    SELECT extra LIKE '%skip_authority%' INTO skip_auth;
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND AND NOT skip_auth THEN
        PERFORM biblio.map_authority_linking( bib.id, bib.marc );
    END IF;

    -- Flatten and insert the mfr data
    SELECT extra LIKE '%skip_full_rec%' INTO skip_full;
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND AND NOT skip_full THEN
        PERFORM metabib.reingest_metabib_full_rec(bib.id);
    END IF;

    -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
    SELECT extra LIKE '%skip_attrs%' INTO skip_attrs;
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
    IF NOT FOUND AND NOT skip_attrs THEN
        IF extra ~ 'attr\(\s*(\w[ ,\w]*?)\s*\)' THEN
            SELECT REGEXP_SPLIT_TO_ARRAY(
                (REGEXP_MATCHES(extra, 'attr\(\s*(\w[ ,\w]*?)\s*\)'))[1],
                '\s*,\s*'
            ) INTO only_attrs;
        END IF;

        PERFORM metabib.reingest_record_attributes(bib.id, only_attrs, bib.marc, insert_only);
    END IF;

    -- Gather and insert the field entry data
    SELECT extra LIKE '%skip_facet%' INTO skip_facet;
    SELECT extra LIKE '%skip_display%' INTO skip_display;
    SELECT extra LIKE '%skip_browse%' INTO skip_browse;
    SELECT extra LIKE '%skip_search%' INTO skip_search;

    IF extra ~ 'field_list\(\s*(\d[ ,\d]+)\s*\)' THEN
        SELECT REGEXP_SPLIT_TO_ARRAY(
            (REGEXP_MATCHES(extra, 'field_list\(\s*(\d[ ,\d]+)\s*\)'))[1],
            '\s*,\s*'
        )::INT[] INTO only_fields;
    END IF;

    IF NOT skip_facet OR NOT skip_display OR NOT skip_browse OR NOT skip_search THEN
        PERFORM metabib.reingest_metabib_field_entries(bib.id, skip_facet, skip_display, skip_browse, skip_search, only_fields);
    END IF;

    -- Located URI magic
    SELECT extra LIKE '%skip_luri%' INTO skip_luri;
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
    IF NOT FOUND AND NOT skip_luri THEN PERFORM biblio.extract_located_uris( bib.id, bib.marc, bib.editor ); END IF;

    -- (re)map metarecord-bib linking
    SELECT extra LIKE '%skip_mrmap%' INTO skip_mrmap;
    IF insert_only THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND AND NOT skip_mrmap THEN
            PERFORM metabib.remap_metarecord_for_bib( bib.id, bib.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND AND NOT skip_mrmap THEN
            PERFORM metabib.remap_metarecord_for_bib( bib.id, bib.fingerprint );
        END IF;
    END IF;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.indexing_delete (auth authority.record_entry, extra TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    tmp_bool BOOL;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN
    DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
    DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
    DELETE FROM authority.simple_heading WHERE record = NEW.id;
      -- Should remove matching $0 from controlled fields at the same time?

    -- XXX What do we about the actual linking subfields present in
    -- authority records that target this one when this happens?
    DELETE FROM authority.authority_linking WHERE source = NEW.id OR target = NEW.id;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION authority.indexing_update (auth authority.record_entry, insert_only BOOL DEFAULT FALSE, old_heading TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    -- Unless there's a setting stopping us, propagate these updates to any linked bib records when the heading changes
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;

    IF NOT FOUND AND auth.heading <> old_heading THEN
        PERFORM authority.propagate_changes(auth.id);
    END IF;

    IF NOT insert_only THEN
        DELETE FROM authority.authority_linking WHERE source = auth.id;
        DELETE FROM authority.simple_heading WHERE record = auth.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            auth.id, auth.control_set, auth.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(auth.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value,thesaurus)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value, ashs.thesaurus);
            ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        SELECT INTO mbe_row * FROM metabib.browse_entry
            WHERE value = ashs.value AND sort_value = ashs.sort_value;

        IF FOUND THEN
            mbe_id := mbe_row.id;
        ELSE
            INSERT INTO metabib.browse_entry
                ( value, sort_value ) VALUES
                ( ashs.value, ashs.sort_value );

            mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
        END IF;

        INSERT INTO metabib.browse_entry_simple_heading_map (entry,simple_heading) VALUES (mbe_id,ash_id);

    END LOOP;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(auth.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(auth.id);
        END IF;
    END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
    IF NOT FOUND THEN
        PERFORM search.symspell_dictionary_reify();
    END IF;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    old_state_data      TEXT := '';
    new_action          TEXT;
    queuing_force       TEXT;
    queuing_flag_name   TEXT;
    queuing_flag        BOOL := FALSE;
    queuing_success     BOOL := FALSE;
    ingest_success      BOOL := FALSE;
    ingest_queue        INT;
BEGIN

    -- Identify the ingest action type
    IF TG_OP = 'UPDATE' THEN

        -- Gather type-specific data for later use
        IF TG_TABLE_SCHEMA = 'authority' THEN
            old_state_data = OLD.heading;
        END IF;

        IF NOT OLD.deleted THEN -- maybe reingest?
            IF NEW.deleted THEN
                new_action = 'delete'; -- nope, delete
            ELSE
                new_action = 'update'; -- yes, update
            END IF;
        ELSIF NOT NEW.deleted THEN
            new_action = 'insert'; -- revivify, AKA insert
        ELSE
            RETURN NEW; -- was and is still deleted, don't ingest
        END IF;
    ELSIF TG_OP = 'INSERT' THEN
        new_action = 'insert'; -- brand new
    ELSE
        RETURN OLD; -- really deleting the record
    END IF;

    queuing_flag_name := 'ingest.queued.'||TG_TABLE_SCHEMA||'.'||new_action;
    -- See if we should be queuing anything
    SELECT  enabled INTO queuing_flag
      FROM  config.internal_flag
      WHERE name IN ('ingest.queued.all','ingest.queued.'||TG_TABLE_SCHEMA||'.all', queuing_flag_name)
            AND enabled
      LIMIT 1;

    SELECT action.get_queued_ingest_force() INTO queuing_force;
    IF queuing_flag IS NULL AND queuing_force = queuing_flag_name THEN
        queuing_flag := TRUE;
    END IF;

    -- you (or part of authority propagation) can forcibly disable specific queuing actions
    IF queuing_force = queuing_flag_name||'.disabled' THEN
        queuing_flag := FALSE;
    END IF;

    -- And if we should be queuing ...
    IF queuing_flag THEN
        ingest_queue := action.get_ingest_queue();

        -- ... but this is NOT a named or forced queue request (marc editor update, say, or vandelay overlay)...
        IF queuing_force IS NULL AND ingest_queue IS NULL AND new_action = 'update' THEN -- re-ingest?

            PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

            --  ... then don't do anything if ingest.reingest.force_on_same_marc is not enabled and the MARC hasn't changed
            IF NOT FOUND AND OLD.marc = NEW.marc THEN
                RETURN NEW;
            END IF;
        END IF;

        -- Otherwise, attempt to enqueue
        SELECT action.enqueue_ingest_entry( NEW.id, TG_TABLE_SCHEMA, NOW(), ingest_queue, new_action, old_state_data) INTO queuing_success;
    END IF;

    -- If queuing was not requested, or failed for some reason, do it live.
    IF NOT queuing_success THEN
        IF queuing_flag THEN
            RAISE WARNING 'Enqueuing of %.record_entry % for ingest failed, attempting direct ingest', TG_TABLE_SCHEMA, NEW.id;
        END IF;

        IF new_action = 'delete' THEN
            IF TG_TABLE_SCHEMA = 'biblio' THEN
                SELECT metabib.indexing_delete(NEW.*, old_state_data) INTO ingest_success;
            ELSIF TG_TABLE_SCHEMA = 'authority' THEN
                SELECT authority.indexing_delete(NEW.*, old_state_data) INTO ingest_success;
            END IF;
        ELSE
            IF TG_TABLE_SCHEMA = 'biblio' THEN
                SELECT metabib.indexing_update(NEW.*, new_action = 'insert', old_state_data) INTO ingest_success;
            ELSIF TG_TABLE_SCHEMA = 'authority' THEN
                SELECT authority.indexing_update(NEW.*, new_action = 'insert', old_state_data) INTO ingest_success;
            END IF;
        END IF;
        
        IF NOT ingest_success THEN
            PERFORM * FROM config.internal_flag WHERE name = 'ingest.queued.abort_on_error' AND enabled;
            IF FOUND THEN
                RAISE EXCEPTION 'Ingest of %.record_entry % failed', TG_TABLE_SCHEMA, NEW.id;
            ELSE
                RAISE WARNING 'Ingest of %.record_entry % failed', TG_TABLE_SCHEMA, NEW.id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP TRIGGER aaa_indexing_ingest_or_delete ON biblio.record_entry;
DROP TRIGGER aaa_auth_ingest_or_delete ON authority.record_entry;

CREATE TRIGGER aaa_indexing_ingest_or_delete AFTER INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.indexing_ingest_or_delete ();
CREATE TRIGGER aaa_auth_ingest_or_delete AFTER INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.indexing_ingest_or_delete ();

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         TEXT;
    tmp_array       TEXT[];
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
    jump_past       BOOL;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition
        WHERE (
            tag IS NOT NULL OR
            fixed_field IS NOT NULL OR
            xpath IS NOT NULL OR
            phys_char_sf IS NOT NULL OR
            composite
        ) AND (
            filter OR sorter
        );
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        jump_past := FALSE; -- This gets set when we are non-multi and have found something
        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1;

        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY_AGG(value) INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
                    AND tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL
                            THEN POSITION(subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                    END
              GROUP BY tag
              ORDER BY tag;

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[ARRAY_TO_STRING(attr_value, COALESCE(attr_def.joiner,' '))];
                jump_past := TRUE;
            END IF;
        END IF;

        IF NOT jump_past AND attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := attr_value || vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
                jump_past := TRUE;
            END IF;
        END IF;

        IF NOT jump_past AND attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;

                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT UNNEST(oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]])) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;
        END IF;

        IF NOT jump_past AND attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO tmp_array
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            attr_value := attr_value || tmp_array;

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND tmp_val <> '' THEN
                -- note that a string that contains only blanks
                -- is a valid value for some attributes
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;

        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            IF norm_attr_value[1] IS NOT NULL THEN
                INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
            END IF;
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

    IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN
        SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
        SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
        attr_vector := attr_vector || attr_vector_tmp;
    END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector)
            ON CONFLICT (source) DO UPDATE SET vlist = EXCLUDED.vlist;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.propagate_changes
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    queuing_success BOOL := FALSE;
BEGIN

    PERFORM 1 FROM config.global_flag
        WHERE name IN ('ingest.queued.all','ingest.queued.authority.propagate')
            AND enabled;

    IF FOUND THEN
        -- XXX enqueue special 'propagate' bib action
        SELECT action.enqueue_ingest_entry( bid, 'biblio', NOW(), NULL, 'propagate', aid::TEXT) INTO queuing_success;

        IF queuing_success THEN
            RETURN aid;
        END IF;
    END IF;

    PERFORM authority.apply_propagate_changes(aid, bid);
    RETURN aid;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.apply_propagate_changes
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    bib_forced  BOOL := FALSE;
    bib_rec     biblio.record_entry%ROWTYPE;
    new_marc    TEXT;
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

    PERFORM action.set_queued_ingest_force('ingest.queued.biblio.update.disabled');

    UPDATE biblio.record_entry SET
        marc = new_marc,
        editor = bib_rec.editor,
        edit_date = bib_rec.edit_date
    WHERE id = bid;

    PERFORM action.clear_queued_ingest_force();

    RETURN aid;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries(
    bib_id BIGINT,
    skip_facet BOOL DEFAULT FALSE,
    skip_display BOOL DEFAULT FALSE,
    skip_browse BOOL DEFAULT FALSE,
    skip_search BOOL DEFAULT FALSE,
    only_fields INT[] DEFAULT '{}'::INT[]
) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_display    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
    field_list      INT[] := only_fields;
    field_types     TEXT[] := '{}'::TEXT[];
BEGIN

    IF field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO field_list FROM config.metabib_field;
    END IF;

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_display, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_display_indexing' AND enabled)) INTO b_skip_display;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    IF NOT b_skip_facet THEN field_types := field_types || '{facet}'; END IF;
    IF NOT b_skip_display THEN field_types := field_types || '{display}'; END IF;
    IF NOT b_skip_browse THEN field_types := field_types || '{browse}'; END IF;
    IF NOT b_skip_search THEN field_types := field_types || '{search}'; END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id || $$ AND field = ANY($1)$$ USING field_list;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id AND def = ANY(field_list);
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id, ' ', field_types, field_list ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.display_field AND NOT b_skip_display THEN
            INSERT INTO metabib.display_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;


        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            IF ind_data.browse_nocase THEN -- for "nocase" browse definions, look for a preexisting row that matches case-insensitively on value and use that
                SELECT INTO mbe_row * FROM metabib.browse_entry
                    WHERE evergreen.lowercase(value) = evergreen.lowercase(value_prepped) AND sort_value = ind_data.sort_value
                    ORDER BY sort_value, value LIMIT 1; -- gotta pick something, I guess
            END IF;

            IF mbe_row.id IS NOT NULL THEN -- asked to check for, and found, a "nocase" version to use
                mbe_id := mbe_row.id;
            ELSE -- otherwise, an UPSERT-protected variant
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value )
                  ON CONFLICT (sort_value, value) DO UPDATE SET sort_value = EXCLUDED.sort_value -- must update a row to return an existing id
                  RETURNING id INTO mbe_id;
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
        IF NOT FOUND THEN
            PERFORM search.symspell_dictionary_reify();
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- get rid of old version
DROP FUNCTION authority.indexing_ingest_or_delete;

COMMIT;

