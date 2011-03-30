BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0504'); -- miker

CREATE OR REPLACE FUNCTION lpad_number_substrings( TEXT, TEXT, INT ) RETURNS TEXT AS $$
    my $string = shift;
    my $pad = shift;
    my $len = shift;
    my $find = $len - 1;

    while ($string =~ /(?:^|\D)(\d{1,$find})(?:$|\D)/) {
        my $padded = $1;
        $padded = $pad x ($len - length($padded)) . $padded;
        $string =~ s/$1/$padded/sg;
    }

    return $string;
$$ LANGUAGE PLPERLU;

CREATE TABLE biblio.monograph_part (
    id              SERIAL  PRIMARY KEY,
    record          BIGINT  NOT NULL REFERENCES biblio.record_entry (id),
    label           TEXT    NOT NULL,
    label_sortkey   TEXT    NOT NULL,
    CONSTRAINT record_label_unique UNIQUE (record,label)
);

CREATE OR REPLACE FUNCTION biblio.normalize_biblio_monograph_part_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER norm_sort_label BEFORE INSERT OR UPDATE ON biblio.monograph_part FOR EACH ROW EXECUTE PROCEDURE biblio.normalize_biblio_monograph_part_sortkey();

CREATE TABLE asset.copy_part_map (
    id          SERIAL  PRIMARY KEY,
    target_copy BIGINT  NOT NULL, -- points o asset.copy
    part        INT     NOT NULL REFERENCES biblio.monograph_part (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX copy_part_map_cp_part_idx ON asset.copy_part_map (target_copy, part);

CREATE OR REPLACE FUNCTION asset.normalize_affix_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE asset.call_number_prefix (
       id                      SERIAL   PRIMARY KEY,
       owning_lib          INT                 NOT NULL REFERENCES actor.org_unit (id),
       label               TEXT                NOT NULL, -- i18n
       label_sortkey   TEXT
);
CREATE TRIGGER prefix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_prefix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_prefix_once_per_lib ON asset.call_number_prefix (label, owning_lib);
CREATE INDEX asset_call_number_prefix_sortkey_idx ON asset.call_number_prefix (label_sortkey);

CREATE TABLE asset.call_number_suffix (
       id                      SERIAL   PRIMARY KEY,
       owning_lib          INT                 NOT NULL REFERENCES actor.org_unit (id),
       label               TEXT                NOT NULL, -- i18n
       label_sortkey   TEXT
);
CREATE TRIGGER suffix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_suffix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_suffix_once_per_lib ON asset.call_number_suffix (label, owning_lib);
CREATE INDEX asset_call_number_suffix_sortkey_idx ON asset.call_number_suffix (label_sortkey);

INSERT INTO asset.call_number_suffix (id, owning_lib, label) VALUES (-1, 1, '');
INSERT INTO asset.call_number_prefix (id, owning_lib, label) VALUES (-1, 1, '');

DROP INDEX IF EXISTS asset.asset_call_number_label_once_per_lib;

ALTER TABLE asset.call_number
    ADD COLUMN prefix INT NOT NULL DEFAULT -1 REFERENCES asset.call_number_prefix(id) DEFERRABLE INITIALLY DEFERRED,
    ADD COLUMN suffix INT NOT NULL DEFAULT -1 REFERENCES asset.call_number_suffix(id) DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label, prefix, suffix) WHERE deleted = FALSE OR deleted IS FALSE;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'ui.cat.volume_copy_editor.horizontal',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.horizontal',
        'GUI: Horizontal layout for Volume/Copy Creator/Editor.',
        'coust', 'label'),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.horizontal',
        'The main entry point for this interface is in Holdings Maintenance, Actions for Selected Rows, Edit Item Attributes / Call Numbers / Replace Barcodes.  This setting changes the top and bottom panes for that interface into left and right panes.',
	'coust', 'description'),
    'bool'
);


CREATE OR REPLACE FUNCTION unapi.bmp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name monograph_part,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@bmp/' || id AS id,
                        id AS ident,
                        label,
                        label_sortkey,
                        'tag:open-ils.org:U2@bre/' || record AS record
                    ),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            XMLELEMENT( name copies,
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8)
                                      FROM  asset.copy cp
                                            JOIN asset.copy_part_map cpm ON (cpm.target_copy = cp.id)
                                      WHERE cpm.part = $1
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( record, 'marcxml', 'record', array_remove_item_by_value($4,'bmp'), $5, $6, $7, $8) ELSE NULL END
                )
          FROM  biblio.monograph_part
          WHERE id = $1
          GROUP BY id, label, label_sortkey, record;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acnp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_prefix,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove_item_by_value($4,'acnp'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_prefix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acns ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name call_number_suffix,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        id AS ident,
                        label,
                        label_sortkey
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove_item_by_value($4,'acns'), $5, $6, $7, $8)
                )
          FROM  asset.call_number_suffix
          WHERE id = $1;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    'http://open-ils.org/spec/holdings/v1' AS xmlns,
                    CASE WHEN ('bre' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
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
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT( name monograph_parts,
                            XMLAGG((SELECT unapi.bmp( id, 'xml', 'monograph_part', array_remove_item_by_value( array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7) FROM biblio.monograph_part WHERE record = $1))
                        )
                     ELSE NULL
                 END,
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume',array_remove_item_by_value(array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7)
                              FROM  asset.call_number acn
                              WHERE acn.record = $1
                                    AND EXISTS (
                                        SELECT  1
                                          FROM  asset.copy acp
                                                JOIN actor.org_unit_descendants(
                                                    $2,
                                                    (COALESCE(
                                                        $4,
                                                        (SELECT aout.depth
                                                          FROM  actor.org_unit_type aout
                                                                JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.id = $2)
                                                        )
                                                    ))
                                                ) aoud ON (acp.circ_lib = aoud.id)
                                          LIMIT 1
                                    )
                              ORDER BY label_sortkey
                              LIMIT $6
                              OFFSET $7
                         )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('ssub' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.acl( location, $2, 'location', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE 
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE 
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.ascecm( stat_cat_entry, 'xml', 'statcat', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    ),
                    CASE 
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                XMLAGG((SELECT unapi.bmp( part, 'xml', 'monograph_part', array_remove_item_by_value($4,'acp'), $5, $6, $7, $8) FROM asset.copy_part_map WHERE target_copy = cp.id))
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        'http://open-ils.org/spec/holdings/v1' AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    XMLELEMENT( name copies,
                        CASE 
                            WHEN ('acp' = ANY ($4)) THEN
                                (SELECT XMLAGG(acp) FROM (
                                    SELECT  unapi.acp( cp.id, 'xml', 'copy', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8)
                                      FROM  asset.copy cp
                                            JOIN actor.org_unit_descendants(
                                                (SELECT id FROM actor.org_unit WHERE shortname = $5),
                                                (COALESCE($6,(SELECT aout.depth FROM actor.org_unit_type aout JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.shortname = $5))))
                                            ) aoud ON (cp.circ_lib = aoud.id)
                                      WHERE cp.call_number = acn.id
                                      ORDER BY COALESCE(cp.copy_number,0), cp.barcode
                                      LIMIT $7
                                      OFFSET $8
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    CASE WHEN ('acnp' = ANY ($4)) THEN unapi.acnp( acn.prefix, 'marcxml', 'prefix', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) ELSE NULL END,
                    CASE WHEN ('acns' = ANY ($4)) THEN unapi.acns( acn.suffix, 'marcxml', 'suffix', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) ELSE NULL END,
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', array_remove_item_by_value($4,'acn'), $5, $6, $7, $8) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL;


COMMIT;

