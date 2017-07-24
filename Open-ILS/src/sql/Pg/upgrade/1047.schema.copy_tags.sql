BEGIN;

SELECT evergreen.upgrade_deps_block_check('1047', :eg_version); -- gmcharlt/stompro

CREATE TABLE config.copy_tag_type (
    code            TEXT NOT NULL PRIMARY KEY,
    label           TEXT NOT NULL,
    owner           INTEGER NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX config_copy_tag_type_owner_idx
    ON config.copy_tag_type (owner);

CREATE TABLE asset.copy_tag (
    id              SERIAL PRIMARY KEY,
    tag_type        TEXT REFERENCES config.copy_tag_type (code)
                    ON UPDATE CASCADE ON DELETE CASCADE,
    label           TEXT NOT NULL,
    value           TEXT NOT NULL,
    index_vector    tsvector NOT NULL,
    staff_note      TEXT,
    pub             BOOLEAN DEFAULT TRUE,
    owner           INTEGER NOT NULL REFERENCES actor.org_unit (id)
);

CREATE INDEX asset_copy_tag_label_idx
    ON asset.copy_tag (label);
CREATE INDEX asset_copy_tag_label_lower_idx
    ON asset.copy_tag (evergreen.lowercase(label));
CREATE INDEX asset_copy_tag_index_vector_idx
    ON asset.copy_tag
    USING GIN(index_vector);
CREATE INDEX asset_copy_tag_tag_type_idx
    ON asset.copy_tag (tag_type);
CREATE INDEX asset_copy_tag_owner_idx
    ON asset.copy_tag (owner);

CREATE OR REPLACE FUNCTION asset.set_copy_tag_value () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.value IS NULL THEN
        NEW.value = NEW.label;        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- name of following trigger chosen to ensure it runs first
CREATE TRIGGER asset_copy_tag_do_value
    BEFORE INSERT OR UPDATE ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE asset.set_copy_tag_value();
CREATE TRIGGER asset_copy_tag_fti_trigger
    BEFORE UPDATE OR INSERT ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

CREATE TABLE asset.copy_tag_copy_map (
    id              BIGSERIAL PRIMARY KEY,
    copy            BIGINT REFERENCES asset.copy (id)
                    ON UPDATE CASCADE ON DELETE CASCADE,
    tag             INTEGER REFERENCES asset.copy_tag (id)
                    ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX asset_copy_tag_copy_map_copy_idx
    ON asset.copy_tag_copy_map (copy);
CREATE INDEX asset_copy_tag_copy_map_tag_idx
    ON asset.copy_tag_copy_map (tag);

INSERT INTO config.copy_tag_type (code, label, owner) VALUES ('bookplate', 'Digital Bookplate', 1);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 590, 'ADMIN_COPY_TAG_TYPES', oils_i18n_gettext( 590,
    'Administer copy tag types', 'ppl', 'description' )),
 ( 591, 'ADMIN_COPY_TAG', oils_i18n_gettext( 591,
    'Administer copy tag', 'ppl', 'description' ))
;

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'opac.search.enable_bookplate_search',
    oils_i18n_gettext(
        'opac.search.enable_bookplate_search',
        'Enable Digital Bookplate Search',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.search.enable_bookplate_search',
        'If enabled, adds a "Digital Bookplate" option to the query type selectors in the public catalog for search on copy tags.',   
        'coust',
        'description'
    ),
    'opac',
    'bool'
);

COMMIT;
