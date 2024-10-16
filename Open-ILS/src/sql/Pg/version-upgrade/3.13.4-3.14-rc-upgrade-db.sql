--Upgrade Script for 3.13.4 to 3.14-rc
\set eg_version '''3.14-rc'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.14-rc', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1419', :eg_version);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'ui.show_search_highlight',
    'gui',
    TRUE,
    oils_i18n_gettext(
        'ui.show_search_highlight',
        'Search Highlight',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.show_search_highlight',
        'A toggle deciding whether to highlight strings in a keyword search result matching the searched term(s)',
        'cust',
        'description'
    ),
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1420', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.search.sort_order', 'gui', 'string',
    oils_i18n_gettext(
        'eg.search.sort_order',
        'Default sort order upon first opening a catalog search',
        'cwst', 'label'
    )
), 
(
    'eg.search.available_only', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.search.available_only',
        'Whether to search for only bibs with available items upon first opening a catalog search',
        'cwst', 'label'
    )
),
(
    'eg.search.group_formats', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.search.group_formats',
        'Whether to group formats/editions upon first opening a catalog search',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1421', :eg_version);

CREATE OR REPLACE FUNCTION unapi.acpt ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy_tag,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        copy_tag_type.label AS type,
                        copy_tag.url AS url
                    ),
                    copy_tag.value
                )
          FROM  asset.copy_tag
          JOIN  config.copy_tag_type
          ON    copy_tag_type.code = copy_tag.tag_type
          WHERE copy_tag.id = $1;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect
                    ),
                    unapi.ccs( status, $2, 'status', array_remove($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', array_remove($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    CASE
                        WHEN ('acpn' = ANY ($4)) THEN
                            XMLELEMENT( name copy_notes,
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('acpt' = ANY ($4)) THEN
                            XMLELEMENT( name copy_tags,
                                (SELECT XMLAGG(acpt) FROM (
                                    SELECT  unapi.acpt( copy_tag.id, 'xml', 'copy_tag', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_tag_copy_map
                                      JOIN asset.copy_tag ON copy_tag.id = copy_tag_copy_map.tag
                                      WHERE copy_tag_copy_map.copy = cp.id AND copy_tag.pub
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('ascecm' = ANY ($4)) THEN
                            XMLELEMENT( name statcats,
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('bre' = ANY ($4)) THEN
                            XMLELEMENT( name foreign_records,
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', array_remove($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, deposit, ref, holdable,
              deleted, deposit_amount, price, barcode, circ_modifier,
              circ_as_type, opac_visible, age_protect;
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION unapi.sunit ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name serial_unit,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id, id AS copy_id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible, age_protect,
                        status_changed_time, floating, mint_condition,
                        detailed_contents, sort_key, summary_contents, cost
                    ),
                    unapi.ccs( status, $2, 'status', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', array_remove($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE
                            WHEN ('acpn' = ANY ($4)) THEN
                                (SELECT XMLAGG(acpn) FROM (
                                    SELECT  unapi.acpn( id, 'xml', 'copy_note', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_note
                                      WHERE owning_copy = cp.id AND pub
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name copy_tags,
                        CASE
                            WHEN ('acpt' = ANY ($4)) THEN
                                (SELECT XMLAGG(acpt) FROM (
                                    SELECT  unapi.acpt( copy_tag.id, 'xml', 'copy_tag', array_remove( array_remove($4,'acp'),'sunit'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_tag_copy_map
                                      JOIN  asset.copy_tag ON copy_tag.id = copy_tag_copy_map.tag
                                      WHERE copy_tag_copy_map.copy = cp.id AND copy_tag.pub
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE
                            WHEN ('ascecm' = ANY ($4)) THEN
                                (SELECT XMLAGG(ascecm) FROM (
                                    SELECT  unapi.ascecm( stat_cat_entry, 'xml', 'statcat', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.stat_cat_entry_copy_map
                                      WHERE owning_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name foreign_records,
                        CASE
                            WHEN ('bre' = ANY ($4)) THEN
                                (SELECT XMLAGG(bre) FROM (
                                    SELECT  unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE)
                                      FROM  biblio.peer_bib_copy_map
                                      WHERE target_copy = cp.id
                                )x)
                            ELSE NULL
                        END
                    ),
                    CASE
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                (SELECT XMLAGG(bmp) FROM (
                                    SELECT  unapi.bmp( part, 'xml', 'monograph_part', array_remove($4,'acp'), $5, $6, $7, $8, FALSE)
                                      FROM  asset.copy_part_map
                                      WHERE target_copy = cp.id
                                )x)
                            )
                        ELSE NULL
                    END,
                    CASE
                        WHEN ('circ' = ANY ($4)) THEN
                            XMLELEMENT( name current_circulation,
                                (SELECT XMLAGG(circ) FROM (
                                    SELECT  unapi.circ( id, 'xml', 'circ', array_remove($4,'circ'), $5, $6, $7, $8, FALSE)
                                      FROM  action.circulation
                                      WHERE target_copy = cp.id
                                            AND checkin_time IS NULL
                                )x)
                            )
                        ELSE NULL
                    END
                )
          FROM  serial.unit cp
          WHERE id = $1
              AND cp.deleted IS FALSE
          GROUP BY id, status, location, circ_lib, call_number, create_date,
              edit_date, copy_number, circulate, floating, mint_condition,
              deposit, ref, holdable, deleted, deposit_amount, price,
              barcode, circ_modifier, circ_as_type, opac_visible,
              status_changed_time, detailed_contents, sort_key,
              summary_contents, cost, age_protect;
$F$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('1422', :eg_version);

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('circ.holds.ui_require_monographic_part_when_present',
        'Normally the selection of a monographic part during hold placement is optional if there is at least one copy on the bib without a monographic part.  A true value for this setting will require part selection even under this condition.  A true value for this setting will also require a part to be added before saving any changes or creating a new item in the holdings editor, if there are parts on the bib.',
        'coust', 'description')
WHERE name = 'circ.holds.ui_require_monographic_part_when_present';


SELECT evergreen.upgrade_deps_block_check('1423', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.self_register.dob_order',
    'opac',
    'string',
    oils_i18n_gettext(
        'opac.self_register.dob_order',
        'Patron Self-Reg. Date of Birth Order',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.self_register.dob_order',
        'The order in which to present the Month, Day, and Year elements for the Date of Birth field in Patron Self-Registration. Use the letter M for Month, D for Day, and Y for Year. Examples: MDY, DMY, YMD',
        'coust',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.patron.edit.au.usrname.hide',
    'opac',
    'bool',
    oils_i18n_gettext(
        'opac.patron.edit.au.usrname.hide',
        'Hide Username field in Patron Self-Reg.',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.patron.edit.au.usrname.hide',
        'Hides the Requested Username field in the Patron Self-Registration interface.',
        'coust',
        'description'
    )
);


SELECT evergreen.upgrade_deps_block_check('1425', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'ui.toast_duration',
    'gui',
    oils_i18n_gettext('ui.toast_duration',
        'Staff Client toast alert duration (seconds)',
        'coust', 'label'),
    oils_i18n_gettext('ui.toast_duration',
        'The number of seconds a toast alert should remain visible if not manually dismissed. Default is 10.',
        'coust', 'description'),
    'integer'
);


SELECT evergreen.upgrade_deps_block_check('1426', :eg_version);


CREATE TABLE action.hold_request_reset_reason (
    id SERIAL NOT NULL PRIMARY KEY,
    manual BOOLEAN,
    name TEXT UNIQUE
);

CREATE TABLE action.hold_request_reset_reason_entry (
    id SERIAL NOT NULL PRIMARY KEY,
    hold INT REFERENCES action.hold_request (id) DEFERRABLE INITIALLY DEFERRED,
    reset_reason INT REFERENCES action.hold_request_reset_reason (id) DEFERRABLE INITIALLY DEFERRED,
    note TEXT,
    reset_time TIMESTAMP WITH TIME ZONE,
    previous_copy BIGINT REFERENCES asset.copy (id) DEFERRABLE INITIALLY DEFERRED,
    requestor INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    requestor_workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX ahrrre_hold_idx ON action.hold_request_reset_reason_entry (hold);

INSERT INTO action.hold_request_reset_reason (id, name, manual) VALUES
(1,'HOLD_TIMED_OUT',false),
(2,'HOLD_MANUAL_RESET',true),
(3,'HOLD_BETTER_HOLD',false),
(4,'HOLD_FROZEN',true),
(5,'HOLD_UNFROZEN',true),
(6,'HOLD_CANCELED',true),
(7,'HOLD_UNCANCELED',true),
(8,'HOLD_UPDATED',true),
(9,'HOLD_CHECKED_OUT',true),
(10,'HOLD_CHECKED_IN',true);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.hold_retarget_previous_targets_interval', 'holds',
  oils_i18n_gettext('circ.hold_retarget_previous_targets_interval',
    'Retarget previous targets interval',
    'coust', 'label'),
  oils_i18n_gettext('circ.hold_retarget_previous_targets_interval',
    'Hold targeter will create proximity adjustments for previously targeted copies within this time interval (in days).',
    'coust', 'description'),
  'integer', null);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.hold_reset_reason_entry_age_threshold', 'holds',
  oils_i18n_gettext('circ.hold_reset_reason_entry_age_threshold',
    'Hold reset reason entry deletion interval',
    'coust', 'label'),
  oils_i18n_gettext('circ.hold_reset_reason_entry_age_threshold',
    'Hold reset reason entries will be removed if older than this interval. Default 1 year if no value provided.',
    'coust', 'description'),
  'interval', null);



SELECT evergreen.upgrade_deps_block_check('1434', :eg_version); 

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_items_out', 'Self-Checkout Items Out', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET checkouts = template_data.checkouts;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR checkout IN checkouts %]
    <li>
      <div>[% checkout.title %]</div>
      <div>Barcode: [% checkout.copy.barcode %]</div>
      <div>Due Date: [% 
        date.format(helpers.format_date(
            checkout.circ.due_date, staff_org_timezone), '%x %r') 
      %]
      </div>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_items_out';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_holds', 'Self-Checkout Holds', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET holds = template_data.holds;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR hold IN holds %]
    <li>
      <table>
        <tr>
          <td>Title:</td>
          <td>[% hold.title %]</td>
        </tr>
        <tr>
          <td>Author:</td>
          <td>[% hold.author %]</td>
        </tr>
        <tr>
          <td>Pickup Location:</td>
          <td>[% helpers.get_org_unit(hold.pickup_lib).name %]</td>
        </tr>
        <tr>
          <td>Status:</td>
          <td>
            [%- IF hold.ready -%]
                Ready for pickup
            [% ELSE %]
                #[% hold.relative_queue_position %] of [% hold.potentials %] copies.
            [% END %]
          </td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_holds';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_fines', 'Self-Checkout Fines', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    USE money = format('$%.2f');
    SET user = template_data.user;
    SET xacts = template_data.xacts;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR xact IN xacts %]
    [% NEXT IF xact.balance_owed <= 0 %]
    <li>
      <table>
        <tr>
          <td>Details:</td>
          <td>[% xact.details %]</td>
        </tr>
        <tr>
          <td>Total Billed:</td>
          <td>[% money(xact.total_owed) %]</td>
        </tr>
        <tr>
          <td>Total Paid:</td>
          <td>[% money(xact.total_paid) %]</td>
        </tr>
        <tr>
          <td>Balance Owed:</td>
          <td>[% money(xact.balance_owed) %]</td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_fines';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_checkouts', 'Self-Checkout Checkouts', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET checkouts = template_data.checkouts;
    SET lib = staff_org;
    SET hours = lib.hours_of_operation;
    SET lib_addr = staff_org.billing_address || staff_org.mailing_address;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <div>[% lib.name %]</div>
  <div>[% lib_addr.street1 %] [% lib_addr.street2 %]</div>
  <div>[% lib_addr.city %], [% lib_addr.state %] [% lib_addr.post_code %]</div>
  <div>[% lib.phone %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR checkout IN checkouts %]
    <li>
      <div>[% checkout.title %]</div>
      <div>Barcode: [% checkout.barcode %]</div>

      [% IF checkout.ctx.renewalFailure %]
      <div style="color:red;">Renewal Failed</div>
      [% END %]

      <div>Due Date: [% date.format(helpers.format_date(
        checkout.circ.due_date, staff_org_timezone), '%x') %]</div>
    </li>
  [% END %]
  </ol>

  <div>
    Library Hours
    [%- 
        BLOCK format_time;
          IF time;
            date.format(time _ ' 1/1/1000', format='%I:%M %p');
          END;
        END
    -%]
    <div>
      Monday 
      [% PROCESS format_time time = hours.dow_0_open %] 
      [% PROCESS format_time time = hours.dow_0_close %] 
    </div>
    <div>
      Tuesday 
      [% PROCESS format_time time = hours.dow_1_open %] 
      [% PROCESS format_time time = hours.dow_1_close %] 
    </div>
    <div>
      Wednesday 
      [% PROCESS format_time time = hours.dow_2_open %] 
      [% PROCESS format_time time = hours.dow_2_close %] 
    </div>
    <div>
      Thursday
      [% PROCESS format_time time = hours.dow_3_open %] 
      [% PROCESS format_time time = hours.dow_3_close %] 
    </div>
    <div>
      Friday
      [% PROCESS format_time time = hours.dow_4_open %] 
      [% PROCESS format_time time = hours.dow_4_close %] 
    </div>
    <div>
      Saturday
      [% PROCESS format_time time = hours.dow_5_open %] 
      [% PROCESS format_time time = hours.dow_5_close %] 
    </div>
    <div>
      Sunday 
      [% PROCESS format_time time = hours.dow_6_open %] 
      [% PROCESS format_time time = hours.dow_6_close %] 
    </div>
  </div>

</div>
$TEMPLATE$ WHERE name = 'scko_checkouts';





-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1435', :eg_version);

-- 002.schema.config.sql

-- this may grow to support full GNU gettext functionality
CREATE TABLE config.i18n_string (
    id              SERIAL      PRIMARY KEY,
    context         TEXT        NOT NULL, -- hint for translators to disambiguate
    string          TEXT        NOT NULL
);

-- 950.data.seed-values.sql

INSERT INTO config.i18n_string (id, context, string) VALUES (1,
    oils_i18n_gettext(
        1, 'In the Place Hold interfaces for staff and patrons; when monographic parts are available, this string provides contextual information about whether and how parts are considered for holds that do not request a specific mongraphic part.',
        'i18ns','context'
    ),
    oils_i18n_gettext(
        1, 'All Parts',
        'i18ns','string'
    )
);
SELECT SETVAL('config.i18n_string_id_seq', 10000); -- reserve some for stock EG interfaces


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1436', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.direct_opt_in_check(
    patron_id   INT,
    staff_id    INT, -- patron must be opted in (directly or implicitly) to one of the staff's working locations
    permlist    TEXT[] DEFAULT '{}'::TEXT[] -- if passed, staff must ADDITIONALLY possess at least one of these permissions at an opted-in location
) RETURNS BOOLEAN AS $f$
DECLARE
    default_boundary    INT;
    org_depth           INT;
    patron              actor.usr%ROWTYPE;
    staff               actor.usr%ROWTYPE;
    patron_visible_at   INT[];
    patron_hard_wall    INT[];
    staff_orgs          INT[];
    current_staff_org   INT;
    passed_optin        BOOL;
BEGIN
    passed_optin := FALSE;

    SELECT * INTO patron FROM actor.usr WHERE id = patron_id;
    SELECT * INTO staff FROM actor.usr WHERE id = staff_id;

    IF patron.id IS NULL OR staff.id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- get the hard wall, if any
    SELECT oils_json_to_text(value)::INT INTO default_boundary
      FROM actor.org_unit_ancestor_setting('org.restrict_opt_to_depth', patron.home_ou);

    IF default_boundary IS NULL THEN default_boundary := 0; END IF;

    IF default_boundary = 0 THEN -- common case
        SELECT ARRAY_AGG(id) INTO patron_hard_wall FROM actor.org_unit;
    ELSE
        -- Patron opt-in scope(s), including home_ou from default_boundary depth
        SELECT  ARRAY_AGG(id) INTO patron_hard_wall
          FROM  actor.org_unit_descendants(patron.home_ou, default_boundary);
    END IF;

    -- gather where the patron has opted in, and their home
    SELECT  COALESCE(ARRAY_AGG(DISTINCT aoud.id),'{}') INTO patron_visible_at
      FROM  actor.usr_org_unit_opt_in auoi
            JOIN LATERAL actor.org_unit_descendants(auoi.org_unit) aoud ON TRUE
      WHERE auoi.usr = patron.id;

    patron_visible_at := patron_visible_at || patron.home_ou;

    <<staff_org_loop>>
    FOR current_staff_org IN SELECT work_ou FROM permission.usr_work_ou_map WHERE usr = staff.id LOOP

        SELECT oils_json_to_text(value)::INT INTO org_depth
          FROM actor.org_unit_ancestor_setting('org.patron_opt_boundary', current_staff_org);

        IF FOUND THEN
            SELECT ARRAY_AGG(DISTINCT id) INTO staff_orgs FROM actor.org_unit_descendants(current_staff_org,org_depth);
        ELSE
            SELECT ARRAY_AGG(DISTINCT id) INTO staff_orgs FROM actor.org_unit_descendants(current_staff_org);
        END IF;

        -- If this staff org (adjusted) isn't at least partly inside the allowed range, move on.
        IF NOT (staff_orgs && patron_hard_wall) THEN CONTINUE staff_org_loop; END IF;

        -- If this staff org (adjusted) overlaps with the patron visibility list
        IF staff_orgs && patron_visible_at THEN passed_optin := TRUE; EXIT staff_org_loop; END IF;

    END LOOP staff_org_loop;

    -- does the staff member have a requested permission where the patron lives or has opted in?
    IF passed_optin AND cardinality(permlist) > 0 THEN
        SELECT  ARRAY_AGG(id) INTO staff_orgs
          FROM  UNNEST(permlist) perms (p)
                JOIN LATERAL permission.usr_has_perm_at_all(staff.id, perms.p) perms_at (id) ON TRUE;

        passed_optin := COALESCE(staff_orgs && patron_visible_at, FALSE);
    END IF;

    RETURN passed_optin;

END;
$f$ STABLE LANGUAGE PLPGSQL;

-- This function defaults to RESTRICTING access to data if applied to
-- a table/class that it does not explicitly know how to handle.
CREATE OR REPLACE FUNCTION evergreen.hint_opt_in_check(
    hint_val    TEXT,
    pkey_val    BIGINT, -- pkey value of the hinted row
    staff_id    INT,
    permlist    TEXT[] DEFAULT '{}'::TEXT[] -- if passed, staff must ADDITIONALLY possess at least one of these permissions at an opted-in location
) RETURNS BOOLEAN AS $f$
BEGIN
    CASE hint_val
        WHEN 'aua' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_address WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'auact' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_activity WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'aus' THEN
            RETURN evergreen.direct_opt_in_check((SELECT usr FROM actor.usr_setting WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'actscecm' THEN
            RETURN evergreen.direct_opt_in_check((SELECT target_usr FROM actor.stat_cat_entry_usr_map WHERE id = pkey_val LIMIT 1), staff_id, permlist);
        WHEN 'ateo' THEN
            RETURN evergreen.direct_opt_in_check(
                (SELECT e.context_user FROM action_trigger.event e JOIN action_trigger.event_output eo ON (eo.event = e.id) WHERE eo.id = pkey_val LIMIT 1),
                staff_id,
                permlist
            );
        ELSE
            RETURN FALSE;
    END CASE;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.redact_value(
    input_data      anycompatible,
    skip_redaction  BOOLEAN         DEFAULT FALSE,  -- pass TRUE for "I passed the test!" and avoid redaction
    redact_with     anycompatible   DEFAULT NULL
) RETURNS anycompatible AS $f$
DECLARE
    result ALIAS FOR $0;
BEGIN
    IF skip_redaction THEN
        result := input_data;
    ELSE
        result := redact_with;
    END IF;

    RETURN result;
END;
$f$ STABLE LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1437', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'holds',
    'circ.holds.adjacent_target_while_stalling', 'bool',
    oils_i18n_gettext(
        'circ.holds.adjacent_target_while_stalling',
        'Allow adjacent copies to capture when Soft Stalling',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.holds.adjacent_target_while_stalling',
        'Allow adjacent copies at the targeted library to capture when Soft Stalling interval is set',
        'coust',
        'description'
    )
);


SELECT evergreen.upgrade_deps_block_check('1438', :eg_version);

ALTER TABLE biblio.monograph_part
    ADD COLUMN creator INTEGER DEFAULT 1,
    ADD COLUMN editor INTEGER DEFAULT 1,
    ADD COLUMN create_date TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN edit_date TIMESTAMPTZ DEFAULT now();

UPDATE biblio.monograph_part SET creator=1, editor=1, create_date=now(),edit_date=now();

ALTER TABLE biblio.monograph_part
    ALTER COLUMN creator SET NOT NULL,
    ALTER COLUMN editor SET NOT NULL,
    ALTER COLUMN create_date SET NOT NULL,
    ALTER COLUMN edit_date SET NOT NULL;


SELECT evergreen.upgrade_deps_block_check('1439', :eg_version);

-- Use oils_xpath_table instead of pgxml's xpath_table
CREATE OR REPLACE FUNCTION acq.extract_holding_attr_table (lineitem int, tag text) RETURNS SETOF acq.flat_lineitem_holding_subfield AS $$
DECLARE
    counter INT;
    lida    acq.flat_lineitem_holding_subfield%ROWTYPE;
BEGIN

    SELECT  COUNT(*) INTO counter
      FROM  oils_xpath_table(
                'id',
                'marc',
                'acq.lineitem',
                '//*[@tag="' || tag || '"]',
                'id=' || lineitem
            ) as t(i int,c text);

    FOR i IN 1 .. counter LOOP
        FOR lida IN
            SELECT  *
              FROM  (   SELECT  id,i,t,v
                          FROM  oils_xpath_table(
                                    'id',
                                    'marc',
                                    'acq.lineitem',
                                    '//*[@tag="' || tag || '"][position()=' || i || ']/*[text()]/@code|' ||
                                        '//*[@tag="' || tag || '"][position()=' || i || ']/*[@code and text()]',
                                    'id=' || lineitem
                                ) as t(id int,t text,v text)
                    )x
        LOOP
            RETURN NEXT lida;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;



-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1440', :eg_version);

CREATE TABLE config.patron_loader_header_map (
    id SERIAL,
    org_unit INTEGER NOT NULL,
    import_header TEXT NOT NULL,
    default_header TEXT NOT NULL
);
ALTER TABLE config.patron_loader_header_map ADD CONSTRAINT config_patron_loader_header_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE config.patron_loader_value_map (
    id SERIAL,
    org_unit INTEGER NOT NULL,
    mapping_type TEXT NOT NULL,
    import_value TEXT NOT NULL,
    native_value TEXT NOT NULL
);
ALTER TABLE config.patron_loader_value_map ADD CONSTRAINT config_patron_loader_value_map_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE actor.patron_loader_log (
    id SERIAL,
    session BIGINT,
    org_unit INTEGER NOT NULL,
    event TEXT,
    record_count INTEGER,
    logtime TIMESTAMP DEFAULT NOW()
);
ALTER TABLE actor.patron_loader_log ADD CONSTRAINT actor_patron_loader_log_org_fkey FOREIGN KEY (org_unit) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

-- Add bib bucket related columns to reporter.schedule


SELECT evergreen.upgrade_deps_block_check('1441', :eg_version);

ALTER TABLE reporter.schedule ADD COLUMN new_record_bucket BOOL NOT NULL DEFAULT 'false';
ALTER TABLE reporter.schedule ADD COLUMN existing_record_bucket BOOL NOT NULL DEFAULT 'false';

CREATE TABLE container.biblio_record_entry_bucket_shares (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    share_org   INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT brebs_org_once_per_bucket UNIQUE (bucket, share_org)
);

CREATE TYPE container.usr_flag_type AS ENUM ('favorite');
CREATE TABLE container.biblio_record_entry_bucket_usr_flags (
    id          SERIAL      PRIMARY KEY,
    bucket      INT         NOT NULL REFERENCES container.biblio_record_entry_bucket (id) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    usr         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    flag        container.usr_flag_type NOT NULL DEFAULT 'favorite',
    CONSTRAINT brebs_flag_once_per_usr_per_bucket UNIQUE (bucket, usr, flag)
);

-- Add settings for record bucket interfaces

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record_buckets', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record_buckets',
        'Grid Config: catalog.record_buckets',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.record_bucket.content', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record_bucket.content',
        'Grid Config: catalog.record_bucket.content',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.record_buckets', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.record_buckets',
        'Grid Filters: catalog.record_buckets',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.record_bucket.content', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.record_bucket.content',
        'Grid Filters: catalog.record_bucket.content',
        'cwst', 'label'
    )
), (
    'eg.grid.buckets.user_shares', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.buckets.user_shares',
        'Grid Config: eg.grid.buckets.user_shares',
        'cwst', 'label'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   659,
   'TRANSFER_CONTAINER',
   oils_i18n_gettext(659,
     'Allow for transferring ownership of a bucket.', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'TRANSFER_CONTAINER');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   660,
   'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE',
   oils_i18n_gettext(660,
     'Allow sharing of record buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   661,
   'ADMIN_CONTAINER_CALL_NUMBER_USER_SHARE',
   oils_i18n_gettext(661,
     'Allow sharing of call number buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_CALL_NUMBER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   662,
   'ADMIN_CONTAINER_COPY_USER_SHARE',
   oils_i18n_gettext(662,
     'Allow sharing of copy buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_COPY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   663,
   'ADMIN_CONTAINER_USER_USER_SHARE',
   oils_i18n_gettext(663,
     'Allow sharing of user buckets with specific users', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_USER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   664,
   'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE',
   oils_i18n_gettext(664,
     'Allow viewing of record bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   665,
   'VIEW_CONTAINER_CALL_NUMBER_USER_SHARE',
   oils_i18n_gettext(665,
     'Allow viewing of call number bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_CALL_NUMBER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   666,
   'VIEW_CONTAINER_COPY_USER_SHARE',
   oils_i18n_gettext(666,
     'Allow viewing of copy bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_COPY_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   667,
   'VIEW_CONTAINER_USER_USER_SHARE',
   oils_i18n_gettext(667,
     'Allow viewing of user bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_USER_USER_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   668,
   'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE',
   oils_i18n_gettext(668,
     'Allow sharing of record buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   669,
   'ADMIN_CONTAINER_CALL_NUMBER_ORG_SHARE',
   oils_i18n_gettext(669,
     'Allow sharing of call number buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_CALL_NUMBER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   670,
   'ADMIN_CONTAINER_COPY_ORG_SHARE',
   oils_i18n_gettext(670,
     'Allow sharing of copy buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_COPY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   671,
   'ADMIN_CONTAINER_USER_ORG_SHARE',
   oils_i18n_gettext(671,
     'Allow sharing of user buckets with specific orgs', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CONTAINER_USER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   672,
   'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE',
   oils_i18n_gettext(672,
     'Allow viewing of record bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   673,
   'VIEW_CONTAINER_CALL_NUMBER_ORG_SHARE',
   oils_i18n_gettext(673,
     'Allow viewing of call number bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_CALL_NUMBER_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   674,
   'VIEW_CONTAINER_COPY_ORG_SHARE',
   oils_i18n_gettext(674,
     'Allow viewing of copy bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_COPY_ORG_SHARE');

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   675,
   'VIEW_CONTAINER_USER_ORG_SHARE',
   oils_i18n_gettext(675,
     'Allow viewing of user bucket user shares', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'VIEW_CONTAINER_USER_ORG_SHARE');

UPDATE  config.ui_staff_portal_page_entry
  SET   target_url = '/eg2/staff/cat/bucket/record'
  WHERE id = 7
        AND entry_type = 'menuitem'
        AND target_url = '/eg/staff/cat/bucket/record/'
;


SELECT evergreen.upgrade_deps_block_check('1442', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.staff.catalog.results.show_sidebar',
    'gui',
    oils_i18n_gettext('eg.staff.catalog.results.show_sidebar',
        'Staff catalog: show sidebar',
        'coust', 'label'),
    oils_i18n_gettext('eg.staff.catalog.results.show_sidebar',
        'Show the sidebar in staff catalog search results. Default is true.',
        'coust', 'description'),
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1443', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_names',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_names',
        'Staff Client patron search: show name fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_names',
        'Displays the name row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_ids',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_ids',
        'Staff Client patron search: show ID fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_ids',
        'Displays the ID row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.circ.patron.search.show_address',
    'gui',
    oils_i18n_gettext('eg.circ.patron.search.show_address',
        'Staff Client patron search: show address fields',
        'coust', 'label'),
    oils_i18n_gettext('eg.circ.patron.search.show_address',
        'Displays the address row of advanced patron search fields',
        'coust', 'description'),
    'bool'
);

COMMIT;

-- MFA (1433) needs two transactions of its own

BEGIN;
SELECT evergreen.upgrade_deps_block_check('1433', :eg_version);

-- This has to happen outside the transaction that uses it below.
ALTER TYPE config.usr_activity_group ADD VALUE IF NOT EXISTS 'mfa';

COMMIT;

BEGIN;
-- Permission seed data 
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 657, 'REMOVE_USER_MFA', oils_i18n_gettext(657,
                    'Remove configured MFA factors for another user', 'ppl', 'description')),

    -- XXX Update the YAOUS update_perm below with the ADMIN_MFA permission id if it changes at commit time!!!
 ( 658, 'ADMIN_MFA', oils_i18n_gettext(658,
                    'Configure Multi-factor Authentication', 'ppl', 'description'))
;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, grp, update_perm )
    VALUES (
        'auth.mfa_expire_interval',
        oils_i18n_gettext(
            'auth.mfa_expire_interval',
            'Security: MFA recheck interval',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'auth.mfa_expire_interval',
            'How long before MFA verification is required again, when MFA is required for a user.',
            'coust',
            'description'
        ),
        'interval',
        'sec',
        658 -- XXX Update this with the ADMIN_MFA permission id if that changes at commit time!!!
    );

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'mfa.send_email', 'au', 'User has requested a One-Time MFA code by email'),
( 'mfa.send_sms', 'au', 'User has requested a One-Time MFA code by SMS');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send One-Time Password Email', 'mfa.send_email', 'NOOP_True', 'SendEmail', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- user_data.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Your Library One-Time access code
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

We will never call to ask you for this code, and make sure you do not share it with anyone calling you directly.

Use this code to continue logging in to your Evergreen account:

One-Time code: [% user_data.otp_code %]

Sincerely,
[% user_data.issuer %] - [% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send One-Time Password SMS', 'mfa.send_sms', 'NOOP_True', 'SendSMS', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = user.home_ou -%]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(user_data.carrier,user_data.phone) %]
Subject: One-Time code

Your [% user_data.issuer %] code is: [%user_data.otp_code %] $$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou');

-- New stuff!
CREATE TABLE IF NOT EXISTS config.mfa_factor (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL,
    description TEXT    NOT NULL
);

INSERT INTO config.mfa_factor (name, label, description) VALUES
  ('webauthn', 'Web Authentication API', 'Uses external Public Key credentials to confirm authentication'),
  ('totp', 'Time-based One-Time Password', 'For use with TOTP applications such as Google Authenticator'),
  ('email', 'One-Time Password by Email', 'Uses a dedicated MFA email address to confirm authentication'),
  ('sms', 'One-Time Password by SMS', 'Uses a dedicated MFA phone number and carrier to confirm authentication'),
  ('static', 'Pre-generated backup passwords', 'Confirms authentication via pre-shared One-Time passwords')
;

CREATE TABLE IF NOT EXISTS actor.usr_mfa_exception (
    id      SERIAL  PRIMARY KEY,
    usr     BIGINT  NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    ingress TEXT    -- disregard MFA requirement for specific ehow (ingress types, like 'sip2'), or NULL for all
); 

CREATE TABLE IF NOT EXISTS actor.usr_mfa_factor_map (
    id          SERIAL  PRIMARY KEY,
    usr         BIGINT  NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    factor      TEXT    NOT NULL REFERENCES config.mfa_factor (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    purpose     TEXT    NOT NULL DEFAULT 'mfa', -- mfa || login, for now
    add_time    TIMESTAMPTZ NOT NULL DEFAULT NOW()
); 
CREATE UNIQUE INDEX IF NOT EXISTS factor_purpose_usr_once ON actor.usr_mfa_factor_map (usr, purpose, factor);

CREATE TABLE IF NOT EXISTS permission.group_mfa_factor_map (
    id      SERIAL  PRIMARY KEY,
    grp     BIGINT  NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    factor  TEXT    NOT NULL REFERENCES config.mfa_factor (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE permission.grp_tree
    ADD COLUMN IF NOT EXISTS mfa_allowed BOOL NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS mfa_required BOOL NOT NULL DEFAULT FALSE;

INSERT INTO config.usr_activity_type (id, ewhat, egroup, label)
    VALUES (31, 'confirm', 'mfa', 'Generic MFA authentication confirmation')
    ;--ON CONFLICT DO NOTHING;

ALTER TABLE actor.usr_activity
    ADD COLUMN IF NOT EXISTS event_data TEXT;

DROP FUNCTION actor.insert_usr_activity(INT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION actor.insert_usr_activity(usr INT, ewho TEXT, ewhat TEXT, ehow TEXT, edata TEXT DEFAULT NULL)
 RETURNS SETOF actor.usr_activity
AS $f$
DECLARE
    new_row actor.usr_activity%ROWTYPE;
BEGIN
    SELECT id INTO new_row.etype FROM actor.usr_activity_get_type(ewho, ewhat, ehow);
    IF FOUND THEN
        new_row.usr := usr;
        new_row.event_data := edata;
        INSERT INTO actor.usr_activity (usr, etype, event_data)
            VALUES (usr, new_row.etype, new_row.event_data)
            RETURNING * INTO new_row;
        RETURN NEXT new_row;
    END IF;
END;
$f$ LANGUAGE plpgsql;

----- Support functions for encoding WebAuthn -----
CREATE OR REPLACE FUNCTION evergreen.gen_random_bytes_b64 (INT) RETURNS TEXT AS $f$
    SELECT encode(gen_random_bytes($1),'base64');
$f$ STRICT IMMUTABLE LANGUAGE SQL;


----- Support functions for encoding URLs -----
CREATE OR REPLACE FUNCTION evergreen.encode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return encode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.decode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return decode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_escape (TEXT) RETURNS TEXT AS $f$
  use URI::Escape;
  my $input = shift;
  return uri_escape_utf8($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_unescape (TEXT) RETURNS TEXT AS $f$
  my $input = shift;
  $input =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # inline the RE, it is 700% faster than URI::Escape::uri_unescape
  return $input;
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

----- Flags used to control OTP calculations -----
INSERT INTO config.global_flag (name, label, value, enabled) VALUES
    ('webauthn.mfa.issuer', 'WebAuthn Relying Party name for multi-factor authentication', 'Evergreen WebAuthn', TRUE),
    ('webauthn.mfa.domain', 'WebAuthn Relying Party domain (optional base domain) for multi-factor authentication', '', TRUE),
    ('webauthn.mfa.digits', 'WebAuthn challenge size (bytes)', '16', TRUE),
    ('webauthn.mfa.period', 'WebAuthn challenge timeout (seconds)', '60', TRUE), -- 1 minute for WebAuthn
    ('webauthn.mfa.multicred', 'If Enabled, allows a user to register multiple multi-factor login WebAuthn verification devices', NULL, TRUE),
    ('webauthn.login.issuer', 'WebAuthn Relying Party name for single-factor login', 'Evergreen WebAuthn', TRUE),
    ('webauthn.login.domain', 'WebAuthn Relying Party domain (optional base domain) for single-factor login', '', TRUE),
    ('webauthn.login.digits', 'WebAuthn single-factor login challenge size (bytes)', '16', TRUE),
    ('webauthn.login.period', 'WebAuthn single-factor login challenge timeout (seconds)', '60', TRUE),
    ('webauthn.login.multicred', 'If Enabled, allows a user to register multiple single-factor login WebAuthn verification devices', NULL, TRUE),
    ('totp.mfa.issuer', 'TOTP Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('totp.mfa.digits', 'TOTP code length (Google Authenticator supports only 6)', '6', TRUE),
    ('totp.mfa.algorithm', 'TOTP code generation algorithm (Google Authenticator supports only SHA1)', 'SHA1', TRUE),
    ('totp.mfa.period', 'TOTP code validity period in seconds  (Google Authenticator supports only 30)', '30', TRUE), -- 30 seconds for totp, but remember, fuzziness!
    ('totp.login.issuer', 'TOTP Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('totp.login.digits', 'TOTP code length (Google Authenticator supports only 6)', '6', TRUE),
    ('totp.login.algorithm', 'TOTP code generation algorithm (Google Authenticator supports only SHA1)', 'SHA1', TRUE),
    ('totp.login.period', 'TOTP code validity period in seconds  (Google Authenticator supports only 30)', '30', TRUE),
    ('email.mfa.issuer', 'Email Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('email.mfa.digits', 'Email One-Time code length for multi-factor authentication; max: 8', '6', TRUE),
    ('email.mfa.algorithm', 'Email One-Time code algorithm for multi-factor authentication: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('email.mfa.period', 'Email One-Time validity period for multi-factor authentication in seconds (default: 30 minutes)', '1800', TRUE), -- 30 minutes for email
    ('email.login.issuer', 'Email Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('email.login.digits', 'Email One-Time code length for single-factor login; max: 8', '6', TRUE),
    ('email.login.algorithm', 'Email One-Time code algorithm for single-factor login: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('email.login.period', 'Email One-Time validity period for single-factor login in seconds (default: 30 minutes)', '1800', TRUE),
    ('sms.mfa.issuer', 'SMS Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('sms.mfa.digits', 'SMS One-Time code length for multi-factor authentication; max: 8', '6', TRUE),
    ('sms.mfa.algorithm', 'SMS One-Time code algorithm for multi-factor authentication: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('sms.mfa.period', 'SMS One-Time validity period for multi-factor authentication in seconds (default: 15 minutes)', '900', TRUE), -- 15 minutes for SMS
    ('sms.login.issuer', 'SMS Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('sms.login.digits', 'SMS One-Time code length for single-factor login; max: 8', '6', TRUE),
    ('sms.login.algorithm', 'SMS One-Time code algorithm for single-factor login: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('sms.login.period', 'SMS One-Time validity period for single-factor login in seconds (default: 15 minutes)', '900', TRUE)
;

----- Password types to support secondary factors -----
INSERT INTO actor.passwd_type (code, name) VALUES
    ('email-mfa', 'Time-base One-Time Password Secret for multi-factor authentication via EMail'),
    ('email-login', 'Time-base One-Time Password Secret for single-factor login via EMail'),
    ('sms-mfa', 'Time-base One-Time Password Secret for multi-factor authentication via SMS'),
    ('sms-login', 'Time-base One-Time Password Secret for single-factor login via SMS'),
    ('totp-mfa', 'Time-base One-Time Password Secret for multi-factor authentication'),
    ('totp-login', 'Time-base One-Time Password Secret for single-factor login'),
    ('webauthn-mfa', 'WebAuthn data for multi-factor authentication'),
    ('webauthn-login', 'WebAuthn data for single-factor login')
;

----- OTP URI destroyer: Removes the TOTP password entry if the user knows the secret NOW -----
CREATE OR REPLACE FUNCTION actor.remove_otpauth_uri(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    proof TEXT,
    fuzziness INT DEFAULT 1
) RETURNS BOOL AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $usr_id = shift;
my $otype = shift;
my $purpose = shift;
my $proof = shift;
my $fuzziness_width = shift // 1;

if ($otype eq 'webauthn') { # nothing to prove
    my $waq = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
    my $res = spi_exec_prepared($waq, $usr_id, $otype, $purpose);
    spi_freeplan($waq);
    return 1;
}

# Normalize the proof value
$proof =~ s/\D//g;
return 0 unless $proof; # all-0s is not valid

my $q = spi_prepare('SELECT actor.otpauth_uri($1, $2, $3) AS uri;', 'INTEGER', 'TEXT', 'TEXT');
my $otp_uri = spi_exec_prepared($q, {limit => 1}, $usr_id, $otype, $purpose)->{rows}[0]{uri};
spi_freeplan($q);

return 0 unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    my $otp_code = Pass::OTP::otp(%otp_config);
    if ($otp_code eq $proof) {
        $q = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
        my $res = spi_exec_prepared($q, $usr_id, $otype, $purpose);
        spi_freeplan($q);
        return 1;
    }
}

return 0;
$f$ LANGUAGE PLPERLU;

----- OTP proof generator: find the TOTP code, optionally with fuzziness -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    otp_uri TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $otp_uri = shift;
my $fuzziness_width = shift // 0;

return undef unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);
return undef unless $otp_config{type};

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    return_next({period_step => $fuzziness, proof => Pass::OTP::otp(%otp_config)});
}

return undef;

$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$
BEGIN
    RETURN QUERY
      SELECT * FROM actor.otpauth_uri_get_proof( actor.otpauth_uri($1, $2, $3), $4 );
    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

----- TOTP URI generator: Saves the secret on the first call for each user ID -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri(
    usr_id INT,
    otype TEXT DEFAULT 'totp',
    purpose TEXT DEFAULT 'mfa',
    additional_params HSTORE DEFAULT ''::HSTORE -- this can be used to pass a start-time parameter to offset totp calc
) RETURNS TEXT AS $f$
DECLARE
    issuer      TEXT := 'Evergreen';
    algorithm   TEXT := 'SHA1';
    digits      TEXT := '6';
    period      TEXT := '30';
    counter     TEXT := '0';
    otp_secret  TEXT;
    otp_params  HSTORE;
    uri         TEXT;
    param_name  TEXT;
    uri_otype  TEXT;
BEGIN

    IF additional_params IS NULL THEN additional_params = ''::HSTORE; END IF;

    -- we're going to be a bit strict here, for now
    IF otype NOT IN ('webauthn','email','sms','totp','hotp') THEN RETURN NULL; END IF;
    IF purpose NOT IN ('mfa','login') THEN RETURN NULL; END IF;

    uri_otype := otype;
    IF otype NOT IN ('totp','hotp') THEN
        uri_otype := 'totp'; -- others are time-based, but with different settings
    END IF;

    -- protect "our" keys
    additional_params := additional_params - ARRAY['issuer','algorithm','digits','period'];

    SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM actor.passwd WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;

    IF NOT FOUND THEN

        issuer := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.issuer' AND enabled),
            issuer
        );

        algorithm := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.algorithm' AND enabled),
            algorithm
        );

        digits := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.digits' AND enabled),
            digits
        );

        period := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.period' AND enabled),
            period
        );

        otp_params := HSTORE('counter', counter)
                      || HSTORE('issuer', issuer)
                      || HSTORE('algorithm', UPPER(algorithm))
                      || HSTORE('digits', digits)
                      || HSTORE('period', period);

        IF additional_params ? 'counter' THEN
            otp_params := otp_params - 'counter';
        END IF;

        otp_params := additional_params || otp_params;

        WITH new_secret AS (
            INSERT INTO actor.passwd (usr, salt, passwd, passwd_type)
                VALUES (usr_id, otp_params::TEXT, gen_random_uuid()::TEXT, otype || '-' || purpose)
                RETURNING passwd, salt
        ) SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM new_secret;

    ELSE
        otp_params := otp_params - akeys(additional_params); -- remove what we're receiving
        otp_params := additional_params || otp_params;
        IF additional_params != ''::HSTORE THEN -- new additional params were passed, let's save the salt again
            UPDATE actor.passwd SET salt = otp_params::TEXT WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;
        END IF;
    END IF;


    uri :=  'otpauth://' || uri_otype || '/' || evergreen.uri_escape(otp_params -> 'issuer') || ':' || usr_id::TEXT
            ||'?secret='    || evergreen.encode_base32(otp_secret);

    FOREACH param_name IN ARRAY akeys(otp_params) LOOP
        uri := uri || '&' || evergreen.uri_escape(param_name) || '=' || evergreen.uri_escape(otp_params -> param_name);
    END LOOP;

    RETURN uri;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;


-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
