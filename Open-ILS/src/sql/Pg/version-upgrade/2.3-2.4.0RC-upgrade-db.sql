--Upgrade Script for 2.3 to 2.4.0RC
\set eg_version '''2.4.0RC'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.4.0RC', :eg_version);
-- remove the Bypass hold capture during clear shelf process setting

SELECT evergreen.upgrade_deps_block_check('0739', :eg_version);


DELETE FROM actor.org_unit_setting WHERE name = 'circ.holds.clear_shelf.no_capture_holds';
DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'circ.holds.clear_shelf.no_capture_holds';


DELETE FROM config.org_unit_setting_type WHERE name = 'circ.holds.clear_shelf.no_capture_holds';


SELECT evergreen.upgrade_deps_block_check('0741', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    540,
    'ADMIN_TOOLBAR_FOR_ORG',
    oils_i18n_gettext(
        540,
        'Allows a user to create, edit, and delete custom toolbars for org units',
        'ppl',
        'description'
    )
), (
    541,
    'ADMIN_TOOLBAR_FOR_WORKSTATION',
    oils_i18n_gettext(
        541,
        'Allows a user to create, edit, and delete custom toolbars for workstations',
        'ppl',
        'description'
    )
), (
    542,
    'ADMIN_TOOLBAR_FOR_USER',
    oils_i18n_gettext(
        542,
        'Allows a user to create, edit, and delete custom toolbars for users',
        'ppl',
        'description'
    )
);


-- Evergreen DB patch 0743.schema.remove_tsearch2.sql
--
-- Enable native full-text search to be used, and drop TSearch2 extension
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0743', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- First up, these functions depend on metabib.full_rec. They have to go for now.
DROP FUNCTION IF EXISTS biblio.flatten_marc(bigint);
DROP FUNCTION IF EXISTS biblio.flatten_marc(text);

-- These views depend on metabib.full_rec as well. Bye-bye!
DROP VIEW IF EXISTS reporter.old_super_simple_record;
DROP VIEW IF EXISTS reporter.simple_record;
DROP VIEW IF EXISTS reporter.classic_item_list;

\echo WARNING: The reporter.classic_item_list view was dropped if it existed.
\echo If you use that view, please run the example.reporter-extension.sql script
\echo to recreate it after rest of the schema upgrade is complete.

-- Now we can drop metabib.full_rec.
DROP VIEW IF EXISTS metabib.full_rec;

-- These indexes have to go. BEFORE we alter the tables, otherwise things take extra time when we alter the tables.
DROP INDEX metabib.metabib_author_field_entry_value_idx;
DROP INDEX metabib.metabib_identifier_field_entry_value_idx;
DROP INDEX metabib.metabib_keyword_field_entry_value_idx;
DROP INDEX metabib.metabib_series_field_entry_value_idx;
DROP INDEX metabib.metabib_subject_field_entry_value_idx;
DROP INDEX metabib.metabib_title_field_entry_value_idx;

-- Now grab all of the tsvector-enabled columns and switch them to the non-wrapper version of the type.
ALTER TABLE authority.full_rec ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE authority.simple_heading ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.real_full_rec ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.author_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.browse_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.identifier_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.keyword_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.series_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.subject_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;
ALTER TABLE metabib.title_field_entry ALTER COLUMN index_vector TYPE pg_catalog.tsvector;

-- Make sure that tsearch2 exists as an extension (for a sufficiently
-- old Evergreen database, it might still be an unpackaged contrib).
CREATE EXTENSION IF NOT EXISTS tsearch2 SCHEMA public FROM unpackaged;
-- Halfway there! Goodbye tsearch2 extension!
DROP EXTENSION tsearch2;

-- Next up, re-creating all of the stuff we just dropped.

-- Indexes! Note to whomever: Do we even need these anymore?
CREATE INDEX metabib_author_field_entry_value_idx ON metabib.author_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_identifier_field_entry_value_idx ON metabib.identifier_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_keyword_field_entry_value_idx ON metabib.keyword_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_series_field_entry_value_idx ON metabib.series_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_subject_field_entry_value_idx ON metabib.subject_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_title_field_entry_value_idx ON metabib.title_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;

-- metabib.full_rec, with insert/update/delete rules
CREATE OR REPLACE VIEW metabib.full_rec AS
    SELECT  id,
            record,
            tag,
            ind1,
            ind2,
            subfield,
            SUBSTRING(value,1,1024) AS value,
            index_vector
      FROM  metabib.real_full_rec;

CREATE OR REPLACE RULE metabib_full_rec_insert_rule
    AS ON INSERT TO metabib.full_rec
    DO INSTEAD
    INSERT INTO metabib.real_full_rec VALUES (
        COALESCE(NEW.id, NEXTVAL('metabib.full_rec_id_seq'::REGCLASS)),
        NEW.record,
        NEW.tag,
        NEW.ind1,
        NEW.ind2,
        NEW.subfield,
        NEW.value,
        NEW.index_vector
    );

CREATE OR REPLACE RULE metabib_full_rec_update_rule
    AS ON UPDATE TO metabib.full_rec
    DO INSTEAD
    UPDATE  metabib.real_full_rec SET
        id = NEW.id,
        record = NEW.record,
        tag = NEW.tag,
        ind1 = NEW.ind1,
        ind2 = NEW.ind2,
        subfield = NEW.subfield,
        value = NEW.value,
        index_vector = NEW.index_vector
      WHERE id = OLD.id;

CREATE OR REPLACE RULE metabib_full_rec_delete_rule
    AS ON DELETE TO metabib.full_rec
    DO INSTEAD
    DELETE FROM metabib.real_full_rec WHERE id = OLD.id;

-- reporter views that depended on metabib.full_rec are up next
CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT  r.id,
    s.metarecord,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    title.value AS title,
    uniform_title.value AS uniform_title,
    author.value AS author,
    publisher.value AS publisher,
    SUBSTRING(pubdate.value FROM $$\d+$$) AS pubdate,
    series_title.value AS series_title,
    series_statement.value AS series_statement,
    summary.value AS summary,
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
    ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
    ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM  biblio.record_entry r
    JOIN metabib.metarecord_source_map s ON (s.source = r.id)
    LEFT JOIN metabib.full_rec uniform_title ON (r.id = uniform_title.record AND uniform_title.tag = '240' AND uniform_title.subfield = 'a')
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag = '100' AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
    LEFT JOIN metabib.full_rec series_title ON (r.id = series_title.record AND series_title.tag IN ('830','440') AND series_title.subfield = 'a')
    LEFT JOIN metabib.full_rec series_statement ON (r.id = series_statement.record AND series_statement.tag = '490' AND series_statement.subfield = 'a')
    LEFT JOIN metabib.full_rec summary ON (r.id = summary.record AND summary.tag = '520' AND summary.subfield = 'a')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT publisher.value), ', ') AS publisher,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$) ), ', ') AS pubdate,
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

-- And finally, the biblio functions. NOTE: I can't find the original source of the second one, so I skipped it as old cruft that was in our production DB.
CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
    bib biblio.record_entry%ROWTYPE;
    output  metabib.full_rec%ROWTYPE;
    field   RECORD;
BEGIN
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    FOR field IN SELECT * FROM vandelay.flatten_marc( bib.marc ) LOOP
        output.record := rid;
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        output.value := field.value;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- Evergreen DB patch 0745.data.prewarn_expire_setting.sql
--
-- Configuration setting to warn staff when an account is about to expire
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0745', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.patron_expires_soon_warning',
        'circ',
        oils_i18n_gettext(
            'circ.patron_expires_soon_warning',
            'Warn when patron account is about to expire',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.patron_expires_soon_warning',
            'Warn when patron account is about to expire. If set, the staff client displays a warning this many days before the expiry of a patron account. Value is in number of days, for example: 3 for 3 days.',
            'coust',
            'description'
        ),
        'integer'
    );

-- LP1076399: Prevent reactivated holds from canceling immediately.
-- Set the expire_time to NULL on all frozen/suspended holds.

SELECT evergreen.upgrade_deps_block_check('0747', :eg_version);

UPDATE action.hold_request
SET expire_time = NULL
WHERE frozen = 't'; 


SELECT evergreen.upgrade_deps_block_check('0752', :eg_version);

INSERT INTO container.biblio_record_entry_bucket_type (code, label) VALUES ('url_verify', 'URL Verification Queue');

DROP SCHEMA IF EXISTS url_verify CASCADE;

CREATE SCHEMA url_verify;

CREATE TABLE url_verify.session (
    id          SERIAL                      PRIMARY KEY,
    name        TEXT                        NOT NULL,
    owning_lib  INT                         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    container   INT                         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    search      TEXT                        NOT NULL,
    CONSTRAINT uvs_name_once_per_lib UNIQUE (name, owning_lib)
);

CREATE TABLE url_verify.url_selector (
    id      SERIAL  PRIMARY KEY,
    xpath   TEXT    NOT NULL,
    session INT     NOT NULL REFERENCES url_verify.session (id) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT tag_once_per_sess UNIQUE (xpath, session)
);

CREATE TABLE url_verify.url (
    id              SERIAL  PRIMARY KEY,
    redirect_from   INT     REFERENCES url_verify.url(id) DEFERRABLE INITIALLY DEFERRED,
    item            INT     REFERENCES container.biblio_record_entry_bucket_item (id) DEFERRABLE INITIALLY DEFERRED,
    url_selector    INT     REFERENCES url_verify.url_selector (id) DEFERRABLE INITIALLY DEFERRED,
    session         INT     REFERENCES url_verify.session (id) DEFERRABLE INITIALLY DEFERRED,
    tag             TEXT,
    subfield        TEXT,
    ord             INT,
    full_url        TEXT    NOT NULL,
    scheme          TEXT,
    username        TEXT,
    password        TEXT,
    host            TEXT,
    domain          TEXT,
    tld             TEXT,
    port            TEXT,
    path            TEXT,
    page            TEXT,
    query           TEXT,
    fragment        TEXT,
    CONSTRAINT redirect_or_from_item CHECK (
        redirect_from IS NOT NULL OR (
            item         IS NOT NULL AND
            url_selector IS NOT NULL AND
            tag          IS NOT NULL AND
            subfield     IS NOT NULL AND
            ord          IS NOT NULL
        )
    )
);

CREATE TABLE url_verify.verification_attempt (
    id          SERIAL                      PRIMARY KEY,
    usr         INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    session     INT                         NOT NULL REFERENCES url_verify.session (id) DEFERRABLE INITIALLY DEFERRED,
    start_time  TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    finish_time TIMESTAMP WITH TIME ZONE
);
 
CREATE TABLE url_verify.url_verification (
    id          SERIAL                      PRIMARY KEY,
    url         INT                         NOT NULL REFERENCES url_verify.url (id) DEFERRABLE INITIALLY DEFERRED,
    attempt     INT                         NOT NULL REFERENCES url_verify.verification_attempt (id) DEFERRABLE INITIALLY DEFERRED,
    req_time    TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    res_time    TIMESTAMP WITH TIME ZONE, 
    res_code    INT                         CHECK (res_code BETWEEN 100 AND 999), -- we know > 599 will never be valid HTTP code, but we use 9XX for other stuff
    res_text    TEXT, 
    redirect_to INT                         REFERENCES url_verify.url (id) DEFERRABLE INITIALLY DEFERRED -- if redirected
);

CREATE TABLE config.filter_dialog_interface (
    key         TEXT                        PRIMARY KEY,
    description TEXT
);

CREATE TABLE config.filter_dialog_filter_set (
    id          SERIAL                      PRIMARY KEY,
    name        TEXT                        NOT NULL,
    owning_lib  INT                         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    interface   TEXT                        NOT NULL REFERENCES config.filter_dialog_interface (key) DEFERRABLE INITIALLY DEFERRED,
    filters     TEXT                        NOT NULL CHECK (is_json(filters)),
    CONSTRAINT cfdfs_name_once_per_lib UNIQUE (name, owning_lib)
);
 

SELECT evergreen.upgrade_deps_block_check('0753', :eg_version);

CREATE OR REPLACE FUNCTION url_verify.parse_url (url_in TEXT) RETURNS url_verify.url AS $$

use Rose::URI;

my $url_in = shift;
my $url = Rose::URI->new($url_in);

my %parts = map { $_ => $url->$_ } qw/scheme username password host port path query fragment/;

$parts{full_url} = $url_in;
($parts{domain} = $parts{host}) =~ s/^[^.]+\.//;
($parts{tld} = $parts{domain}) =~ s/(?:[^.]+\.)+//;
($parts{page} = $parts{path}) =~ s#(?:[^/]*/)+##;

return \%parts;

$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION url_verify.ingest_url () RETURNS TRIGGER AS $$
DECLARE
    tmp_row url_verify.url%ROWTYPE;
BEGIN
    SELECT * INTO tmp_row FROM url_verify.parse_url(NEW.full_url);

    NEW.scheme          := tmp_row.scheme;
    NEW.username        := tmp_row.username;
    NEW.password        := tmp_row.password;
    NEW.host            := tmp_row.host;
    NEW.domain          := tmp_row.domain;
    NEW.tld             := tmp_row.tld;
    NEW.port            := tmp_row.port;
    NEW.path            := tmp_row.path;
    NEW.page            := tmp_row.page;
    NEW.query           := tmp_row.query;
    NEW.fragment        := tmp_row.fragment;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER ingest_url_tgr
    BEFORE INSERT ON url_verify.url
    FOR EACH ROW EXECUTE PROCEDURE url_verify.ingest_url(); 

CREATE OR REPLACE FUNCTION url_verify.extract_urls ( session_id INT, item_id INT ) RETURNS INT AS $$
DECLARE
    last_seen_tag TEXT;
    current_tag TEXT;
    current_sf TEXT;
    current_url TEXT;
    current_ord INT;
    current_url_pos INT;
    current_selector url_verify.url_selector%ROWTYPE;
BEGIN
    current_ord := 1;

    FOR current_selector IN SELECT * FROM url_verify.url_selector s WHERE s.session = session_id LOOP
        current_url_pos := 1;
        LOOP
            SELECT  (XPATH(current_selector.xpath || '/text()', b.marc::XML))[current_url_pos]::TEXT INTO current_url
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            EXIT WHEN current_url IS NULL;

            SELECT  (XPATH(current_selector.xpath || '/../@tag', b.marc::XML))[current_url_pos]::TEXT INTO current_tag
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            IF current_tag IS NULL THEN
                current_tag := last_seen_tag;
            ELSE
                last_seen_tag := current_tag;
            END IF;

            SELECT  (XPATH(current_selector.xpath || '/@code', b.marc::XML))[current_url_pos]::TEXT INTO current_sf
              FROM  biblio.record_entry b
                    JOIN container.biblio_record_entry_bucket_item c ON (c.target_biblio_record_entry = b.id)
              WHERE c.id = item_id;

            INSERT INTO url_verify.url (session, item, url_selector, tag, subfield, ord, full_url)
              VALUES ( session_id, item_id, current_selector.id, current_tag, current_sf, current_ord, current_url);

            current_url_pos := current_url_pos + 1;
            current_ord := current_ord + 1;
        END LOOP;
    END LOOP;

    RETURN current_ord - 1;
END;
$$ LANGUAGE PLPGSQL;



-- NOTE: beware the use of bare perm IDs in the update_perm's below and in 
-- the 950 seed data file.  Update before merge to match current perm IDs! XXX


SELECT evergreen.upgrade_deps_block_check('0754', :eg_version);

INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        543, 
        'URL_VERIFY',
        oils_i18n_gettext(
            543, 
            'Allows a user to process and verify ULSs', 
            'ppl', 
            'description'
        )
    );


INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        544, 
        'URL_VERIFY_UPDATE_SETTINGS',
        oils_i18n_gettext(
            544, 
            'Allows a user to configure URL verification org unit settings',
            'ppl', 
            'description'
        )
    );


INSERT INTO permission.perm_list (id, code, description) 
    VALUES ( 
        545, 
        'SAVED_FILTER_DIALOG_FILTERS',
        oils_i18n_gettext(
            545, 
            'Allows users to save and load sets of filters for filter dialogs, available in certain staff interfaces',
            'ppl', 
            'description'
        )
    );


INSERT INTO config.settings_group (name, label)
    VALUES (
        'url_verify',
        oils_i18n_gettext(
            'url_verify',
            'URL Verify',
            'csg',
            'label'
        )
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_delay',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_delay',
            'Number of seconds to wait between URL test attempts.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_delay',
            'Throttling mechanism for batch URL verification runs.  Each running process will wait this number of seconds after a URL test before performing the next.',
            'coust',
            'description'
        ),
        'integer',
        544
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_max_redirects',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_max_redirects',
            'Maximum redirect lookups',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_max_redirects',
            'For URLs returning 3XX redirects, this is the maximum number of redirects we will follow before giving up.',
            'coust',
            'description'
        ),
        'integer',
        544
    );

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.url_verification_max_wait',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.url_verification_max_wait',
            'Maximum wait time (in seconds) for a URL to lookup',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.url_verification_max_wait',
            'If we exceed the wait time, the URL is marked as a "timeout" and the system moves on to the next URL',
            'coust',
            'description'
        ),
        'integer',
        544
    );


INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype, update_perm)
    VALUES (
        'url_verify.verification_batch_size',
        'url_verify',
        oils_i18n_gettext(
            'url_verify.verification_batch_size',
            'Number of URLs to test in parallel',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'url_verify.verification_batch_size',
            'URLs are tested in batches.  This number defines the size of each batch and it directly relates to the number of back-end processes performing URL verification.',
            'coust',
            'description'
        ),
        'integer',
        544
    );


INSERT INTO config.filter_dialog_interface (key, description) VALUES (
    'url_verify',
    oils_i18n_gettext(
        'url_verify',
        'All Link Checker filter dialogs',
        'cfdi',
        'description'
    )
);


INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.url_verify.select_urls',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.select_urls',
        'Link Checker''s URL Selection interface''s saved columns',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.select_urls',
        'Link Checker''s URL Selection interface''s saved columns',
        'cust',
        'description'
    ),
    'string'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.grid_columns.url_verify.review_attempt',
    'gui',
    FALSE,
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.review_attempt',
        'Link Checker''s Review Attempt interface''s saved columns',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.grid_columns.url_verify.review_attempt',
        'Link Checker''s Review Attempt interface''s saved columns',
        'cust',
        'description'
    ),
    'string'
);




SELECT evergreen.upgrade_deps_block_check('0755', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype, fm_class) VALUES
(
    'acq.upload.default.create_po',
    oils_i18n_gettext(
        'acq.upload.default.create_po',
        'Upload Create PO',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.create_po',
        'Create a purchase order by default during ACQ file upload',
        'coust',
        'description'
    ),
   'acq',
    'bool',
    NULL
), (
    'acq.upload.default.activate_po',
    oils_i18n_gettext(
        'acq.upload.default.activate_po',
        'Upload Activate PO',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.activate_po',
        'Activate the purchase order by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.provider',
    oils_i18n_gettext(
        'acq.upload.default.provider',
        'Upload Default Provider',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.provider',
        'Default provider to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'acqpro'
), (
    'acq.upload.default.vandelay.match_set',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.match_set',
        'Upload Default Match Set',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.match_set',
        'Default match set to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vms'
), (
    'acq.upload.default.vandelay.merge_profile',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_profile',
        'Upload Default Merge Profile',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_profile',
        'Default merge profile to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vmp'
), (
    'acq.upload.default.vandelay.import_non_matching',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.import_non_matching',
        'Upload Import Non Matching by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.import_non_matching',
        'Import non-matching records by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_exact',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_exact',
        'Upload Merge on Exact Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_exact',
        'Merge records on exact match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_best',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_best',
        'Upload Merge on Best Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_best',
        'Merge records on best match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_single',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_single',
        'Upload Merge on Single Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_single',
        'Merge records on single match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.quality_ratio',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.quality_ratio',
        'Upload Default Min. Quality Ratio',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.quality_ratio',
        'Default minimum quality ratio used during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'integer',
    NULL
), (
    'acq.upload.default.vandelay.low_quality_fall_thru_profile',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.low_quality_fall_thru_profile',
        'Upload Default Insufficient Quality Fall-Thru Profile',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.low_quality_fall_thru_profile',
        'Default low-quality fall through profile used during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vmp'
), (
    'acq.upload.default.vandelay.load_item_for_imported',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.load_item_for_imported',
        'Upload Load Items for Imported Records by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.load_item_for_imported',
        'Load items for imported records by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
);


SELECT evergreen.upgrade_deps_block_check('0756', :eg_version);

-- Drop some lingering old functions in search schema
DROP FUNCTION IF EXISTS search.staged_fts(INT,INT,TEXT,INT[],INT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT[],TEXT,TEXT,TEXT,TEXT[],TEXT,REAL,TEXT,BOOL,BOOL,BOOL,INT,INT,INT);
DROP FUNCTION IF EXISTS search.parse_search_args(TEXT);
DROP FUNCTION IF EXISTS search.explode_array(ANYARRAY);
DROP FUNCTION IF EXISTS search.pick_table(TEXT);

-- Now drop query_parser_fts and related
DROP FUNCTION IF EXISTS search.query_parser_fts(INT,INT,TEXT,INT[],INT[],INT,INT,INT,BOOL,BOOL,INT);
DROP TYPE IF EXISTS search.search_result;
DROP TYPE IF EXISTS search.search_args;


SELECT evergreen.upgrade_deps_block_check('0757', :eg_version);

SET search_path = public, pg_catalog;

DO $$
DECLARE
lang TEXT;
BEGIN
FOR lang IN SELECT substring(pptsd.dictname from '(.*)_stem$') AS lang FROM pg_catalog.pg_ts_dict pptsd JOIN pg_catalog.pg_namespace ppn ON ppn.oid = pptsd.dictnamespace
WHERE ppn.nspname = 'pg_catalog' AND pptsd.dictname LIKE '%_stem' LOOP
RAISE NOTICE 'FOUND LANGUAGE %', lang;

EXECUTE 'DROP TEXT SEARCH DICTIONARY IF EXISTS ' || lang || '_nostop CASCADE;
CREATE TEXT SEARCH DICTIONARY ' || lang || '_nostop (TEMPLATE=pg_catalog.snowball, language=''' || lang || ''');
COMMENT ON TEXT SEARCH DICTIONARY ' || lang || '_nostop IS ''' ||lang || ' snowball stemmer with no stopwords for ASCII words only.'';
CREATE TEXT SEARCH CONFIGURATION ' || lang || '_nostop ( COPY = pg_catalog.' || lang || ' );
ALTER TEXT SEARCH CONFIGURATION ' || lang || '_nostop ALTER MAPPING FOR word, hword, hword_part WITH pg_catalog.simple;
ALTER TEXT SEARCH CONFIGURATION ' || lang || '_nostop ALTER MAPPING FOR asciiword, asciihword, hword_asciipart WITH ' || lang || '_nostop;';

END LOOP;
END;
$$;
CREATE TEXT SEARCH CONFIGURATION keyword ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION "default" ( COPY = english_nostop );

SET search_path = evergreen, public, pg_catalog;

ALTER TABLE config.metabib_class
    ADD COLUMN a_weight NUMERIC  DEFAULT 1.0 NOT NULL,
    ADD COLUMN b_weight NUMERIC  DEFAULT 0.4 NOT NULL,
    ADD COLUMN c_weight NUMERIC  DEFAULT 0.2 NOT NULL,
    ADD COLUMN d_weight NUMERIC  DEFAULT 0.1 NOT NULL;

CREATE TABLE config.ts_config_list (
    id      TEXT PRIMARY KEY,
    name    TEXT NOT NULL
);
COMMENT ON TABLE config.ts_config_list IS $$
Full Text Configs

A list of full text configs with names and descriptions.
$$;

CREATE TABLE config.metabib_class_ts_map (
    id              SERIAL PRIMARY KEY,
    field_class     TEXT NOT NULL REFERENCES config.metabib_class (name),
    ts_config       TEXT NOT NULL REFERENCES config.ts_config_list (id),
    active          BOOL NOT NULL DEFAULT TRUE,
    index_weight    CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
    index_lang      TEXT NULL,
    search_lang     TEXT NULL,
    always          BOOL NOT NULL DEFAULT true
);
COMMENT ON TABLE config.metabib_class_ts_map IS $$
Text Search Configs for metabib class indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE config.metabib_field_ts_map (
    id              SERIAL PRIMARY KEY,
    metabib_field   INT NOT NULL REFERENCES config.metabib_field (id),
    ts_config       TEXT NOT NULL REFERENCES config.ts_config_list (id),
    active          BOOL NOT NULL DEFAULT TRUE,
    index_weight    CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
    index_lang      TEXT NULL,
    search_lang     TEXT NULL
);
COMMENT ON TABLE config.metabib_field_ts_map IS $$
Text Search Configs for metabib field indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE metabib.combined_identifier_field_entry (
    record          BIGINT      NOT NULL,
    metabib_field   INT         NULL,
    index_vector    tsvector    NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_identifier_field_entry_fakepk_idx ON metabib.combined_identifier_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_identifier_field_entry_index_vector_idx ON metabib.combined_identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_identifier_field_source_idx ON metabib.combined_identifier_field_entry (metabib_field);

CREATE TABLE metabib.combined_title_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_title_field_entry_fakepk_idx ON metabib.combined_title_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_title_field_entry_index_vector_idx ON metabib.combined_title_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_title_field_source_idx ON metabib.combined_title_field_entry (metabib_field);

CREATE TABLE metabib.combined_author_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_author_field_entry_fakepk_idx ON metabib.combined_author_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_author_field_entry_index_vector_idx ON metabib.combined_author_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_author_field_source_idx ON metabib.combined_author_field_entry (metabib_field);

CREATE TABLE metabib.combined_subject_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_subject_field_entry_fakepk_idx ON metabib.combined_subject_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_subject_field_entry_index_vector_idx ON metabib.combined_subject_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_subject_field_source_idx ON metabib.combined_subject_field_entry (metabib_field);

CREATE TABLE metabib.combined_keyword_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_keyword_field_entry_fakepk_idx ON metabib.combined_keyword_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_keyword_field_entry_index_vector_idx ON metabib.combined_keyword_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_keyword_field_source_idx ON metabib.combined_keyword_field_entry (metabib_field);

CREATE TABLE metabib.combined_series_field_entry (
	record		BIGINT		NOT NULL,
	metabib_field		INT		NULL,
	index_vector	tsvector	NOT NULL
);
CREATE UNIQUE INDEX metabib_combined_series_field_entry_fakepk_idx ON metabib.combined_series_field_entry (record, COALESCE(metabib_field::TEXT,''));
CREATE INDEX metabib_combined_series_field_entry_index_vector_idx ON metabib.combined_series_field_entry USING GIST (index_vector);
CREATE INDEX metabib_combined_series_field_source_idx ON metabib.combined_series_field_entry (metabib_field);

CREATE OR REPLACE FUNCTION metabib.update_combined_index_vectors(bib_id BIGINT) RETURNS VOID AS $func$
BEGIN
    DELETE FROM metabib.combined_keyword_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_keyword_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.keyword_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_title_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_title_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.title_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_author_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_author_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.author_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_subject_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_subject_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.subject_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_series_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_series_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.series_field_entry WHERE source = bib_id;

    DELETE FROM metabib.combined_identifier_field_entry WHERE record = bib_id;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, field, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id GROUP BY field;
    INSERT INTO metabib.combined_identifier_field_entry(record, metabib_field, index_vector)
        SELECT bib_id, NULL, strip(COALESCE(string_agg(index_vector::TEXT,' '),'')::tsvector)
        FROM metabib.identifier_field_entry WHERE source = bib_id;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = ind_data.value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES
                    (metabib.browse_normalize(ind_data.value, ind_data.field));
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field AND NOT skip_search THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    IF NOT skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS evergreen.oils_tsearch2() CASCADE;
DROP FUNCTION IF EXISTS public.oils_tsearch2() CASCADE;

CREATE OR REPLACE FUNCTION public.oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
    temp_vector     TEXT := '';
    ts_rec          RECORD;
    cur_weight      "char";
BEGIN
    value := NEW.value;
    NEW.index_vector = ''::tsvector;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
        NEW.value = value;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN
        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    ELSIF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR ts_rec IN
            SELECT ts_config, index_weight
            FROM config.metabib_class_ts_map
            WHERE field_class = TG_ARGV[0]
                AND index_lang IS NULL OR EXISTS (SELECT 1 FROM metabib.record_attr WHERE id = NEW.source AND index_lang IN(attrs->'item_lang',attrs->'language'))
                AND always OR NOT EXISTS (SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = NEW.field)
            UNION
            SELECT ts_config, index_weight
            FROM config.metabib_field_ts_map
            WHERE metabib_field = NEW.field
               AND index_lang IS NULL OR EXISTS (SELECT 1 FROM metabib.record_attr WHERE id = NEW.source AND index_lang IN(attrs->'item_lang',attrs->'language'))
            ORDER BY index_weight ASC
        LOOP
            IF cur_weight IS NOT NULL AND cur_weight != ts_rec.index_weight THEN
                NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
                temp_vector = '';
            END IF;
            cur_weight = ts_rec.index_weight;
            SELECT INTO temp_vector temp_vector || ' ' || to_tsvector(ts_rec.ts_config::regconfig, value)::TEXT;
        END LOOP;
        NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER authority_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER authority_simple_heading_fti_trigger
    BEFORE UPDATE OR INSERT ON authority.simple_heading
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('identifier');

CREATE TRIGGER metabib_title_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.title_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('title');

CREATE TRIGGER metabib_author_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.author_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('author');

CREATE TRIGGER metabib_subject_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.subject_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('subject');

CREATE TRIGGER metabib_keyword_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.keyword_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_series_field_entry_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.series_field_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('series');

CREATE TRIGGER metabib_browse_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.browse_entry
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE TRIGGER metabib_full_rec_fti_trigger
    BEFORE UPDATE OR INSERT ON metabib.real_full_rec
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

INSERT INTO config.ts_config_list(id, name) VALUES
    ('simple','Non-Stemmed Simple'),
    ('danish_nostop','Danish Stemmed'),
    ('dutch_nostop','Dutch Stemmed'),
    ('english_nostop','English Stemmed'),
    ('finnish_nostop','Finnish Stemmed'),
    ('french_nostop','French Stemmed'),
    ('german_nostop','German Stemmed'),
    ('hungarian_nostop','Hungarian Stemmed'),
    ('italian_nostop','Italian Stemmed'),
    ('norwegian_nostop','Norwegian Stemmed'),
    ('portuguese_nostop','Portuguese Stemmed'),
    ('romanian_nostop','Romanian Stemmed'),
    ('russian_nostop','Russian Stemmed'),
    ('spanish_nostop','Spanish Stemmed'),
    ('swedish_nostop','Swedish Stemmed'),
    ('turkish_nostop','Turkish Stemmed');

INSERT INTO config.metabib_class_ts_map(field_class, ts_config, index_weight, always) VALUES
    ('keyword','simple','A',true),
    ('keyword','english_nostop','C',true),
    ('title','simple','A',true),
    ('title','english_nostop','C',true),
    ('author','simple','A',true),
    ('author','english_nostop','C',true),
    ('series','simple','A',true),
    ('series','english_nostop','C',true),
    ('subject','simple','A',true),
    ('subject','english_nostop','C',true),
    ('identifier','simple','A',true);

CREATE OR REPLACE FUNCTION evergreen.rel_bump(terms TEXT[], value TEXT, bumps TEXT[], mults NUMERIC[]) RETURNS NUMERIC AS
$BODY$
use strict;
my ($terms,$value,$bumps,$mults) = @_;

my $retval = 1;

for (my $id = 0; $id < @$bumps; $id++) {
        if ($bumps->[$id] eq 'first_word') {
                $retval *= $mults->[$id] if ($value =~ /^$terms->[0]/);
        } elsif ($bumps->[$id] eq 'full_match') {
                my $fullmatch = join(' ', @$terms);
                $retval *= $mults->[$id] if ($value =~ /^$fullmatch$/);
        } elsif ($bumps->[$id] eq 'word_order') {
                my $wordorder = join('.*', @$terms);
                $retval *= $mults->[$id] if ($value =~ /$wordorder/);
        }
}
return $retval;
$BODY$ LANGUAGE plperlu IMMUTABLE STRICT COST 100;

/* ** This happens in the supplemental script **

UPDATE metabib.identifier_field_entry set value = value;
UPDATE metabib.title_field_entry set value = value;
UPDATE metabib.author_field_entry set value = value;
UPDATE metabib.subject_field_entry set value = value;
UPDATE metabib.keyword_field_entry set value = value;
UPDATE metabib.series_field_entry set value = value;

SELECT metabib.update_combined_index_vectors(id)
    FROM biblio.record_entry
    WHERE NOT deleted;

*/

SELECT evergreen.upgrade_deps_block_check('0758', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
    ('vandelay', 'Vandelay');

INSERT INTO config.org_unit_setting_type (name, grp, label, datatype, fm_class) VALUES
    ('vandelay.default_match_set', 'vandelay', 'Default Record Match Set', 'link', 'vms');


SELECT evergreen.upgrade_deps_block_check('0759', :eg_version);

CREATE TABLE actor.org_unit_proximity_adjustment (
    id                  SERIAL   PRIMARY KEY,
    item_circ_lib       INT         REFERENCES actor.org_unit (id),
    item_owning_lib     INT         REFERENCES actor.org_unit (id),
    copy_location       INT         REFERENCES asset.copy_location (id),
    hold_pickup_lib     INT         REFERENCES actor.org_unit (id),
    hold_request_lib    INT         REFERENCES actor.org_unit (id),
    pos                 INT         NOT NULL DEFAULT 0,
    absolute_adjustment BOOL        NOT NULL DEFAULT FALSE,
    prox_adjustment     NUMERIC,
    circ_mod            TEXT,       -- REFERENCES config.circ_modifier (code),
    CONSTRAINT prox_adj_criterium CHECK (COALESCE(item_circ_lib::TEXT,item_owning_lib::TEXT,copy_location::TEXT,hold_pickup_lib::TEXT,hold_request_lib::TEXT,circ_mod) IS NOT NULL)
);
CREATE UNIQUE INDEX prox_adj_once_idx ON actor.org_unit_proximity_adjustment (item_circ_lib,item_owning_lib,copy_location,hold_pickup_lib,hold_request_lib,circ_mod);
CREATE INDEX prox_adj_circ_lib_idx ON actor.org_unit_proximity_adjustment (item_circ_lib);
CREATE INDEX prox_adj_owning_lib_idx ON actor.org_unit_proximity_adjustment (item_owning_lib);
CREATE INDEX prox_adj_copy_location_idx ON actor.org_unit_proximity_adjustment (copy_location);
CREATE INDEX prox_adj_pickup_lib_idx ON actor.org_unit_proximity_adjustment (hold_pickup_lib);
CREATE INDEX prox_adj_request_lib_idx ON actor.org_unit_proximity_adjustment (hold_request_lib);
CREATE INDEX prox_adj_circ_mod_idx ON actor.org_unit_proximity_adjustment (circ_mod);

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity(
    ahr_id INT,
    acp_id BIGINT,
    copy_context_ou INT DEFAULT NULL
    -- TODO maybe? hold_context_ou INT DEFAULT NULL.  This would optionally
    -- support an "ahprox" measurement: adjust prox between copy circ lib and
    -- hold request lib, but I'm unsure whether to use this theoretical
    -- argument only in the baseline calculation or later in the other
    -- queries in this function.
) RETURNS NUMERIC AS $f$
DECLARE
    aoupa           actor.org_unit_proximity_adjustment%ROWTYPE;
    ahr             action.hold_request%ROWTYPE;
    acp             asset.copy%ROWTYPE;
    acn             asset.call_number%ROWTYPE;
    acl             asset.copy_location%ROWTYPE;
    baseline_prox   NUMERIC;

    icl_list        INT[];
    iol_list        INT[];
    isl_list        INT[];
    hpl_list        INT[];
    hrl_list        INT[];

BEGIN

    SELECT * INTO ahr FROM action.hold_request WHERE id = ahr_id;
    SELECT * INTO acp FROM asset.copy WHERE id = acp_id;
    SELECT * INTO acn FROM asset.call_number WHERE id = acp.call_number;
    SELECT * INTO acl FROM asset.copy_location WHERE id = acp.location;

    IF copy_context_ou IS NULL THEN
        copy_context_ou := acp.circ_lib;
    END IF;

    -- First, gather the baseline proximity of "here" to pickup lib
    SELECT prox INTO baseline_prox FROM actor.org_unit_proximity WHERE from_org = copy_context_ou AND to_org = ahr.pickup_lib;

    -- Find any absolute adjustments, and set the baseline prox to that
    SELECT  adj.* INTO aoupa
      FROM  actor.org_unit_proximity_adjustment adj
            LEFT JOIN actor.org_unit_ancestors_distance(copy_context_ou) acp_cl ON (acp_cl.id = adj.item_circ_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(acn.owning_lib) acn_ol ON (acn_ol.id = adj.item_owning_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acn_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
        absolute_adjustment AND
        COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
      ORDER BY
            COALESCE(acp_cl.distance,999)
                + COALESCE(acn_ol.distance,999)
                + COALESCE(acl_ol.distance,999)
                + COALESCE(ahr_pl.distance,999)
                + COALESCE(ahr_rl.distance,999),
            adj.pos
      LIMIT 1;

    IF FOUND THEN
        baseline_prox := aoupa.prox_adjustment;
    END IF;

    -- Now find any relative adjustments, and change the baseline prox based on them
    FOR aoupa IN
        SELECT  adj.* 
          FROM  actor.org_unit_proximity_adjustment adj
                LEFT JOIN actor.org_unit_ancestors_distance(copy_context_ou) acp_cl ON (acp_cl.id = adj.item_circ_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(acn.owning_lib) acn_ol ON (acn_ol.id = adj.item_owning_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acn_ol.id = adj.copy_location)
                LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
          WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
            NOT absolute_adjustment AND
            COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

ALTER TABLE actor.org_unit_proximity_adjustment
    ADD CONSTRAINT actor_org_unit_proximity_adjustment_circ_mod_fkey
    FOREIGN KEY (circ_mod) REFERENCES config.circ_modifier (code)
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.hold_copy_map ADD COLUMN proximity NUMERIC;


SELECT evergreen.upgrade_deps_block_check('0760', :eg_version);

CREATE TABLE config.best_hold_order(
    id          SERIAL      PRIMARY KEY,    -- (metadata)
    name        TEXT        UNIQUE,   -- i18n (metadata)
    pprox       INT, -- copy capture <-> pickup lib prox
    hprox       INT, -- copy circ lib <-> request lib prox
    aprox       INT, -- copy circ lib <-> pickup lib ADJUSTED prox on ahcm
    approx      INT, -- copy capture <-> pickup lib ADJUSTED prox from function
    priority    INT, -- group hold priority
    cut         INT, -- cut-in-line
    depth       INT, -- selection depth
    htime       INT, -- time since last home-lib circ exceeds org-unit setting
    rtime       INT, -- request time
    shtime      INT  -- time since copy last trip home exceeds org-unit setting
);

-- At least one of these columns must contain a non-null value
ALTER TABLE config.best_hold_order ADD CHECK ((
    pprox IS NOT NULL OR
    hprox IS NOT NULL OR
    aprox IS NOT NULL OR
    priority IS NOT NULL OR
    cut IS NOT NULL OR
    depth IS NOT NULL OR
    htime IS NOT NULL OR
    rtime IS NOT NULL
));

INSERT INTO config.best_hold_order (
    name,
    pprox, aprox, priority, cut, depth, rtime, htime, hprox
) VALUES (
    'Traditional',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    hprox, pprox, aprox, priority, cut, depth, rtime, htime
) VALUES (
    'Traditional with Holds-always-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    htime, hprox, pprox, aprox, priority, cut, depth, rtime
) VALUES (
    'Traditional with Holds-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    priority, cut, rtime, depth, pprox, hprox, aprox, htime
) VALUES (
    'FIFO',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    hprox, priority, cut, rtime, depth, pprox, aprox, htime
) VALUES (
    'FIFO with Holds-always-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO config.best_hold_order (
    name,
    htime, priority, cut, rtime, depth, pprox, aprox, hprox
) VALUES (
    'FIFO with Holds-go-home',
    1, 2, 3, 4, 5, 6, 7, 8
);

INSERT INTO permission.perm_list (
    id, code, description
) VALUES (
    546,
    'ADMIN_HOLD_CAPTURE_SORT',
    oils_i18n_gettext(
        546,
        'Allows a user to make changes to best-hold selection sort order',
        'ppl',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype, fm_class, update_perm, grp
) VALUES (
    'circ.hold_capture_order',
    oils_i18n_gettext(
        'circ.hold_capture_order',
        'Best-hold selection sort order',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.hold_capture_order',
        'Defines the sort order of holds when selecting a hold to fill using a given copy at capture time',
        'coust',
        'description'
    ),
    'link',
    'cbho',
    546,
    'holds'
);

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype, update_perm, grp
) VALUES (
    'circ.hold_go_home_interval',
    oils_i18n_gettext(
        'circ.hold_go_home_interval',
        'Max foreign-circulation time',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.hold_go_home_interval',
        'Time a copy can spend circulating away from its circ lib before returning there to fill a hold (if one exists there)',
        'coust',
        'description'
    ),
    'interval',
    546,
    'holds'
);

INSERT INTO actor.org_unit_setting (
    org_unit, name, value
) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.hold_go_home_interval',
    '"6 months"'
);

UPDATE actor.org_unit_setting SET
    name = 'circ.hold_capture_order',
    value = (SELECT id FROM config.best_hold_order WHERE name = 'FIFO')
WHERE
    name = 'circ.holds_fifo' AND value ILIKE '%true%';


SELECT evergreen.upgrade_deps_block_check('0762', :eg_version);

INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_browse_indexing');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_search_indexing');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_facet_indexing');

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT, skip_facet BOOL DEFAULT FALSE, skip_browse BOOL DEFAULT FALSE, skip_search BOOL DEFAULT FALSE ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
BEGIN

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.
            SELECT INTO mbe_row * FROM metabib.browse_entry WHERE value = ind_data.value;
            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry (value) VALUES
                    (metabib.browse_normalize(ind_data.value, ind_data.field));
                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source)
                VALUES (mbe_id, ind_data.field, ind_data.source);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0763', :eg_version);

INSERT INTO config.org_unit_setting_type (
    name, label, grp, datatype
) VALUES (
    'circ.fines.truncate_to_max_fine',
    'Truncate fines to max fine amount',
    'circ',
    'bool'
);



SELECT evergreen.upgrade_deps_block_check('0765', :eg_version);

ALTER TABLE acq.provider
    ADD COLUMN default_copy_count INTEGER NOT NULL DEFAULT 0;


SELECT evergreen.upgrade_deps_block_check('0768', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.rank_ou(lib INT, search_lib INT, pref_lib INT DEFAULT NULL)
RETURNS INTEGER AS $$
    SELECT COALESCE(

        -- lib matches search_lib
        (SELECT CASE WHEN $1 = $2 THEN -20000 END),

        -- lib matches pref_lib
        (SELECT CASE WHEN $1 = $3 THEN -10000 END),


        -- pref_lib is a child of search_lib and lib is a child of pref lib.  
        (SELECT distance - 5000
            FROM actor.org_unit_descendants_distance($3) 
            WHERE id = $1 AND $3 IN (
                SELECT id FROM actor.org_unit_descendants($2))),

        -- lib is a child of search_lib
        (SELECT distance FROM actor.org_unit_descendants_distance($2) WHERE id = $1),

        -- all others pay cash
        1000
    );
$$ LANGUAGE SQL STABLE;




SELECT evergreen.upgrade_deps_block_check('0769', :eg_version);

DROP FUNCTION IF EXISTS 
    evergreen.ranked_volumes(BIGINT, INT, INT, HSTORE, HSTORE, INT);

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT, 
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN actor.org_unit_descendants( $2, COALESCE(
                $3, (
                    SELECT depth
                    FROM actor.org_unit_type aout
                        INNER JOIN actor.org_unit ou ON ou_type = aout.id
                    WHERE ou.id = $2
                ), $6)
            ) AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = $1
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN 
                EXISTS (
                    SELECT 1 
                    FROM asset.opac_visible_copies 
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, acp.status, aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY evergreen.rank_ou(aou.id, $2, $6), evergreen.rank_cp_status(acp.status)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$
LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT record_has_holdable_copy FROM asset.record_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($9,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes($1, $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), 0, name, label_sortkey
                        FROM evergreen.located_uris($1, $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('acp' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name foreign_copies,
                         (SELECT XMLAGG(acp) FROM (
                            SELECT  unapi.acp(p.target_copy,'xml','copy',evergreen.array_remove_item_by_value($5,'acp'), $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND p.peer_record = $1
                            LIMIT ($6 -> 'acp')::INT
                            OFFSET ($7 -> 'acp')::INT
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('0771', :eg_version);

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'au.barred',
        'au',
        'A user was barred by staff',
        FALSE
    );

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'au.unbarred',
        'au',
        'A user was un-barred by staff',
        FALSE
    );

INSERT INTO action_trigger.validator (
        module, 
        description
    ) VALUES (
        'PatronBarred',
        'Tests if a patron is currently marked as barred'
    );

INSERT INTO action_trigger.validator (
        module, 
        description
    ) VALUES (
        'PatronNotBarred',
        'Tests if a patron is currently not marked as barred'
    );


SELECT evergreen.upgrade_deps_block_check('0772', :eg_version);

INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.preserve_on_delete');  -- defaults to false/off

DROP RULE protect_bib_rec_delete ON biblio.record_entry;
CREATE RULE protect_bib_rec_delete AS
    ON DELETE TO biblio.record_entry DO INSTEAD (
        UPDATE biblio.record_entry
            SET deleted = TRUE
            WHERE OLD.id = biblio.record_entry.id
    );


-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
        IF NOT FOUND THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id;
            DELETE FROM metabib.record_attr WHERE id = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  m.value INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id) v
                            JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
                      WHERE v.subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            COALESCE( quote_literal( attr_value ), 'NULL' ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


-- Evergreen DB patch xxxx.data.authority_thesaurus_update.sql
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0773', :eg_version);


INSERT INTO authority.thesaurus (code, name, control_set) VALUES
    (' ', oils_i18n_gettext(' ','Alternate no attempt to code','at','name'), NULL);



SELECT evergreen.upgrade_deps_block_check('0774', :eg_version);

CREATE TABLE config.z3950_source_credentials (
    id SERIAL PRIMARY KEY,
    owner INTEGER NOT NULL REFERENCES actor.org_unit(id),
    source TEXT NOT NULL REFERENCES config.z3950_source(name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    -- do some Z servers require a username but no password or vice versa?
    username TEXT,
    password TEXT,
    CONSTRAINT czsc_source_once_per_lib UNIQUE (source, owner)
);

-- find the most relevant set of credentials for the Z source and org
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_lookup
        (source TEXT, owner INTEGER) 
        RETURNS config.z3950_source_credentials AS $$

    SELECT creds.* 
    FROM config.z3950_source_credentials creds
        JOIN actor.org_unit aou ON (aou.id = creds.owner)
        JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
    WHERE creds.source = $1 AND creds.owner IN ( 
        SELECT id FROM actor.org_unit_ancestors($2) 
    )
    ORDER BY aout.depth DESC LIMIT 1;

$$ LANGUAGE SQL STABLE;

-- since we are not exposing config.z3950_source_credentials
-- via the IDL, providing a stored proc gives us a way to
-- set values in the table via cstore
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_apply
        (src TEXT, org INTEGER, uname TEXT, passwd TEXT) 
        RETURNS VOID AS $$
BEGIN
    PERFORM 1 FROM config.z3950_source_credentials
        WHERE owner = org AND source = src;

    IF FOUND THEN
        IF COALESCE(uname, '') = '' AND COALESCE(passwd, '') = '' THEN
            DELETE FROM config.z3950_source_credentials 
                WHERE owner = org AND source = src;
        ELSE 
            UPDATE config.z3950_source_credentials 
                SET username = uname, password = passwd
                WHERE owner = org AND source = src;
        END IF;
    ELSE
        IF COALESCE(uname, '') <> '' OR COALESCE(passwd, '') <> '' THEN
            INSERT INTO config.z3950_source_credentials
                (source, owner, username, password) 
                VALUES (src, org, uname, passwd);
        END IF;
    END IF;
END;
$$ LANGUAGE PLPGSQL;




SELECT evergreen.upgrade_deps_block_check('0775', :eg_version);

ALTER TABLE config.z3950_attr
    DROP CONSTRAINT z3950_attr_source_fkey,
    ADD CONSTRAINT z3950_attr_source_fkey 
        FOREIGN KEY (source) 
        REFERENCES config.z3950_source(name) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('0776', :eg_version);

ALTER TABLE acq.lineitem_attr
    ADD COLUMN order_ident BOOLEAN NOT NULL DEFAULT FALSE;

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    547, -- VERIFY
    'ACQ_ADD_LINEITEM_IDENTIFIER',
    oils_i18n_gettext(
        547,-- VERIFY
        'When granted, newly added lineitem identifiers will propagate to linked bib records',
        'ppl',
        'description'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    548, -- VERIFY
    'ACQ_SET_LINEITEM_IDENTIFIER',
    oils_i18n_gettext(
        548,-- VERIFY
        'Allows staff to change the lineitem identifier',
        'ppl',
        'description'
    )
);


SELECT evergreen.upgrade_deps_block_check('0777', :eg_version);

-- Listed here for reference / ease of access.  The update
-- is not applied here (see the WHERE clause).
UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%
    # extract some commonly used variables

    VENDOR_SAN = target.provider.san;
    VENDCODE = target.provider.edi_default.vendcode;
    VENDACCT = target.provider.edi_default.vendacct;
    ORG_UNIT_SAN = target.ordering_agency.mailing_address.san;

    # set the vendor / provider

    VENDOR_BT      = 0; # Baker & Taylor
    VENDOR_INGRAM  = 0;
    VENDOR_BRODART = 0;
    VENDOR_MW_TAPE = 0; # Midwest Tape
    VENDOR_RB      = 0; # Recorded Books
    VENDOR_ULS     = 0; # ULS

    IF    VENDOR_SAN == '1556150'; VENDOR_BT = 1;
    ELSIF VENDOR_SAN == '1697684'; VENDOR_BRODART = 1;
    ELSIF VENDOR_SAN == '1697978'; VENDOR_INGRAM = 1;
    ELSIF VENDOR_SAN == '2549913'; VENDOR_MW_TAPE = 1;
    ELSIF VENDOR_SAN == '1113984'; VENDOR_RB = 1;
    ELSIF VENDOR_SAN == '1699342'; VENDOR_ULS = 1;
    END;

    # if true, pass the PO name as a secondary identifier
    # RFF+LI:<name>/li_id
    INC_PO_NAME = 0;
    IF VENDOR_INGRAM;
        INC_PO_NAME = 1;
    END;

    # GIR configuration --------------------------------------

    INC_COPIES = 1; # copies on/off switch
    INC_FUND = 0;
    INC_CALLNUMBER = 0;
    INC_ITEM_TYPE = 1;
    INC_LOCATION = 0;
    INC_COLLECTION_CODE = 1;
    INC_OWNING_LIB = 1;
    INC_QUANTITY = 1;
    INC_COPY_ID = 0;

    IF VENDOR_BT;
        INC_CALLNUMBER = 1;
    END;

    IF VENDOR_BRODART;
        INC_FUND = 1;
    END;

    IF VENDOR_MW_TAPE;
        INC_FUND = 1;
        INC_COLLECTION_CODE = 0;
        INC_ITEM_TYPE = 0;
    END;

    # END GIR configuration ---------------------------------

-%]
[%- BLOCK big_block -%]
{
   "recipient":"[% VENDOR_SAN %]",
   "sender":"[% ORG_UNIT_SAN %]",
   "body": [{
     "ORDERS":[ "order", {

        "po_number":[% target.id %],

        [% IF INC_PO_NAME %]
        "po_name":"[% target.name | replace('\/', ' ') | replace('"', '\"') %]",
        [% END %]

        "date":"[% date.format(date.now, '%Y%m%d') %]",

        "buyer":[
            [% IF VENDOR_BT %]
                {"id-qualifier": 91, "id":"[% ORG_UNIT_SAN %] [% VENDCODE %]"}
            [% ELSE %]
                {"id":"[% ORG_UNIT_SAN %]"},
                {"id-qualifier": 91, "id":"[% VENDACCT %]"}
            [% END %]
        ],

        "vendor":[
            "[% VENDOR_SAN %]",
            {"id-qualifier": 92, "id":"[% target.provider.id %]"}
        ],

        "currency":"[% target.provider.currency_type %]",
                
        "items":[
        [%- FOR li IN target.lineitems %]
        {
            "line_index":"[% li.id %]",
            "identifiers":[   
            [%- 
                idval = '';
                idqual = 'EN'; # default ISBN/UPC/EAN-13
                ident_attr = helpers.get_li_order_ident(li.attributes);
                IF ident_attr;
                    idname = ident_attr.attr_name;
                    idval = ident_attr.attr_value;
                    IF idname == 'isbn' AND idval.length != 13;
                        idqual = 'IB';
                    ELSIF idname == 'issn';
                        idqual = 'IS';
                    END;
                ELSE;
                    idqual = 'IN';
                    idval = li.id;
                END -%]
                {"id-qualifier":"[% idqual %]","id":"[% idval %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr_jedi('title',     '', li.attributes) %]"},
                {"BPU":"[% helpers.get_li_attr_jedi('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr_jedi('pubdate',   '', li.attributes) %]"},
                [% IF VENDOR_ULS -%]
                {"BEN":"[% helpers.get_li_attr_jedi('edition',   '', li.attributes) %]"},
                {"BAU":"[% helpers.get_li_attr_jedi('author',    '', li.attributes) %]"}
                [%- ELSE -%]
                {"BPH":"[% helpers.get_li_attr_jedi('pagination','', li.attributes) %]"}
                [%- END %]
            ],
            [%- ftx_vals = []; 
                FOR note IN li.lineitem_notes;
                    NEXT UNLESS note.vendor_public == 't'; 
                    ftx_vals.push(note.value); 
                END; 
                IF VENDOR_BRODART; # look for copy-level spec code
                    FOR lid IN li.lineitem_details;
                        IF lid.note;
                            spec_note = lid.note.match('spec code ([a-zA-Z0-9_])');
                            IF spec_note.0; ftx_vals.push(spec_note.0); END;
                        END;
                    END;
                END; 
                IF xtra_ftx;           ftx_vals.unshift(xtra_ftx); END; 

                # BT & ULS want FTX+LIN for every LI, even if empty
                IF ((VENDOR_BT OR VENDOR_ULS) AND ftx_vals.size == 0);
                    ftx_vals.unshift('');
                END;  
            -%]

            "free-text":[ 
                [% FOR note IN ftx_vals -%] "[% note %]"[% UNLESS loop.last %], [% END %][% END %] 
            ],            

            "quantity":[% li.lineitem_details.size %],

            [%- IF INC_COPIES -%]
            "copies" : [
                [%- compressed_copies = [];
                    FOR lid IN li.lineitem_details;
                        fund = lid.fund.code;
                        item_type = lid.circ_modifier;
                        callnumber = lid.cn_label;
                        owning_lib = lid.owning_lib.shortname;
                        location = lid.location;
                        collection_code = lid.collection_code;
    
                        # when we have real copy data, treat it as authoritative for some fields
                        acp = lid.eg_copy_id;
                        IF acp;
                            item_type = acp.circ_modifier;
                            callnumber = acp.call_number.label;
                            location = acp.location.name;
                        END ;


                        # collapse like copies into groups w/ quantity

                        found_match = 0;
                        IF !INC_COPY_ID; # INC_COPY_ID implies 1 copy per GIR
                            FOR copy IN compressed_copies;
                                IF  (fund == copy.fund OR (!fund AND !copy.fund)) AND
                                    (item_type == copy.item_type OR (!item_type AND !copy.item_type)) AND
                                    (callnumber == copy.callnumber OR (!callnumber AND !copy.callnumber)) AND
                                    (owning_lib == copy.owning_lib OR (!owning_lib AND !copy.owning_lib)) AND
                                    (location == copy.location OR (!location AND !copy.location)) AND
                                    (collection_code == copy.collection_code OR (!collection_code AND !copy.collection_code));

                                    copy.quantity = copy.quantity + 1;
                                    found_match = 1;
                                END;
                            END;
                        END;

                        IF !found_match;
                            compressed_copies.push({
                                fund => fund,
                                item_type => item_type,
                                callnumber => callnumber,
                                owning_lib => owning_lib,
                                location => location,
                                collection_code => collection_code,
                                copy_id => lid.id, # for INC_COPY_ID
                                quantity => 1
                            });
                        END;
                    END;
                    FOR copy IN compressed_copies;

                    # If we assume owning_lib is required and set, 
                    # it is safe to prepend each following copy field w/ a ","

                    # B&T EDI requires expected GIR fields to be 
                    # present regardless of whether a value exists.  
                    # some fields are required to have a value in ACQ, 
                    # though, so they are not forced into place below.

                 %]{[%- IF INC_OWNING_LIB AND copy.owning_lib %] "owning_lib":"[% copy.owning_lib %]"[% END -%]
                    [%- IF INC_FUND AND copy.fund %],"fund":"[% copy.fund %]"[% END -%]
                    [%- IF INC_CALLNUMBER AND (VENDOR_BT OR copy.callnumber) %],"call_number":"[% copy.callnumber %]"[% END -%]
                    [%- IF INC_ITEM_TYPE AND (VENDOR_BT OR copy.item_type) %],"item_type":"[% copy.item_type %]"[% END -%]
                    [%- IF INC_LOCATION AND copy.location %],"copy_location":"[% copy.location %]"[% END -%]
                    [%- IF INC_COLLECTION_CODE AND (VENDOR_BT OR copy.collection_code) %],"collection_code":"[% copy.collection_code %]"[% END -%]
                    [%- IF INC_QUANTITY %],"quantity":"[% copy.quantity %]"[% END -%]
                    [%- IF INC_COPY_ID %],"copy_id":"[% copy.copy_id %]" [% END %]}[% ',' UNLESS loop.last -%]
                [%- END -%] [%# FOR compressed_copies -%]
            ]
            [%- END -%] [%# IF INC_COPIES %]

        }[% UNLESS loop.last %],[% END -%]

        [% END %] [%# END lineitems %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [%# close ORDERS array %]
   }]    [%# close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE ID = 23 AND FALSE; -- remove 'AND FALSE' to apply this update


-- lineitem worksheet
UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%-
    # find a lineitem attribute by name and optional type
    BLOCK get_li_attr;
        FOR attr IN li.attributes;
            IF attr.attr_name == attr_name;
                IF !attr_type OR attr_type == attr.attr_type;
                    attr.attr_value;
                    LAST;
                END;
            END;
        END;
    END
-%]

<h2>Purchase Order [% target.id %]</h2>
<br/>
date <b>[% date.format(date.now, '%Y%m%d') %]</b>
<br/>

<style>
    table td { padding:5px; border:1px solid #aaa;}
    table { width:95%; border-collapse:collapse; }
    #vendor-notes { padding:5px; border:1px solid #aaa; }
</style>
<table id='vendor-table'>
  <tr>
    <td valign='top'>Vendor</td>
    <td>
      <div>[% target.provider.name %]</div>
      <div>[% target.provider.addresses.0.street1 %]</div>
      <div>[% target.provider.addresses.0.street2 %]</div>
      <div>[% target.provider.addresses.0.city %]</div>
      <div>[% target.provider.addresses.0.state %]</div>
      <div>[% target.provider.addresses.0.country %]</div>
      <div>[% target.provider.addresses.0.post_code %]</div>
    </td>
    <td valign='top'>Ship to / Bill to</td>
    <td>
      <div>[% target.ordering_agency.name %]</div>
      <div>[% target.ordering_agency.billing_address.street1 %]</div>
      <div>[% target.ordering_agency.billing_address.street2 %]</div>
      <div>[% target.ordering_agency.billing_address.city %]</div>
      <div>[% target.ordering_agency.billing_address.state %]</div>
      <div>[% target.ordering_agency.billing_address.country %]</div>
      <div>[% target.ordering_agency.billing_address.post_code %]</div>
    </td>
  </tr>
</table>

<br/><br/>
<fieldset id='vendor-notes'>
    <legend>Notes to the Vendor</legend>
    <ul>
    [% FOR note IN target.notes %]
        [% IF note.vendor_public == 't' %]
            <li>[% note.value %]</li>
        [% END %]
    [% END %]
    </ul>
</fieldset>
<br/><br/>

<table>
  <thead>
    <tr>
      <th>PO#</th>
      <th>ISBN or Item #</th>
      <th>Title</th>
      <th>Quantity</th>
      <th>Unit Price</th>
      <th>Line Total</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>

  [% subtotal = 0 %]
  [% FOR li IN target.lineitems %]

  <tr>
    [% count = li.lineitem_details.size %]
    [% price = li.estimated_unit_price %]
    [% litotal = (price * count) %]
    [% subtotal = subtotal + litotal %]
    [% 
        ident_attr = helpers.get_li_order_ident(li.attributes);
        SET ident_value = ident_attr.attr_value IF ident_attr;
    %]
    <td>[% target.id %]</td>
    <td>[% ident_value %]</td>
    <td>[% PROCESS get_li_attr attr_name = 'title' %]</td>
    <td>[% count %]</td>
    <td>[% price %]</td>
    <td>[% litotal %]</td>
    <td>
        <ul>
        [% FOR note IN li.lineitem_notes %]
            [% IF note.vendor_public == 't' %]
                <li>[% note.value %]</li>
            [% END %]
        [% END %]
        </ul>
    </td>
  </tr>
  [% END %]
  <tr>
    <td/><td/><td/><td/>
    <td>Subtotal</td>
    <td>[% subtotal %]</td>
  </tr>
  </tbody>
</table>

<br/>

Total Line Item Count: [% target.lineitems.size %]
$$
WHERE ID = 4; -- PO HTML


SELECT evergreen.upgrade_deps_block_check('0778', :eg_version);

CREATE OR REPLACE FUNCTION extract_marc_field_set
        (TEXT, BIGINT, TEXT, TEXT) RETURNS SETOF TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    FOR output IN
        SELECT x.t FROM (
            SELECT id,t
                FROM  oils_xpath_table(
                    'id', 'marc', $1, $3, 'id = ' || $2)
                AS t(id int, t text))x
        LOOP
        IF $4 IS NOT NULL THEN
            SELECT INTO output (SELECT regexp_replace(output, $4, '', 'g'));
        END IF;
        RETURN NEXT output;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;


CREATE OR REPLACE FUNCTION 
        public.extract_acq_marc_field_set ( BIGINT, TEXT, TEXT) 
        RETURNS SETOF TEXT AS $$
	SELECT extract_marc_field_set('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $function$
DECLARE
	value		TEXT;
	atype		TEXT;
	prov		INT;
	pos 		INT;
	adef		RECORD;
	xpath_string	TEXT;
BEGIN
	FOR adef IN SELECT *,tableoid FROM acq.lineitem_attr_definition LOOP

		SELECT relname::TEXT INTO atype FROM pg_class WHERE oid = adef.tableoid;

		IF (atype NOT IN ('lineitem_usr_attr_definition','lineitem_local_attr_definition')) THEN
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT provider INTO prov FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
				CONTINUE WHEN NEW.provider IS NULL OR prov <> NEW.provider;
			END IF;
			
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_marc_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_marc_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_generated_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_generated_attr_definition WHERE id = adef.id;
			END IF;

            xpath_string := REGEXP_REPLACE(xpath_string,$re$//?text\(\)$$re$,'');

            IF (adef.code = 'title' OR adef.code = 'author') THEN
                -- title and author should not be split
                -- FIXME: once oils_xpath can grok XPATH 2.0 functions, we can use
                -- string-join in the xpath and remove this special case
    			SELECT extract_acq_marc_field(id, xpath_string, adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;
    			IF (value IS NOT NULL AND value <> '') THEN
				    INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
	     			    VALUES (NEW.id, adef.id, atype, adef.code, value);
                END IF;
            ELSE
                pos := 1;
                LOOP
                    -- each application of the regex may produce multiple values
                    FOR value IN
                        SELECT * FROM extract_acq_marc_field_set(
                            NEW.id, xpath_string || '[' || pos || ']', adef.remove)
                        LOOP

                        IF (value IS NOT NULL AND value <> '') THEN
                            INSERT INTO acq.lineitem_attr
                                (lineitem, definition, attr_type, attr_name, attr_value)
                                VALUES (NEW.id, adef.id, atype, adef.code, value);
                        ELSE
                            EXIT;
                        END IF;
                    END LOOP;
                    IF NOT FOUND THEN
                        EXIT;
                    END IF;
                    pos := pos + 1;
               END LOOP;
            END IF;

		END IF;

	END LOOP;

	RETURN NULL;
END;
$function$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0779', :eg_version);

CREATE TABLE vandelay.import_bib_trash_group(
    id SERIAL PRIMARY KEY,
    owner INT NOT NULL REFERENCES actor.org_unit(id),
    label TEXT NOT NULL, --i18n
    always_apply BOOLEAN NOT NULL DEFAULT FALSE,
	CONSTRAINT vand_import_bib_trash_grp_owner_label UNIQUE (owner, label)
);

-- otherwise, the ALTER TABLE statement below
-- will fail with pending trigger events.
SET CONSTRAINTS ALL IMMEDIATE;

ALTER TABLE vandelay.import_bib_trash_fields
    -- allow null-able for now..
    ADD COLUMN grp INTEGER REFERENCES vandelay.import_bib_trash_group;

-- add any existing trash_fields to "Legacy" groups (one per unique field
-- owner) as part of the upgrade, since grp is now required.
-- note that vandelay.import_bib_trash_fields was never used before,
-- so in most cases this should be a no-op.

INSERT INTO vandelay.import_bib_trash_group (owner, label)
    SELECT DISTINCT(owner), 'Legacy' FROM vandelay.import_bib_trash_fields;

UPDATE vandelay.import_bib_trash_fields field SET grp = tgroup.id
    FROM vandelay.import_bib_trash_group tgroup
    WHERE tgroup.owner = field.owner;
    
ALTER TABLE vandelay.import_bib_trash_fields
    -- now that have values, we can make this non-null
    ALTER COLUMN grp SET NOT NULL,
    -- drop outdated constraint
    DROP CONSTRAINT vand_import_bib_trash_fields_idx,
    -- owner is implied by the grp
    DROP COLUMN owner, 
    -- make grp+field unique
    ADD CONSTRAINT vand_import_bib_trash_fields_once_per UNIQUE (grp, field);


SELECT evergreen.upgrade_deps_block_check('0780', :eg_version);

ALTER TABLE acq.distribution_formula_entry
    ADD COLUMN fund INT REFERENCES acq.fund (id),
    ADD COLUMN circ_modifier TEXT REFERENCES config.circ_modifier (code),
    ADD COLUMN collection_code TEXT ;


-- support option to roll distribution formula funds
CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER,
    encumb_only BOOL DEFAULT FALSE,
    include_desc BOOL DEFAULT TRUE
) RETURNS VOID AS $$
DECLARE
--
new_fund    INT;
new_year    INT := old_year + 1;
org_found   BOOL;
perm_ous    BOOL;
xfer_amount NUMERIC := 0;
roll_fund   RECORD;
deb         RECORD;
detail      RECORD;
roll_distrib_forms BOOL;
--
BEGIN
	--
	-- Sanity checks
	--
	IF old_year IS NULL THEN
		RAISE EXCEPTION 'Input year argument is NULL';
    ELSIF old_year NOT BETWEEN 2008 and 2200 THEN
        RAISE EXCEPTION 'Input year is out of range';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'Input user id argument is NULL';
	END IF;
	--
	IF org_unit_id IS NULL THEN
		RAISE EXCEPTION 'Org unit id argument is NULL';
	ELSE
		--
		-- Validate the org unit
		--
		SELECT TRUE
		INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id % is invalid', org_unit_id;
		ELSIF encumb_only THEN
			SELECT INTO perm_ous value::BOOL FROM
			actor.org_unit_ancestor_setting(
				'acq.fund.allow_rollover_without_money', org_unit_id
			);
			IF NOT FOUND OR NOT perm_ous THEN
				RAISE EXCEPTION 'Encumbrance-only rollover not permitted at org %', org_unit_id;
			END IF;
		END IF;
	END IF;
	--
	-- Loop over the propagable funds to identify the details
	-- from the old fund plus the id of the new one, if it exists.
	--
	FOR roll_fund in
	SELECT
	    oldf.id AS old_fund,
	    oldf.org,
	    oldf.name,
	    oldf.currency_type,
	    oldf.code,
		oldf.rollover,
	    newf.id AS new_fund_id
	FROM
    	acq.fund AS oldf
    	LEFT JOIN acq.fund AS newf
        	ON ( oldf.code = newf.code )
	WHERE
 		    oldf.year = old_year
		AND oldf.propagate
        AND newf.year = new_year
		AND ( ( include_desc AND oldf.org IN ( SELECT id FROM actor.org_unit_descendants( org_unit_id ) ) )
                OR (NOT include_desc AND oldf.org = org_unit_id ) )
	LOOP
		--RAISE NOTICE 'Processing fund %', roll_fund.old_fund;
		--
		IF roll_fund.new_fund_id IS NULL THEN
			--
			-- The old fund hasn't been propagated yet.  Propagate it now.
			--
			INSERT INTO acq.fund (
				org,
				name,
				year,
				currency_type,
				code,
				rollover,
				propagate,
				balance_warning_percent,
				balance_stop_percent
			) VALUES (
				roll_fund.org,
				roll_fund.name,
				new_year,
				roll_fund.currency_type,
				roll_fund.code,
				true,
				true,
				roll_fund.balance_warning_percent,
				roll_fund.balance_stop_percent
			)
			RETURNING id INTO new_fund;
		ELSE
			new_fund = roll_fund.new_fund_id;
		END IF;
		--
		-- Determine the amount to transfer
		--
		SELECT amount
		INTO xfer_amount
		FROM acq.fund_spent_balance
		WHERE fund = roll_fund.old_fund;
		--
		IF xfer_amount <> 0 THEN
			IF NOT encumb_only AND roll_fund.rollover THEN
				--
				-- Transfer balance from old fund to new
				--
				--RAISE NOTICE 'Transferring % from fund % to %', xfer_amount, roll_fund.old_fund, new_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					new_fund,
					xfer_amount,
					user_id,
					'Rollover'
				);
			ELSE
				--
				-- Transfer balance from old fund to the void
				--
				-- RAISE NOTICE 'Transferring % from fund % to the void', xfer_amount, roll_fund.old_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					NULL,
					NULL,
					user_id,
					'Rollover into the void'
				);
			END IF;
		END IF;
		--
		IF roll_fund.rollover THEN
			--
			-- Move any lineitems from the old fund to the new one
			-- where the associated debit is an encumbrance.
			--
			-- Any other tables tying expenditure details to funds should
			-- receive similar treatment.  At this writing there are none.
			--
			UPDATE acq.lineitem_detail
			SET fund = new_fund
			WHERE
    			fund = roll_fund.old_fund -- this condition may be redundant
    			AND fund_debit in
    			(
        			SELECT id
        			FROM acq.fund_debit
        			WHERE
            			fund = roll_fund.old_fund
            			AND encumbrance
    			);
			--
			-- Move encumbrance debits from the old fund to the new fund
			--
			UPDATE acq.fund_debit
			SET fund = new_fund
			wHERE
				fund = roll_fund.old_fund
				AND encumbrance;
		END IF;

		-- Rollover distribution formulae funds
		SELECT INTO roll_distrib_forms value::BOOL FROM
			actor.org_unit_ancestor_setting(
				'acq.fund.rollover_distrib_forms', org_unit_id
			);

		IF roll_distrib_forms THEN
			UPDATE acq.distribution_formula_entry 
				SET fund = roll_fund.new_fund_id
				WHERE fund = roll_fund.old_fund;
		END IF;

		--
		-- Mark old fund as inactive, now that we've closed it
		--
		UPDATE acq.fund
		SET active = FALSE
		WHERE id = roll_fund.old_fund;
	END LOOP;
END;
$$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('0781', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'acq.fund.rollover_distrib_forms',
    oils_i18n_gettext(
        'acq.fund.rollover_distrib_forms',
        'Rollover Distribution Formulae Funds',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.fund.rollover_distrib_forms',
        'During fiscal rollover, update distribution formalae to use new funds',
        'coust',
        'description'
    ),
    'acq',
    'bool'
);


-- No transaction needed. This can be run on a live, production server.
SELECT evergreen.upgrade_deps_block_check('0782', :eg_version);

/* ** Handled by the supplemental script ** */
-- On a heavily used system, user activity lookup is painful.  This is used
-- on the patron display in the staff client.
--
-- Measured speed increase: ~2s -> .01s
-- CREATE INDEX CONCURRENTLY usr_activity_usr_idx on actor.usr_activity (usr);

-- Finding open holds, often as a subquery within larger hold-related logic,
-- can be sped up with the following.
--
-- Measured speed increase: ~3s -> .02s
-- CREATE INDEX CONCURRENTLY hold_request_open_idx on action.hold_request (id) where cancel_time IS NULL AND fulfillment_time IS NULL;

-- Hold queue position is a particularly difficult thing to calculate
-- efficiently.  Recent changes in the query structure now allow some
-- optimization via indexing.  These do that.
--
-- Measured speed increase: ~6s -> ~0.4s
-- CREATE INDEX CONCURRENTLY cp_available_by_circ_lib_idx on asset.copy (circ_lib) where status IN (0,7);
-- CREATE INDEX CONCURRENTLY hold_request_current_copy_before_cap_idx on action.hold_request (current_copy) where capture_time IS NULL AND cancel_time IS NULL;

-- After heavy use, fetching EDI messages becomes time consuming.  The following
-- index addresses that for large-data environments.
-- 
-- Measured speed increase: ~3s -> .1s
-- CREATE INDEX CONCURRENTLY edi_message_account_status_idx on acq.edi_message (account,status);

-- After heavy use, fetching POs becomes time consuming.  The following
-- index addresses that for large-data environments.
-- 
-- Measured speed increase: ~1.5s -> .1s
-- CREATE INDEX CONCURRENTLY edi_message_po_idx on acq.edi_message (purchase_order);

-- Related to EDI messages, fetching of certain A/T events benefit from specific
-- indexing.  This index is more general than necessary for the observed query
-- but ends up speeding several other (already relatively fast) queries.
--
-- Measured speed increase: ~2s -> .06s
-- CREATE INDEX CONCURRENTLY atev_def_state on action_trigger.event (event_def,state);

-- Retrieval of hold transit by hold id (for transit completion or cancelation)
-- is slow in some query formulations.
--
-- Measured speed increase: ~.5s -> .1s
-- CREATE INDEX CONCURRENTLY hold_transit_copy_hold_idx on action.hold_transit_copy (hold);


SELECT evergreen.upgrade_deps_block_check('0785', :eg_version);

DROP INDEX actor.prox_adj_once_idx;

CREATE UNIQUE INDEX prox_adj_once_idx ON actor.org_unit_proximity_adjustment (
    COALESCE(item_circ_lib, -1),
    COALESCE(item_owning_lib, -1),
    COALESCE(copy_location, -1),
    COALESCE(hold_pickup_lib, -1),
    COALESCE(hold_request_lib, -1),
    COALESCE(circ_mod, ''),
    pos
);


--Check if we can apply the upgrade.
SELECT evergreen.upgrade_deps_block_check('0786', :eg_version);


CREATE TYPE search.search_result AS ( id BIGINT, rel NUMERIC, record INT, total INT, checked INT, visible INT, deleted INT, excluded INT );
CREATE TYPE search.search_args AS ( id INT, field_class TEXT, field_name TEXT, table_alias TEXT, term TEXT, term_type TEXT );

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        SELECT array_accum(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );

    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP
            SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT array_accum(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
        SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors(param_pref_ou);
        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                  WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  asset.call_number cn
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND NOT cp.deleted
                      LIMIT 1;

                    IF FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

 

SELECT evergreen.upgrade_deps_block_check('0788', :eg_version);

-- New view including 264 as a potential tag for publisher and pubdate
CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT publisher.value), ', ') AS publisher,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$) ), ', ') AS pubdate,
    ARRAY_ACCUM( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) AS isbn,
    ARRAY_ACCUM( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

-- Update reporter.materialized_simple_record with new 264-based values for publisher and pubdate
DELETE FROM reporter.materialized_simple_record WHERE id IN (
    SELECT DISTINCT record FROM metabib.full_rec WHERE tag = '264' AND subfield IN ('b', 'c')
);

INSERT INTO reporter.materialized_simple_record
    SELECT DISTINCT rossr.* FROM reporter.old_super_simple_record rossr INNER JOIN metabib.full_rec mfr ON mfr.record = rossr.id
        WHERE mfr.tag = '264' AND mfr.subfield IN ('b', 'c')
;

SELECT evergreen.upgrade_deps_block_check('0789', :eg_version);
SELECT evergreen.upgrade_deps_block_check('0790', :eg_version);

ALTER TABLE config.metabib_class ADD COLUMN combined BOOL NOT NULL DEFAULT FALSE;
UPDATE config.metabib_class SET combined = TRUE WHERE name = 'subject';


--Check if we can apply the upgrade.
SELECT evergreen.upgrade_deps_block_check('0791', :eg_version);



CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    deleted_search  BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        SELECT array_accum(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );

    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP
            SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT array_accum(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
        SELECT array_accum(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors(param_pref_ou);
        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        IF NOT deleted_search THEN

            PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
                deleted_count := deleted_count + 1;
                CONTINUE;
            END IF;

            PERFORM 1
              FROM  biblio.record_entry b
                    JOIN config.bib_source s ON (b.source = s.id)
              WHERE s.transcendant
                    AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

            IF FOUND THEN
                -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                    JOIN asset.uri uri ON (map.uri = uri.id)
              WHERE NOT cn.deleted
                    AND cn.label = '##URI##'
                    AND uri.active
                    AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
              LIMIT 1;

            IF FOUND THEN
                -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;

                tmp_int := 1;
                IF metarecord THEN
                    SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
                END IF;

                IF tmp_int = 1 THEN
                    current_res.record = core_result.records[1];
                ELSE
                    current_res.record = NULL;
                END IF;

                RETURN NEXT current_res;

                CONTINUE;
            END IF;

            IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF staff IS NULL OR NOT staff THEN

                PERFORM 1
                  FROM  asset.opac_visible_copies
                  WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                      WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            ELSE

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        PERFORM 1
                          FROM  asset.call_number cn
                                JOIN asset.copy cp ON (cp.call_number = cn.id)
                          WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                AND NOT cp.deleted
                          LIMIT 1;

                        IF FOUND THEN
                            -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                            excluded_count := excluded_count + 1;
                            CONTINUE;
                        END IF;
                    END IF;

                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;


-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
        IF NOT FOUND THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id;
            DELETE FROM metabib.record_attr WHERE id = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  m.value INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id) v
                            JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
                      WHERE v.subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            COALESCE( quote_literal( attr_value ), 'NULL' ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                DELETE FROM metabib.record_attr WHERE id = NEW.id;
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
 
SELECT evergreen.upgrade_deps_block_check('0792', :eg_version);

UPDATE permission.perm_list SET code = 'URL_VERIFY_UPDATE_SETTINGS' WHERE id = 544 AND code = '544';


SELECT evergreen.upgrade_deps_block_check('0793', :eg_version);

UPDATE config.best_hold_order
SET
    approx = 1,
    pprox = 2,
    aprox = 3,
    priority = 4,
    cut = 5,
    depth = 6,
    rtime = 7,
    hprox = NULL,
    htime = NULL
WHERE name = 'Traditional' AND
    pprox = 1 AND
    aprox = 2 AND
    priority = 3 AND
    cut = 4 AND
    depth = 5 AND
    rtime = 6 ;

UPDATE config.best_hold_order
SET
    hprox = 1,
    approx = 2,
    pprox = 3,
    aprox = 4,
    priority = 5,
    cut = 6,
    depth = 7,
    rtime = 8,
    htime = NULL
WHERE name = 'Traditional with Holds-always-go-home' AND
    hprox = 1 AND
    pprox = 2 AND
    aprox = 3 AND
    priority = 4 AND
    cut = 5 AND
    depth = 6 AND
    rtime = 7 AND
    htime = 8;

UPDATE config.best_hold_order
SET
    htime = 1,
    approx = 2,
    pprox = 3,
    aprox = 4,
    priority = 5,
    cut = 6,
    depth = 7,
    rtime = 8,
    hprox = NULL
WHERE name = 'Traditional with Holds-go-home' AND
    htime = 1 AND
    hprox = 2 AND
    pprox = 3 AND
    aprox = 4 AND
    priority = 5 AND
    cut = 6 AND
    depth = 7 AND
    rtime = 8 ;


COMMIT;

-- These are from 0789, and can and should be run outside of a transaction
CREATE TEXT SEARCH CONFIGURATION title ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION author ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION subject ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION series ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION identifier ( COPY = english_nostop );

\qecho Please run Open-ILS/src/sql/Pg/version-upgrade/2.3-2.4-supplemental.sh now, which contains additional required SQL to complete your Evergreen upgrade!

