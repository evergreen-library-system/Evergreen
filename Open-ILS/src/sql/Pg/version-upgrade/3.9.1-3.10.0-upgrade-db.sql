--Upgrade Script for 3.9.1 to 3.10.0
\set eg_version '''3.10.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.10.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1326', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.config.idl_field_doc', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.config.idl_field_doc',
        'Grid Config: admin.config.idl_field_doc',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1329', :eg_version);

CREATE TABLE config.openathens_uid_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_uid_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname')
;

SELECT SETVAL('config.openathens_uid_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_name_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_name_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname'),
    (3,'fullname')
;

SELECT SETVAL('config.openathens_name_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_identity (
    id                          SERIAL  PRIMARY KEY,
    active                      BOOL    NOT NULL DEFAULT true,
    org_unit                    INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    api_key                     TEXT    NOT NULL,
    connection_id               TEXT    NOT NULL,
    connection_uri              TEXT    NOT NULL,
    auto_signon_enabled         BOOL    NOT NULL DEFAULT true,
    auto_signout_enabled        BOOL    NOT NULL DEFAULT false,
    unique_identifier           INT     NOT NULL REFERENCES config.openathens_uid_field (id) DEFAULT 1,
    display_name                INT     NOT NULL REFERENCES config.openathens_name_field (id) DEFAULT 1,
    release_prefix              BOOL    NOT NULL DEFAULT false,
    release_first_given_name    BOOL    NOT NULL DEFAULT false,
    release_second_given_name   BOOL    NOT NULL DEFAULT false,
    release_family_name         BOOL    NOT NULL DEFAULT false,
    release_suffix              BOOL    NOT NULL DEFAULT false,
    release_email               BOOL    NOT NULL DEFAULT false,
    release_home_ou             BOOL    NOT NULL DEFAULT false,
    release_barcode             BOOL    NOT NULL DEFAULT false
);


INSERT INTO permission.perm_list ( id, code, description) VALUES 
  ( 639, 'ADMIN_OPENATHENS', oils_i18n_gettext(639,
     'Allow a user to administer OpenAthens authentication service', 'ppl', 'description'));



SELECT evergreen.upgrade_deps_block_check('1330', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.negative_balances', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.admin.local.negative_balances',
        'Patrons With Negative Balances Grid Settings',
        'cwst', 'label'
    )
), (
    'eg.orgselect.admin.local.negative_balances', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.admin.local.negative_balances',
        'Default org unit for patron negative balances interface',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1331', :eg_version);

INSERT into config.org_unit_setting_type
    (name, datatype, grp, label, description)
VALUES (
    'ui.staff.traditional_catalog.enabled', 'bool', 'gui',
    oils_i18n_gettext(
        'ui.staff.traditional_catalog.enabled',
        'GUI: Enable Traditional Staff Catalog',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.staff.traditional_catalog.enabled',
        'Display an entry point in the browser client for the ' ||
        'traditional staff catalog.',
        'coust', 'description'
    )
);




SELECT evergreen.upgrade_deps_block_check('1332', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES

( 'acq.default_owning_lib_for_auto_lids_strategy', 'acq',
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'How to set default owning library for auto-created line item items',
        'coust', 'label'),
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids_strategy',
        'Stategy to use to set default owning library to set when line item items are auto-created because the provider''s default copy count has been set. Valid values are "workstation" to use the workstation library, "blank" to leave it blank, and "use_setting" to use the "Default owning library for auto-created line item items" setting. If not set, the workstation library will be used.',
        'coust', 'description'),
    'string', null)
,( 'acq.default_owning_lib_for_auto_lids', 'acq',
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids',
        'Default owning library for auto-created line item items',
        'coust', 'label'),
    oils_i18n_gettext('acq.default_owning_lib_for_auto_lids',
        'The default owning library to set when line item items are auto-created because the provider''s default copy count has been set. This applies if the "How to set default owning library for auto-created line item items" setting is set to "use_setting".',
        'coust', 'description'),
    'link', 'aou')
;


SELECT evergreen.upgrade_deps_block_check('1333', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.lineitem.history', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.lineitem.history',
        'Grid Config: Acq Lineitem History',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.po.history', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.po.history',
        'Grid Config: Acq PO History',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.po.edi_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.po.edi_messages',
        'Grid Config: Acq PO EDI Messages',
        'cwst', 'label'
    )
), (
    'acq.lineitem.page_size', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.page_size',
        'ACQ Lineitem List Page Size',
        'cwst', 'label'
    )
), (
    'ui.staff.angular_acq_search.enabled', 'gui', 'bool',
    oils_i18n_gettext(
        'ui.staff.angular_acq_search.enabled',
        'Enable Experimental ACQ Selection/Purchase Search Interface Links',
        'cwst', 'label'
    )
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (
    5, 'lineitem_worksheet', 'Lineitem Worksheet', 1, TRUE, 'en-US',
$TEMPLATE$
[%- 
  USE money=format('%.2f');
  USE date;
  SET li = template_data.lineitem;
  SET title = '';
  SET author = '';
  FOREACH attr IN li.attributes;
    IF attr.attr_type == 'lineitem_marc_attr_definition';
      IF attr.attr_name == 'title';
        title = attr.attr_value;
      ELSIF attr.attr_name == 'author';
        author = attr.attr_value;
      END;
    END;
  END;
-%]

<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>
        <div>Title: [% title.substr(0, 80) %][% IF title.length > 80 %]...[% END %]</div>
        <div>Author: [% author %]</div>
        <div>Item Count: [% li.lineitem_details.size %]</div>
        <div>Lineitem ID: [% li.id %]</div>
        <div>PO # : [% li.purchase_order %]</div>
        <div>Est. Price: [% money(li.estimated_unit_price) %]</div>
        <div>Open Holds: [% template_data.hold_count %]</div>
        [% IF li.cancel_reason.label %]
        <div>[% li.cancel_reason.label %]</div>
        [% END %]

        [% IF li.distribution_formulas.size > 0 %]
            [% SET forms = [] %]
            [% FOREACH form IN li.distribution_formulas; forms.push(form.formula.name); END %]
            <div>Distribution Formulas: [% forms.join(',') %]</div>
        [% END %]

        [% IF li.lineitem_notes.size > 0 %]
            Lineitem Notes:
            <ul>
                [%- FOR note IN li.lineitem_notes -%]
                    <li>
                    [% IF note.alert_text %]
                        [% note.alert_text.code -%] 
                        [% IF note.value -%]
                            : [% note.value %]
                        [% END %]
                    [% ELSE %]
                        [% note.value -%] 
                    [% END %]
                    </li>
                [% END %]
            </ul>
        [% END %]
    </div>
    <br/>
    <table>
        <thead>
            <tr>
                <th>Branch</th>
                <th>Barcode</th>
                <th>Call Number</th>
                <th>Fund</th>
                <th>Shelving Location</th>
                <th>Recd.</th>
                <th>Notes</th>
                <th>Delayed / Canceled</th>
            </tr>
        </thead>
        <tbody>
        <!-- set detail.owning_lib from fm object to org name -->
        [% FOREACH detail IN li.lineitem_details %]
            [% detail.owning_lib = detail.owning_lib.shortname %]
        [% END %]

        [% FOREACH detail IN li.lineitem_details.sort('owning_lib') %]
            [% 
                IF detail.eg_copy_id;
                    SET copy = detail.eg_copy_id;
                    SET cn_label = copy.call_number.label;
                ELSE; 
                    SET copy = detail; 
                    SET cn_label = detail.cn_label;
                END 
            %]
            <tr>
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td style='padding:5px;'>[% detail.owning_lib %]</td>
                <td style='padding:5px;'>[% IF copy.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF cn_label %]<span class="cn_label" >[% cn_label  %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.fund %]<span class="fund">[% detail.fund.code %] ([% detail.fund.year %])</span>[% END %]</td>
                <td style='padding:5px;'>[% copy.location.name %]</td>
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% date.format(helpers.format_date(detail.recv_time, staff_org_timezone), '%x %r', locale) %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
                <td style='padding:5px;'>[% detail.cancel_reason.label %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$TEMPLATE$
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (6, 'purchase_order', 'Purchase Order', 1, TRUE, 'en-US', 
$TEMPLATE$

[%- 
  USE date;
  USE String;
  USE money=format('%.2f');
  SET po = template_data.po;

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
  END;

  BLOCK get_li_order_attr_value;
    FOR attr IN li.attributes;
      IF attr.order_ident == 't';
        attr.attr_value;
        LAST;
      END;
    END;
  END;
-%]

<table style="width:100%">
  <thead>
    <tr>
      <th>PO#</th>
      <th>Line#</th>
      <th>ISBN / Item # / Charge Type</th>
      <th>Title</th>
      <th>Author</th>
      <th>Pub Info</th>
      <th>Quantity</th>
      <th>Unit Price</th>
      <th>Line Total</th>
    </tr>
  </thead>
  <tbody>
[% 
  SET subtotal = 0;
  FOR li IN po.lineitems;

    SET idval = '';
    IF vendnum != '';
      idval = PROCESS get_li_attr attr_name = 'vendor_num';
    END;
    IF !idval;
      idval = PROCESS get_li_order_attr_value;
    END;
-%]
    <tr>
      <td>[% po.id %]</td>
      <td>[% li.id %]</td>
      <td>[% idval %]</td>
      <td>[% PROCESS get_li_attr attr_name = 'title' %]</td>
      <td>[% PROCESS get_li_attr attr_name = 'author' %]</td>
      <td>
        <div>
          [% PROCESS get_li_attr attr_name = 'publisher' %], 
          [% PROCESS get_li_attr attr_name = 'pubdate' %]
        </div>
        <div>Edition: [% PROCESS get_li_attr attr_name = 'edition' %]</div>
      </td>
      [%- 
        SET count = li.lineitem_details.size;
        SET price = li.estimated_unit_price;
        SET itotal = (price * count);
      %]
      <td>[% count %]</td>
      <td>[% money(price) %]</td>
      <td>[% money(litotal) %]</td>
    </tr>
  [% END %]

  </tbody>
</table>



$TEMPLATE$
);





SELECT evergreen.upgrade_deps_block_check('1334', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.acq.picklist.upload.templates','acq','object',
    oils_i18n_gettext(
        'eg.acq.picklist.upload.templates',
        'Acq Picklist Uploader Templates',
        'cwst','label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1335', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'acq.lineitem.sort_order', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.sort_order',
        'ACQ Lineitem List Sort Order',
        'cwst', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, grp, datatype, label)
VALUES (
    'ui.staff.acq.show_deprecated_links', 'gui', 'bool',
    oils_i18n_gettext(
        'ui.staff.acq.show_deprecated_links',
        'Display Links to Deprecated Acquisitions Interfaces',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1336', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.admin.actor.org_unit_settings', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.actor.org_unit_settings',
        'Grid Config: admin.actor.org_unit_settings',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1342', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, datatype, description, grp, update_perm, view_perm) 
VALUES (
    'circ.permit_renew_when_exceeds_fines',
    oils_i18n_gettext(
        'circ.permit_renew_when_exceeds_fines',
        'Permit renewals when patron exceeds max fine threshold',
        'coust',
        'label'
    ),
    'bool',
    oils_i18n_gettext(
        'circ.permit_renew_when_exceeds_fines',
        'Permit renewals even when the patron exceeds the maximum fine threshold',
        'coust',
        'description'
    ),
    'opac',
    93,
    NULL
);

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    circ_limit_set          config.circ_limit_set%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    permit_renew            TEXT;
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Need user info to look up matchpoints
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user AND NOT deleted;

    -- (Insta)Fail if we couldn't find the user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Need item info to look up matchpoints
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item AND NOT deleted;

    -- (Insta)Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, item_object, user_object, renewal);

    circ_matchpoint             := circ_test.matchpoint;
    result.matchpoint           := circ_matchpoint.id;
    result.circulate            := circ_matchpoint.circulate;
    result.duration_rule        := circ_matchpoint.duration_rule;
    result.recurring_fine_rule  := circ_matchpoint.recurring_fine_rule;
    result.max_fine_rule        := circ_matchpoint.max_fine_rule;
    result.hard_due_date        := circ_matchpoint.hard_due_date;
    result.renewals             := circ_matchpoint.renewals;
    result.grace_period         := circ_matchpoint.grace_period;
    result.buildrows            := circ_test.buildrows;

    -- (Insta)Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- All failures before this point are non-recoverable
    -- Below this point are possibly overridable failures

    -- Fail if the user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
    IF item_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item isn't in a circulateable status on a non-renewal
    IF NOT renewal AND item_object.status NOT IN ( 0, 7, 8 ) THEN 
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    -- Alternately, fail if the item isn't checked out on a renewal
    ELSIF renewal AND item_object.status <> 1 THEN
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate because of the shelving location
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;
    IF item_location_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy_location.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Use Circ OU for penalties and such
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( circ_ou );

    IF renewal THEN
        penalty_type = '%RENEW%';
    ELSE
        penalty_type = '%CIRC%';
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        -- override PATRON_EXCEEDS_FINES penalty for renewals based on org setting
        IF renewal AND standing_penalty.name = 'PATRON_EXCEEDS_FINES' THEN
            SELECT INTO permit_renew value FROM actor.org_unit_ancestor_setting('circ.permit_renew_when_exceeds_fines', circ_ou);
            IF permit_renew IS NOT NULL AND permit_renew ILIKE 'true' THEN
                CONTINUE;
            END IF;
        END IF;

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the test is set to hard non-circulating
    IF circ_matchpoint.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_matchpoint.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_matchpoint.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_matchpoint.available_copy_hold_ratio IS NOT NULL THEN
        IF hold_ratio.hold_count IS NULL THEN
            SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        END IF;
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_matchpoint.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the user has too many items out by defined limit sets
    FOR circ_limit_set IN SELECT ccls.* FROM config.circ_limit_set ccls
      JOIN config.circ_matrix_limit_set_map ccmlsm ON ccmlsm.limit_set = ccls.id
      WHERE ccmlsm.active AND ( ccmlsm.matchpoint = circ_matchpoint.id OR
        ( ccmlsm.matchpoint IN (SELECT * FROM unnest(result.buildrows)) AND ccmlsm.fallthrough )
        ) LOOP
            IF circ_limit_set.items_out > 0 AND NOT renewal THEN
                SELECT INTO context_org_list ARRAY_AGG(aou.id)
                  FROM actor.org_unit_full_path( circ_ou ) aou
                    JOIN actor.org_unit_type aout ON aou.ou_type = aout.id
                  WHERE aout.depth >= circ_limit_set.depth;
                IF circ_limit_set.global THEN
                    WITH RECURSIVE descendant_depth AS (
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                        WHERE ou.id IN (SELECT * FROM unnest(context_org_list))
                            UNION
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                            JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
                    ) SELECT INTO context_org_list ARRAY_AGG(ou.id) FROM actor.org_unit ou JOIN descendant_depth USING (id);
                END IF;
                SELECT INTO items_out COUNT(DISTINCT circ.id)
                  FROM action.circulation circ
                    JOIN asset.copy copy ON (copy.id = circ.target_copy)
                    LEFT JOIN action.circulation_limit_group_map aclgm ON (circ.id = aclgm.circ)
                  WHERE circ.usr = match_user
                    AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                    AND circ.checkin_time IS NULL
                    AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
                    AND (copy.circ_modifier IN (SELECT circ_mod FROM config.circ_limit_set_circ_mod_map WHERE limit_set = circ_limit_set.id)
                        OR copy.location IN (SELECT copy_loc FROM config.circ_limit_set_copy_loc_map WHERE limit_set = circ_limit_set.id)
                        OR aclgm.limit_group IN (SELECT limit_group FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id)
                    );
                IF items_out >= circ_limit_set.items_out THEN
                    result.fail_part := 'config.circ_matrix_circ_mod_test';
                    result.success := FALSE;
                    done := TRUE;
                    RETURN NEXT result;
                END IF;
            END IF;
            SELECT INTO result.limit_groups result.limit_groups || ARRAY_AGG(limit_group) FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id AND NOT check_only;
    END LOOP;

    -- If we passed everything, return the successful matchpoint
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('1343', :eg_version);

ALTER TABLE actor.hours_of_operation
    ADD COLUMN dow_0_note TEXT,
    ADD COLUMN dow_1_note TEXT,
    ADD COLUMN dow_2_note TEXT,
    ADD COLUMN dow_3_note TEXT,
    ADD COLUMN dow_4_note TEXT,
    ADD COLUMN dow_5_note TEXT,
    ADD COLUMN dow_6_note TEXT;

SELECT evergreen.upgrade_deps_block_check('1344', :eg_version);

-- This function is used to help clean up facet labels. Due to quirks in
-- MARC parsing, some facet labels may be generated with periods or commas
-- at the end.  This will strip a trailing commas off all the time, and
-- periods when they don't look like they are part of initials or dotted
-- abbreviations.
--      Smith, John                 =>  no change
--      Smith, John,                =>  Smith, John
--      Smith, John.                =>  Smith, John
--      Public, John Q.             => no change
--      Public, John, Ph.D.         => no change
--      Atlanta -- Georgia -- U.S.  => no change
--      Atlanta -- Georgia.         => Atlanta, Georgia
--      The fellowship of the rings / => The fellowship of the rings
--      Some title ;                  => Some title
CREATE OR REPLACE FUNCTION metabib.trim_trailing_punctuation ( TEXT ) RETURNS TEXT AS $$
DECLARE
    result    TEXT;
    last_char TEXT;
BEGIN
    result := $1;
    last_char = substring(result from '.$');

    IF last_char = ',' THEN
        result := substring(result from '^(.*),$');

    ELSIF last_char = '.' THEN
        -- must have a single word-character following at least one non-word character
        IF substring(result from '\W\w\.$') IS NULL THEN
            result := substring(result from '^(.*)\.$');
        END IF;

    ELSIF last_char IN ('/',':',';','=') THEN -- Dangling subtitle/SoR separator
        IF substring(result from ' .$') IS NOT NULL THEN -- must have a space before last_char
            result := substring(result from '^(.*) .$');
        END IF;
    END IF;

    RETURN result;

END;
$$ language 'plpgsql';


INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func = 'metabib.trim_trailing_punctuation'
            AND m.field_class='title' AND (m.browse_field OR m.facet_field OR m.display_field)
            AND NOT EXISTS (SELECT 1 FROM config.metabib_field_index_norm_map WHERE field = m.id AND norm = i.id);


SELECT evergreen.upgrade_deps_block_check('1345', :eg_version);

CREATE TABLE acq.shipment_notification (
    id              SERIAL      PRIMARY KEY,
    receiver        INT         NOT NULL REFERENCES actor.org_unit (id),
    provider        INT         NOT NULL REFERENCES acq.provider (id),
    shipper         INT         NOT NULL REFERENCES acq.provider (id),
    recv_date       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recv_method     TEXT        NOT NULL REFERENCES acq.invoice_method (code) DEFAULT 'EDI',
    process_date    TIMESTAMPTZ,
    processed_by    INT         REFERENCES actor.usr(id) ON DELETE SET NULL,
    container_code  TEXT        NOT NULL, -- vendor-supplied super-barcode
    lading_number   TEXT,       -- informational
    note            TEXT,
    CONSTRAINT      container_code_once_per_provider UNIQUE(provider, container_code)
);

CREATE INDEX acq_asn_container_code_idx ON acq.shipment_notification (container_code);

CREATE TABLE acq.shipment_notification_entry (
    id                      SERIAL  PRIMARY KEY,
    shipment_notification   INT NOT NULL REFERENCES acq.shipment_notification (id)
                            ON DELETE CASCADE,
    lineitem                INT REFERENCES acq.lineitem (id)
                            ON UPDATE CASCADE ON DELETE SET NULL,
    item_count              INT NOT NULL -- How many items the provider shipped
);

/* TODO alter valid_message_type constraint */

ALTER TABLE acq.edi_message DROP CONSTRAINT valid_message_type;
ALTER TABLE acq.edi_message ADD CONSTRAINT valid_message_type
CHECK (
    message_type IN (
        'ORDERS',
        'ORDRSP',
        'INVOIC',
        'OSTENQ',
        'OSTRPT',
        'DESADV'
    )
);


/* UNDO

DELETE FROM acq.edi_message WHERE message_type = 'DESADV';

DELETE FROM acq.shipment_notification_entry;
DELETE FROM acq.shipment_notification;

ALTER TABLE acq.edi_message DROP CONSTRAINT valid_message_type;
ALTER TABLE acq.edi_message ADD CONSTRAINT valid_message_type
CHECK (
    message_type IN (
        'ORDERS',
        'ORDRSP',
        'INVOIC',
        'OSTENQ',
        'OSTRPT'
    )
);

DROP TABLE acq.shipment_notification_entry;
DROP TABLE acq.shipment_notification;

*/


SELECT evergreen.upgrade_deps_block_check('1346', :eg_version); 

-- insert then update for easier iterative development tweaks
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('items_out', 'Patron Items Out', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  circulations = template_data.circulations;
%]
<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following items:</div>
  <hr/>
  <ol>
  [% FOR checkout IN circulations %]
    <li>
      <div>[% checkout.title %]</div>
      <div>
      [% IF checkout.copy %]Barcode: [% checkout.copy.barcode %][% END %]
    Due: [% date.format(helpers.format_date(checkout.dueDate, staff_org_timezone), '%x %r') %]
      </div>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'items_out';

UPDATE config.print_template SET active = TRUE WHERE name = 'patron_address';

-- insert then update for easier iterative development tweaks
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('bills_current', 'Bills, Current', 1, TRUE, 'en-US', 'text/html', '');


UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET xacts = template_data.xacts;
%]
<div>
  <style>td { padding: 1px 3px 1px 3px; }</style>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following bills:</div>
  <hr/>
  <ol>
  [% FOR xact IN xacts %]
    <li>
      <table>
        <tr>
          <td>Bill #:</td>
          <td>[% xact.id %]</td>
        </tr>
        <tr>
          <td>Date:</td>
          <td>[% date.format(helpers.format_date(
            xact.xact_start, staff_org_timezone), '%x %r') %]
          </td>
        </tr>
        <tr>
          <td>Last Billing:</td>
          <td>[% xact.last_billing_type %]</td>
        </tr>
        <tr>
          <td>Total Billed:</td>
          <td>[% money(xact.total_owed) %]</td>
        </tr>
        <tr>
          <td>Last Payment:</td>
          <td>
            [% xact.last_payment_type %]
            [% IF xact.last_payment_ts %]
              at [% date.format(
                    helpers.format_date(
                        xact.last_payment_ts, staff_org_timezone), '%x %r') %]
            [% END %]
          </td>
        </tr>
        <tr>
          <td>Total Paid:</td>
          <td>[% money(xact.total_paid) %]</td>
        </tr>
        <tr>
          <td>Balance:</td>
          <td>[% money(xact.balance_owed) %]</td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'bills_current';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('bills_payment', 'Bills, Payment', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET payments = template_data.payments;
  SET previous_balance = template_data.previous_balance;
  SET new_balance = template_data.new_balance;
  SET payment_type = template_data.payment_type;
  SET payment_total = template_data.payment_total;
  SET payment_applied = template_data.payment_applied;
  SET amount_voided = template_data.amount_voided;
  SET change_given = template_data.change_given;
  SET payment_note = template_data.payment_note;
  SET copy_barcode = template_data.copy_barcode;
  SET title = template_data.title;
%]
<div>
  <style>td { padding: 1px 3px 1px 3px; }</style>
  <div>Welcome to [% staff_org.name %]</div>
  <div>A receipt of your transaction:</div>
  <hr/>

  <table style="width:100%"> 
    <tr> 
      <td>Original Balance:</td> 
      <td align="right">[% money(previous_balance) %]</td> 
    </tr> 
    <tr> 
      <td>Payment Method:</td> 
      <td align="right">
        [% SWITCH payment_type %]
          [% CASE "cash_payment" %]Cash
          [% CASE "check_payment" %]Check
          [% CASE "credit_card_payment" %]Credit Card
          [% CASE "debit_card_payment" %]Debit Card
          [% CASE "credit_payment" %]Patron Credit
          [% CASE "work_payment" %]Work
          [% CASE "forgive_payment" %]Forgive
          [% CASE "goods_payment" %]Goods
        [% END %]
      </td>
    </tr> 
    <tr> 
      <td>Payment Received:</td> 
      <td align="right">[% money(payment_total) %]</td> 
    </tr> 
    <tr> 
      <td>Payment Applied:</td> 
      <td align="right">[% money(payment_applied) %]</td> 
    </tr> 
    <tr> 
      <td>Billings Voided:</td> 
      <td align="right">[% money(amount_voided) %]</td> 
    </tr> 
    <tr> 
      <td>Change Given:</td> 
      <td align="right">[% money(change_given) %]</td> 
    </tr> 
    <tr> 
      <td>New Balance:</td> 
      <td align="right">[% money(new_balance) %]</td> 
    </tr> 
  </table> 
  <p>Note: [% payment_note %]</p>
  <p>
    Specific Bills
    <blockquote>
      [% FOR payment IN payments %]
        <table style="width:100%">
          <tr>
            <td>Bill # [% payment.xact.id %]</td>
            <td>[% payment.xact.summary.last_billing_type %]</td>
            <td>Received: [% money(payment.amount) %]</td>
          </tr>
          [% IF payment.copy_barcode %]
          <tr>
            <td colspan="5">[% payment.copy_barcode %] [% payment.title %]</td>
          </tr>
          [% END %]
        </table>
        <br/>
      [% END %]
    </blockquote>
  </p> 
  <hr/>
  <br/><br/> 
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
</div>
$TEMPLATE$ WHERE name = 'bills_payment';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('patron_data', 'Patron Data', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET patron = template_data.patron;
%]
<table>
  <tr><td>Barcode:</td><td>[% patron.card.barcode %]</td></tr>
  <tr><td>Patron's Username:</td><td>[% patron.usrname %]</td></tr>
  <tr><td>Prefix/Title:</td><td>[% patron.prefix %]</td></tr>
  <tr><td>First Name:</td><td>[% patron.first_given_name %]</td></tr>
  <tr><td>Middle Name:</td><td>[% patron.second_given_name %]</td></tr>
  <tr><td>Last Name:</td><td>[% patron.family_name %]</td></tr>
  <tr><td>Suffix:</td><td>[% patron.suffix %]</td></tr>
  <tr><td>Holds Alias:</td><td>[% patron.alias %]</td></tr>
  <tr><td>Date of Birth:</td><td>[% patron.dob %]</td></tr>
  <tr><td>Juvenile:</td><td>[% patron.juvenile %]</td></tr>
  <tr><td>Primary Identification Type:</td><td>[% patron.ident_type.name %]</td></tr>
  <tr><td>Primary Identification:</td><td>[% patron.ident_value %]</td></tr>
  <tr><td>Secondary Identification Type:</td><td>[% patron.ident_type2.name %]</td></tr>
  <tr><td>Secondary Identification:</td><td>[% patron.ident_value2 %]</td></tr>
  <tr><td>Email Address:</td><td>[% patron.email %]</td></tr>
  <tr><td>Daytime Phone:</td><td>[% patron.day_phone %]</td></tr>
  <tr><td>Evening Phone:</td><td>[% patron.evening_phone %]</td></tr>
  <tr><td>Other Phone:</td><td>[% patron.other_phone %]</td></tr>
  <tr><td>Home Library:</td><td>[% patron.home_ou.name %]</td></tr>
  <tr><td>Main (Profile) Permission Group:</td><td>[% patron.profile.name %]</td></tr>
  <tr><td>Privilege Expiration Date:</td><td>[% patron.expire_date %]</td></tr>
  <tr><td>Internet Access Level:</td><td>[% patron.net_access_level.name %]</td></tr>
  <tr><td>Active:</td><td>[% patron.active %]</td></tr>
  <tr><td>Barred:</td><td>[% patron.barred %]</td></tr>
  <tr><td>Is Group Lead Account:</td><td>[% patron.master_account %]</td></tr>
  <tr><td>Claims-Returned Count:</td><td>[% patron.claims_returned_count %]</td></tr>
  <tr><td>Claims-Never-Checked-Out Count:</td><td>[% patron.claims_never_checked_out_count %]</td></tr>
  <tr><td>Alert Message:</td><td>[% patron.alert_message %]</td></tr>

  [% FOR addr IN patron.addresses %]
    <tr><td colspan="2">----------</td></tr>
    <tr><td>Type:</td><td>[% addr.address_type %]</td></tr>
    <tr><td>Street (1):</td><td>[% addr.street1 %]</td></tr>
    <tr><td>Street (2):</td><td>[% addr.street2 %]</td></tr>
    <tr><td>City:</td><td>[% addr.city %]</td></tr>
    <tr><td>County:</td><td>[% addr.county %]</td></tr>
    <tr><td>State:</td><td>[% addr.state %]</td></tr>
    <tr><td>Postal Code:</td><td>[% addr.post_code %]</td></tr>
    <tr><td>Country:</td><td>[% addr.country %]</td></tr>
    <tr><td>Valid Address?:</td><td>[% addr.valid %]</td></tr>
    <tr><td>Within City Limits?:</td><td>[% addr.within_city_limits %]</td></tr>
  [% END %]

  [% FOR entry IN patron.stat_cat_entries %]
    <tr><td>-----------</td></tr>
    <tr><td>[% entry.stat_cat.name %]</td><td>[% entry.stat_cat_entry %]</td></tr>
  [% END %]

</table>

$TEMPLATE$ WHERE name = 'patron_data';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('hold_shelf_slip', 'Hold Shelf Slip', 1, TRUE, 'en-US', 'text/html', '');


UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET copy = template_data.checkin.copy;
  SET hold = template_data.checkin.hold;
  SET volume = template_data.checkin.volume;
  SET hold = template_data.checkin.hold;
  SET record = template_data.checkin.record;
  SET patron = template_data.checkin.patron;
%] 

<div>
  [% IF hold.behind_desk == 't' %]
    This item needs to be routed to the <strong>Private Holds Shelf</strong>.
  [% ELSE %]
    This item needs to be routed to the <strong>Public Holds Shelf</strong>.
  [% END %]
</div>
<br/>

<div>Barcode: [% copy.barcode %]</div>
<div>Title: [% checkin.title %]</div>
<div>Call Number: [% volume.prefix.label %] [% volume.label %] [% volume.suffix.label %]</div>

<br/>

<div>Hold for patron: [% patron.family_name %], 
  [% patron.first_given_name %] [% patron.second_given_name %]</div>
<div>Barcode: [% patron.card.barcode %]</div>

[% IF hold.phone_notify %]
  <div>Notify by phone: [% hold.phone_notify %]</div>
[% END %]
[% IF hold.sms_notify %]
  <div>Notify by text: [% hold.sms_notify %]</div>
[% END %]
[% IF hold.email_notify %]
  <div>Notify by email: [% patron.email %]</div>
[% END %]

[% FOR note IN hold.notes %]
  <ul>
  [% IF note.slip == 't' %]
    <li><strong>[% note.title %]</strong> - [% note.body %]</li>
  [% END %]
  </ul>
[% END %]
<br/>

<div>Request Date: [% 
  date.format(helpers.format_date(hold.request_time, staff_org_timezone), '%x %r') %]</div>
<div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
<div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>

</div>

$TEMPLATE$ WHERE name = 'hold_shelf_slip';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('transit_slip', 'Transit Slip', 1, TRUE, 'en-US', 'text/html', '');


UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET checkin = template_data.checkin;
  SET copy = checkin.copy;
  SET destOrg = checkin.destOrg;
  SET destAddress = checkin.destAddress;
  SET destCourierCode = checkin.destCourierCode;
%] 
<div>
  <div>This item needs to be routed to <b>[% destOrg.shortname %]</b></div>
  <div>[% destOrg.name %]</div>
  [% IF destCourierCode %]Courier Code: [% destCourierCode %][% END %]

  [% IF destAddress %]
    <div>[% destAddress.street1 %]</div>
    <div>[% destAddress.street2 %]</div>
    <div>[% destAddress.city %],
    [% destAddress.state %]
    [% destAddress.post_code %]</div>
  [% ELSE %]
    <div>We do not have a holds address for this library.</div>
  [% END %]
  
  <br/>
  <div>Barcode: [% copy.barcode %]</div>
  <div>Title: [% checkin.title %]</div>
  <div>Author: [% checkin.author %]</div>
  
  <br/>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'transit_slip';

 
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('hold_transit_slip', 'Hold Transit Slip', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET checkin = template_data.checkin;
  SET copy = checkin.copy;
  SET hold = checkin.hold;
  SET patron = checkin.patron;
  SET destOrg = checkin.destOrg;
  SET destAddress = checkin.destAddress;
  SET destCourierCode = checkin.destCourierCode;
%] 
<div>
  <div>This item needs to be routed to <b>[% destOrg.shortname %]</b></div>
  <div>[% destOrg.name %]</div>
  [% IF destCourierCode %]Courier Code: [% destCourierCode %][% END %]

  [% IF destAddress %]
    <div>[% destAddress.street1 %]</div>
    <div>[% destAddress.street2 %]</div>
    <div>[% destAddress.city %],
    [% destAddress.state %]
    [% destAddress.post_code %]</div>
  [% ELSE %]
    <div>We do not have a holds address for this library.</div>
  [% END %]
  
  <br/>
  <div>Barcode: [% copy.barcode %]</div>
  <div>Title: [% checkin.title %]</div>
  <div>Author: [% checkin.author %]</div>

  <br/>
  <div>Hold for patron [% patron.card.barcode %]</div>
  
  <br/>
  <div>Request Date: [% 
    date.format(helpers.format_date(hold.request_time, staff_org_timezone), '%x %r') %]
  </div>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'transit_slip';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('checkin', 'Checkin', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET checkins = template_data.checkins;
%] 

<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You checked in the following items:</div>
  <hr/>
  <ol>
	[% FOR checkin IN checkins %]
    <li>
      <div>[% checkin.title %]</div>
      <span>Barcode: </span>
      <span>[% checkin.copy.barcode %]</span>
      <span>Call Number: </span>
      <span>
      [% IF checkin.volume %]
	    [% volume.prefix.label %] [% volume.label %] [% volume.suffix.label %]
      [% ELSE %]
        Not Cataloged
      [% END %]
      </span>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'checkin';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('holds_for_patron', 'Holds For Patron', 1, TRUE, 'en-US', 'text/html', '');


UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET holds = template_data;
%] 

<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following items on hold:</div>
  <hr/>
  <ol>
	[% FOR hold IN holds %]
    <li>
      <div>[% hold.title %]</div>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'holds_for_patron';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('bills_historical', 'Bills, Historical', 1, TRUE, 'en-US', 'text/html', '');


UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET xacts = template_data.xacts;
%]
<div>
  <style>td { padding: 1px 3px 1px 3px; }</style>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following bills:</div>
  <hr/>
  <ol>
  [% FOR xact IN xacts %]
    <li>
      <table>
        <tr>
          <td>Bill #:</td>
          <td>[% xact.id %]</td>
        </tr>
        <tr>
          <td>Date:</td>
          <td>[% date.format(helpers.format_date(
            xact.xact_start, staff_org_timezone), '%x %r') %]
          </td>
        </tr>
        <tr>
          <td>Last Billing:</td>
          <td>[% xact.last_billing_type %]</td>
        </tr>
        <tr>
          <td>Total Billed:</td>
          <td>[% money(xact.total_owed) %]</td>
        </tr>
        <tr>
          <td>Last Payment:</td>
          <td>
            [% xact.last_payment_type %]
            [% IF xact.last_payment_ts %]
              at [% date.format(
                    helpers.format_date(
                        xact.last_payment_ts, staff_org_timezone), '%x %r') %]
            [% END %]
          </td>
        </tr>
        <tr>
          <td>Total Paid:</td>
          <td>[% money(xact.total_paid) %]</td>
        </tr>
        <tr>
          <td>Balance:</td>
          <td>[% money(xact.balance_owed) %]</td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'bills_historical';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('checkout', 'Checkout', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET checkouts = template_data.checkouts;
%] 

<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You checked out the following items:</div>
  <hr/>
  <ol>
	[% FOR checkout IN checkouts %]
    <li>
      <div>[% checkout.title %]</div>
      <span>Barcode: </span>
      <span>[% checkout.copy.barcode %]</span>
      <span>Call Number: </span>
      <span>
      [% IF checkout.volume %]
	    [% volume.prefix.label %] [% volume.label %] [% volume.suffix.label %]
      [% ELSE %]
        Not Cataloged
      [% END %]
      </span>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'checkout';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('renew', 'renew', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET renewals = template_data.renewals;
%] 

<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You renewed the following items:</div>
  <hr/>
  <ol>
	[% FOR renewal IN renewals %]
    <li>
      <div>[% renewal.title %]</div>
      <span>Barcode: </span>
      <span>[% renewal.copy.barcode %]</span>
      <span>Call Number: </span>
      <span>
      [% IF renewal.volume %]
	    [% volume.prefix.label %] [% volume.label %] [% volume.suffix.label %]
      [% ELSE %]
        Not Cataloged
      [% END %]
      </span>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>Slip Date: [% date.format(date.now, '%x %r') %]</div>
  <div>Printed by [% staff.first_given_name %] at [% staff_org.shortname %]</div>
</div>

$TEMPLATE$ WHERE name = 'renew';

INSERT INTO config.org_unit_setting_type (name, grp, datatype, label, description)
VALUES (
    'ui.staff.angular_circ.enabled', 'gui', 'bool',
    oils_i18n_gettext(
        'ui.staff.angular_circ.enabled',
        'Enable Angular Circulation Menu',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.staff.angular_circ.enabled',
        'Enable Angular Circulation Menu',
        'coust', 'description'
    )
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 640, 'ACCESS_ANGULAR_CIRC', oils_i18n_gettext(640,
    'Allow a user to access the experimental Angular circulation interfaces', 'ppl', 'description'))
;





SELECT evergreen.upgrade_deps_block_check('1347', :eg_version);   

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

    -- action_trigger.event (even doing this, event_output may--and probably does--contain PII and should have a retention/removal policy)
    UPDATE action_trigger.event SET context_user = dest_usr WHERE context_user = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;
	UPDATE action.curbside SET notes = NULL WHERE patron = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;
	DELETE FROM actor.usr_privacy_waiver WHERE usr = src_usr;
	DELETE FROM actor.usr_message WHERE usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_message SET title = 'purged', message = 'purged', read_date = NOW() WHERE usr = src_usr;
	DELETE FROM actor.usr_message WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;
	UPDATE actor.usr_message SET editor = dest_usr WHERE editor = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1348', :eg_version);

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN renew_extends_due_date BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN renew_extend_min_interval INTERVAL;


SELECT evergreen.upgrade_deps_block_check('1349', :eg_version);

UPDATE config.org_unit_setting_type
    SET label = 'Rollover encumbrances only',
        description = 'Rollover encumbrances only when doing fiscal year end.  This makes money left in the old fund disappear, modeling its return to some outside entity.'
    WHERE name = 'acq.fund.allow_rollover_without_money'
    AND label = 'Allow funds to be rolled over without bringing the money along'
    AND description = 'Allow funds to be rolled over without bringing the money along.  This makes money left in the old fund disappear, modeling its return to some outside entity.';


SELECT evergreen.upgrade_deps_block_check('1350', :eg_version);

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- we don't merge bib -1
    IF target_record = -1 OR source_record = -1 THEN
       RETURN 0;
    END IF;

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
			' tag="856"' ||
			' ind1="' || FIRST(ind1) || '"'  ||
			' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

	-- Find and move metarecords to the target record
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- And delete mappings where the item's home bib was merged with the peer bib
	DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
		SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
		FROM asset.copy WHERE id = target_copy
	);

    -- Apply merge tracking
    UPDATE biblio.record_entry 
        SET merge_date = NOW() WHERE id = target_record;

    UPDATE biblio.record_entry
        SET merge_date = NOW(), merged_to = target_record
        WHERE id = source_record;

    -- replace book bag entries of source_record with target_record
    UPDATE container.biblio_record_entry_bucket_item
        SET target_biblio_record_entry = target_record
        WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'bookbag')
        AND target_biblio_record_entry = source_record;

    -- move over record notes 
    UPDATE biblio.record_note 
        SET record = target_record, value = CONCAT(value,'; note merged from ',source_record::TEXT) 
        WHERE record = source_record
        AND NOT deleted;

    -- add note to record merge 
    INSERT INTO biblio.record_note (record, value) 
        VALUES (target_record,CONCAT('record ',source_record::TEXT,' merged on ',NOW()::TEXT));

    -- Finally, "delete" the source record
    UPDATE biblio.record_entry SET active = FALSE WHERE id = source_record;
    DELETE FROM biblio.record_entry WHERE id = source_record;

	-- That's all, folks!
	RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1351', :eg_version);

INSERT INTO permission.perm_list ( id, code, description )
    VALUES (
        641,
        'ADMIN_FUND_ROLLOVER',
        oils_i18n_gettext(
            641,
            'Allow a user to perform fund propagation and rollover',
            'ppl',
            'description'
        )
    );

-- ensure that permission groups that are able to
-- rollover funds can continue to do so
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('ADMIN_FUND_ROLLOVER'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'ADMIN_FUND'
        );


SELECT evergreen.upgrade_deps_block_check('1352', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.cash_reports.desk_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.cash_reports.desk_payments',
        'Grid Config: admin.local.cash_reports.desk_payments',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.cash_reports.user_payments', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.cash_reports.user_payments',
        'Grid Config: admin.local.cash_reports.user_payments',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1353', :eg_version);

UPDATE config.org_unit_setting_type SET description = oils_i18n_gettext('cat.default_classification_scheme',
        'Defines the default classification scheme for new call numbers.',
        'coust', 'description')
    WHERE name = 'cat.default_classification_scheme'
    AND description =
        'Defines the default classification scheme for new call numbers: 1 = Generic; 2 = Dewey; 3 = LC';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();

\qecho A partial reingest is necessary to get the full benefit of the change in
\qecho upgrade script 1344 (bug 1864507) It will take a while.
\qecho You can cancel now without losing the effect of
\qecho the rest of the upgrade script, and arrange the reingest later.
\qecho

SELECT metabib.reingest_metabib_field_entries(
          id, TRUE, FALSE, FALSE, TRUE,
          (SELECT ARRAY_AGG(id) FROM config.metabib_field WHERE field_class='title' AND (browse_field OR facet_field OR display_field))
) FROM biblio.record_entry;
