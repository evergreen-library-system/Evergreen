--Upgrade Script for 2.3 to 2.4.alpha1
\set eg_version '''2.4.alpha1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.4.alpha1', :eg_version);
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

UPDATE metabib.identifier_field_entry set value = value;
UPDATE metabib.title_field_entry set value = value;
UPDATE metabib.author_field_entry set value = value;
UPDATE metabib.subject_field_entry set value = value;
UPDATE metabib.keyword_field_entry set value = value;
UPDATE metabib.series_field_entry set value = value;

SELECT metabib.update_combined_index_vectors(id)
    FROM biblio.record_entry
    WHERE NOT deleted;


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

COMMIT;
