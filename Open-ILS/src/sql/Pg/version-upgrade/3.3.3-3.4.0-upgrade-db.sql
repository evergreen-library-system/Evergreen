--Upgrade Script for 3.3.3 to 3.4.0
\set eg_version '''3.4.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.4.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1168', :eg_version); -- csharp/khuckins/gmcharlt

UPDATE permission.perm_list 
    SET description = oils_i18n_gettext(
        '608',
        'Allows a user to apply values to workstation settings',
        'ppl', 'description')
    WHERE code = 'APPLY_WORKSTATION_SETTING' and description = 'APPLY_WORKSTATION_SETTING';



SELECT evergreen.upgrade_deps_block_check('1169', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.search_templates', 'gui', 'object',
    oils_i18n_gettext(
        'eg.catalog.search_templates',
        'Staff Catalog Search Templates',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1170', :eg_version);

CREATE TABLE config.hold_type (
    id          SERIAL,
    hold_type   TEXT UNIQUE,
    description TEXT
);

INSERT INTO config.hold_type (hold_type,description) VALUES
    ('C','Copy Hold'),
    ('V','Volume Hold'),
    ('T','Title Hold'),
    ('M','Metarecord Hold'),
    ('R','Recall Hold'),
    ('F','Force Hold'),
    ('I','Issuance Hold'),
    ('P','Part Hold')
;

ALTER TABLE action.hold_request ADD CONSTRAINT hold_request_hold_type_fkey FOREIGN KEY (hold_type) REFERENCES config.hold_type(hold_type) DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('1172', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label) 
VALUES (
    'eg.grid.admin.local.config.hold_matrix_matchpoint', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.hold_matrix_matchpoint',
        'Grid Config: admin.local.config.hold_matrix_matchpoint',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.actor.address_alert', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.address_alert',
        'Grid Config: admin.local.actor.address_alert',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.config.barcode_completion', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.barcode_completion',
        'Grid Config: admin.local.config.barcode_completion',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.actor.copy_alert_suppress', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.copy_alert_suppress',
        'Grid Config: admin.local.actor.copy_alert_suppress',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.copy_location', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.copy_location',
        'Grid Config: admin.local.asset.copy_location',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.copy_tag', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.copy_tag',
        'Grid Config: admin.local.asset.copy_tag',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.permission.grp_penalty_threshold', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.permission.grp_penalty_threshold',
        'Grid Config: admin.local.permission.grp_penalty_threshold',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.config.non_cataloged_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.non_cataloged_type',
        'Grid Config: admin.local.config.non_cataloged_type',
        'cwst', 'label'
    )
);

-- eg.grid.admin.local.rating.badge already exists



SELECT evergreen.upgrade_deps_block_check('1173', :eg_version);

CREATE TABLE config.print_template (
    id           SERIAL PRIMARY KEY,
    name         TEXT NOT NULL, -- programatic name
    label        TEXT NOT NULL, -- i18n
    owner        INT NOT NULL REFERENCES actor.org_unit (id),
    active       BOOLEAN NOT NULL DEFAULT FALSE,
    locale       TEXT REFERENCES config.i18n_locale(code) 
                 ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    content_type TEXT NOT NULL DEFAULT 'text/html',
    template     TEXT NOT NULL,
	CONSTRAINT   name_once_per_lib UNIQUE (owner, name),
	CONSTRAINT   label_once_per_lib UNIQUE (owner, label)
);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    1, 'patron_address', 'en-US', FALSE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(1, 'Address Label', 'cpt', 'label'),
$TEMPLATE$
[%-
    SET patron = template_data.patron;
    SET addr = template_data.address;
-%]
<div>
  <div>
    [% patron.first_given_name %] 
    [% patron.second_given_name %] 
    [% patron.family_name %]
  </div>
  <div>[% addr.street1 %]</div>
  [% IF addr.street2 %]<div>[% addr.street2 %]</div>[% END %]
  <div>
    [% addr.city %], [% addr.state %] [% addr.post_code %]
  </div>
</div>
$TEMPLATE$
);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    2, 'holds_for_bib', 'en-US', FALSE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(2, 'Holds for Bib Record', 'cpt', 'label'),
$TEMPLATE$
[%-
    USE date;
    SET holds = template_data;
    # template_data is an arry of wide_hold hashes.
-%]
<div>
  <div>Holds for record: [% holds.0.title %]</div>
  <hr/>
  <style>#holds-for-bib-table td { padding: 5px; }</style>
  <table id="holds-for-bib-table">
    <thead>
      <tr>
        <th>Request Date</th>
        <th>Patron Barcode</th>
        <th>Patron Last</th>
        <th>Patron Alias</th>
        <th>Current Item</th>
      </tr>
    </thead>
    <tbody>
      [% FOR hold IN holds %]
      <tr>
        <td>[% 
          date.format(helpers.format_date(
            hold.request_time, staff_org_timezone), '%x %r', locale) 
        %]</td>
        <td>[% hold.ucard_barcode %]</td>
        <td>[% hold.usr_family_name %]</td>
        <td>[% hold.usr_alias %]</td>
        <td>[% hold.cp_barcode %]</td>
      </tr>
      [% END %]
    </tbody>
  </table>
  <hr/>
  <div>
    [% staff_org.shortname %] 
    [% date.format(helpers.current_date(client_timezone), '%x %r', locale) %]
  </div>
  <div>Printed by [% staff.first_given_name %]</div>
</div>
<br/>

$TEMPLATE$
);

-- Allow for 1k stock templates
SELECT SETVAL('config.print_template_id_seq'::TEXT, 1000);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (611, 'ADMIN_PRINT_TEMPLATE', 
    oils_i18n_gettext(611, 'Modify print templates', 'ppl', 'description'));



INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1174', :eg_version);

ALTER TABLE asset.copy_tag
          ADD COLUMN url TEXT;


SELECT evergreen.upgrade_deps_block_check('1175', :eg_version);

CREATE TABLE config.carousel_type (
    id                          SERIAL PRIMARY KEY,
    name                        TEXT NOT NULL,
    automatic                   BOOLEAN NOT NULL DEFAULT TRUE,
    filter_by_age               BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_owning_lib   BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_location     BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO config.carousel_type
    (id, name,                               automatic, filter_by_age, filter_by_copy_owning_lib, filter_by_copy_location)
VALUES
    (1, 'Manual',                            FALSE,     FALSE,         FALSE,                     FALSE),
    (2, 'Newly Catalogued Items',            TRUE,      TRUE,          TRUE,                      TRUE),
    (3, 'Recently Returned Items',           TRUE,      TRUE,          TRUE,                      TRUE),
    (4, 'Top Circulated Items',              TRUE,      TRUE,          TRUE,                      FALSE),
    (5, 'Newest Items By Shelving Location', TRUE,      TRUE,          TRUE,                      FALSE)
;

SELECT SETVAL('config.carousel_type_id_seq'::TEXT, 100);

CREATE TABLE container.carousel (
    id                      SERIAL PRIMARY KEY,
    type                    INTEGER NOT NULL REFERENCES config.carousel_type (id),
    owner                   INTEGER NOT NULL REFERENCES actor.org_unit (id),
    name                    TEXT NOT NULL,
    bucket                  INTEGER REFERENCES container.biblio_record_entry_bucket (id),
    creator                 INTEGER NOT NULL REFERENCES actor.usr (id),
    editor                  INTEGER NOT NULL REFERENCES actor.usr (id),
    create_time             TIMESTAMPTZ NOT NULL DEFAULT now(),
    edit_time               TIMESTAMPTZ NOT NULL DEFAULT now(),
    age_filter              INTERVAL,
    owning_lib_filter       INT[],
    copy_location_filter    INT[],
    last_refresh_time       TIMESTAMPTZ,
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    max_items               INTEGER NOT NULL
);

CREATE TABLE container.carousel_org_unit (
    id              SERIAL PRIMARY KEY,
    carousel        INTEGER NOT NULL REFERENCES container.carousel (id) ON DELETE CASCADE,
    override_name   TEXT,
    org_unit        INTEGER NOT NULL REFERENCES actor.org_unit (id),
    seq             INTEGER NOT NULL
);

INSERT INTO container.biblio_record_entry_bucket_type (code, label) VALUES ('carousel', 'Carousel');

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 612, 'ADMIN_CAROUSEL_TYPE', oils_i18n_gettext(611,
    'Allow a user to manage carousel types', 'ppl', 'description')),
 ( 613, 'ADMIN_CAROUSEL', oils_i18n_gettext(612,
    'Allow a user to manage carousels', 'ppl', 'description')),
 ( 614, 'REFRESH_CAROUSEL', oils_i18n_gettext(613,
    'Allow a user to refresh carousels', 'ppl', 'description'))
;


SELECT evergreen.upgrade_deps_block_check('1176', :eg_version);

ALTER TABLE booking.reservation
    ADD COLUMN note TEXT;


SELECT evergreen.upgrade_deps_block_check('1177', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.manage', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage',
        'Grid Config: Booking Manage Reservations',
        'cwst', 'label')
), (
    'eg.grid.booking.pickup.ready', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pickup.ready',
        'Grid Config: Booking Ready to pick up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.pickup.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pickup.picked_up',
        'Grid Config: Booking Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.patron.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.patron.picked_up',
        'Grid Config: Booking Return Patron tab Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.patron.returned', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.patron.returned',
        'Grid Config: Booking Return Patron tab Returned Today grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.resource.picked_up', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.resourcce.picked_up',
        'Grid Config: Booking Return Resource tab Already Picked Up grid',
        'cwst', 'label')
), (
    'eg.grid.booking.return.resource.returned', 'gui', 'object',
    oils_i18n_gettext(
        'booking.return.resource.returned',
        'Grid Config: Booking Return Resource tab Returned Today grid',
        'cwst', 'label')
), (
    'eg.booking.manage.selected_org_family', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage.selected_org_family',
        'Sticky setting for pickup ou family in Manage Reservations screen',
        'cwst', 'label')
), (
    'eg.booking.return.tab', 'gui', 'string',
    oils_i18n_gettext(
        'booking.return.tab',
        'Sticky setting for tab in Booking Return',
        'cwst', 'label')
), (
    'eg.booking.create.granularity', 'gui', 'integer',
    oils_i18n_gettext(
        'booking.create.granularity',
        'Sticky setting for granularity combobox in Booking Create',
        'cwst', 'label')
), (
    'eg.booking.create.multiday', 'gui', 'bool',
    oils_i18n_gettext(
        'booking.create.multiday',
        'Default to creating multiday booking reservations',
        'cwst', 'label')
), (
    'eg.booking.pickup.ready.only_show_captured', 'gui', 'bool',
    oils_i18n_gettext(
        'booking.pickup.ready.only_show_captured',
        'Include only resources that have been captured in the Ready grid in the Pickup screen',
        'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1178', :eg_version);

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, group_field, max_delay, template) 
    VALUES (false, 1, 'Fine Limit Exceeded', 'penalty.PATRON_EXCEEDS_FINES', 'NOOP_True', 'SendEmail', '00:05:00', 'usr', '1 day', 
$$
[%- USE date -%]
[%- user = target.usr -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Fine Limit Exceeded
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],


Our records indicate your account has exceeded the fine limit allowed for the use of your library account.

Please visit the library to pay your fines and restore full access to your account.
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (currval('action_trigger.event_definition_id_seq'), 'usr'),
    (currval('action_trigger.event_definition_id_seq'), 'usr.card');


SELECT evergreen.upgrade_deps_block_check('1179', :eg_version);

INSERT INTO config.org_unit_setting_type 
    (grp, name, datatype, label, description)
VALUES (
    'opac',
    'opac.show_owning_lib_column', 'bool',
    oils_i18n_gettext(
        'opac.show_owning_lib_column',
        'Show Owning Lib in Items Out',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.show_owning_lib_column',
'If enabled, the Owning Lib will be shown in the Items Out display.' ||
' This may assist in requesting additional renewals',
        'coust',
        'description'
    )
);


SELECT evergreen.upgrade_deps_block_check('1180', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 615, 'ADMIN_REMOTEAUTH', oils_i18n_gettext( 615,
    'Administer remote patron authentication', 'ppl', 'description' ));

CREATE TABLE config.remoteauth_profile (
    name TEXT PRIMARY KEY,
    description TEXT,
    context_org INT NOT NULL REFERENCES actor.org_unit(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    perm INT NOT NULL REFERENCES permission.perm_list(id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    restrict_to_org BOOLEAN NOT NULL DEFAULT TRUE,
    allow_inactive BOOL NOT NULL DEFAULT FALSE,
    allow_expired BOOL NOT NULL DEFAULT FALSE,
    block_list TEXT,
    usr_activity_type INT REFERENCES config.usr_activity_type(id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION actor.permit_remoteauth (profile_name TEXT, userid BIGINT) RETURNS TEXT AS $func$
DECLARE
    usr               actor.usr%ROWTYPE;
    profile           config.remoteauth_profile%ROWTYPE;
    perm              TEXT;
    context_org_list  INT[];
    home_prox         INT;
    block             TEXT;
    penalty_count     INT;
BEGIN

    SELECT INTO usr * FROM actor.usr WHERE id = userid AND NOT deleted;
    IF usr IS NULL THEN
        RETURN 'not_found';
    END IF;

    IF usr.barred IS TRUE THEN
        RETURN 'blocked';
    END IF;

    SELECT INTO profile * FROM config.remoteauth_profile WHERE name = profile_name;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( profile.context_org );

    -- user's home library must be within the context org
    IF profile.restrict_to_org IS TRUE AND usr.home_ou NOT IN (SELECT * FROM UNNEST(context_org_list)) THEN
        RETURN 'not_found';
    END IF;

    SELECT INTO perm code FROM permission.perm_list WHERE id = profile.perm;
    IF permission.usr_has_perm(usr.id, perm, profile.context_org) IS FALSE THEN
        RETURN 'not_found';
    END IF;
    
    IF usr.expire_date < NOW() AND profile.allow_expired IS FALSE THEN
        RETURN 'expired';
    END IF;

    IF usr.active IS FALSE AND profile.allow_inactive IS FALSE THEN
        RETURN 'blocked';
    END IF;

    -- Proximity of user's home_ou to context_org to see if penalties should be ignored.
    SELECT INTO home_prox prox FROM actor.org_unit_proximity WHERE from_org = usr.home_ou AND to_org = profile.context_org;

    -- Loop through the block list to see if the user has any matching penalties.
    IF profile.block_list IS NOT NULL THEN
        FOR block IN SELECT UNNEST(STRING_TO_ARRAY(profile.block_list, '|')) LOOP
            SELECT INTO penalty_count COUNT(DISTINCT csp.*)
                FROM  actor.usr_standing_penalty usp
                        JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
                WHERE usp.usr = usr.id
                        AND usp.org_unit IN ( SELECT * FROM UNNEST(context_org_list) )
                        AND ( usp.stop_date IS NULL or usp.stop_date > NOW() )
                        AND ( csp.ignore_proximity IS NULL OR csp.ignore_proximity < home_prox )
                        AND csp.block_list ~ block;
            IF penalty_count > 0 THEN
                -- User has penalties that match this block, so auth is not permitted.
                -- Don't bother testing the rest of the block list.
                RETURN 'blocked';
            END IF;
        END LOOP;
    END IF;

    -- User has passed all tests.
    RETURN 'success';

END;
$func$ LANGUAGE plpgsql;




SELECT evergreen.upgrade_deps_block_check('1181', :eg_version);

\qecho Migrating aged billing and payment data.  This might take a while.

CREATE TABLE money.aged_payment (LIKE money.payment INCLUDING INDEXES);
ALTER TABLE money.aged_payment ADD COLUMN payment_type TEXT NOT NULL;

CREATE TABLE money.aged_billing (LIKE money.billing INCLUDING INDEXES);


/* LP 1858448 : Disable initial aged money migration

INSERT INTO money.aged_payment 
    SELECT  mp.* FROM money.payment_view mp
    JOIN action.aged_circulation circ ON (circ.id = mp.xact);

INSERT INTO money.aged_billing
    SELECT mb.* FROM money.billing mb
    JOIN action.aged_circulation circ ON (circ.id = mb.xact);

*/

CREATE OR REPLACE VIEW money.all_payments AS
    SELECT * FROM money.payment_view 
    UNION ALL
    SELECT * FROM money.aged_payment;

CREATE OR REPLACE VIEW money.all_billings AS
    SELECT * FROM money.billing
    UNION ALL
    SELECT * FROM money.aged_billing;

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

/* LP 1858448 : Disable initial aged money migration
    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = OLD.id;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view WHERE xact = OLD.id;

    DELETE FROM money.payment WHERE xact = OLD.id;
    DELETE FROM money.billing WHERE xact = OLD.id;
*/

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';


/* LP 1858448 : Disable initial aged money migration

-- NOTE you could COMMIT here then start a new TRANSACTION if desired.

\qecho Deleting aged payments and billings from active payment/billing
\qecho tables.  This may take a while...

ALTER TABLE money.payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.cash_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.check_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_card_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.forgive_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_payment DISABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.goods_payment DISABLE TRIGGER mat_summary_del_tgr;

DELETE FROM money.payment WHERE id IN (SELECT id FROM money.aged_payment);

ALTER TABLE money.payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.cash_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.check_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_card_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.forgive_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.credit_payment ENABLE TRIGGER mat_summary_del_tgr;
ALTER TABLE money.goods_payment ENABLE TRIGGER mat_summary_del_tgr;

-- TODO: This approach assumes most of the money.billing rows have been
-- copied to money.aged_billing.  If that is not the case, which would
-- happen if circ anonymization is not enabled, it will be faster to
-- perform a simple delete instead of a truncate/rebuild.

-- Copy all money.billing rows that are not represented in money.aged_billing
CREATE TEMPORARY TABLE tmp_money_billing ON COMMIT DROP AS
    SELECT mb.* FROM money.billing mb
    LEFT JOIN money.aged_billing mab USING (id)
    WHERE mab.id IS NULL;

ALTER TABLE money.billing DISABLE TRIGGER ALL;

-- temporarily remove the foreign key constraint to money.billing on
-- account adjusment.  Needed for money.billing truncate.
ALTER TABLE money.account_adjustment 
    DROP CONSTRAINT account_adjustment_billing_fkey;

TRUNCATE money.billing;

INSERT INTO money.billing SELECT * FROM tmp_money_billing;

ALTER TABLE money.billing ENABLE TRIGGER ALL;
ALTER TABLE money.account_adjustment 
    ADD CONSTRAINT account_adjustment_billing_fkey 
    FOREIGN KEY (billing) REFERENCES money.billing (id);


-- Good to run after truncating -- OK to run after COMMIT.
ANALYZE money.billing;

*/


SELECT evergreen.upgrade_deps_block_check('1182', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 616, 'IMPORT_USE_ORG_UNIT_COPIES', oils_i18n_gettext( 616,
    'Allows users to import records based on the number of org unit copies attached to a record', 'ppl', 'description' )),
 ( 617, 'IMPORT_ON_ORDER_CAT_COPY', oils_i18n_gettext( 617,
    'Allows users to import copies based on the on-order items attached to a record', 'ppl', 'description' ));

-- function update in 1182 further updated in 1186

SELECT evergreen.upgrade_deps_block_check('1183', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'ui.patron.edit.au.ident_value.require', 'gui',
    oils_i18n_gettext('ui.patron.edit.au.ident_value.require',
        'require ident_value field on patron registration',
        'coust', 'label'),
    oils_i18n_gettext('ui.patron.edit.au.ident_value.require',
        'The ident_value field will be required on the patron registration screen.',
        'coust', 'description'),
    'bool', null);



SELECT evergreen.upgrade_deps_block_check('1184', :eg_version);

INSERT INTO permission.perm_list(id, code, description)
    VALUES (618, 'CREATE_PRECAT', 'Allows user to create a pre-catalogued copy');

-- Add this new permission to any group with Staff login perm.
-- Manually remove if needed
INSERT INTO permission.grp_perm_map(perm, grp, depth) SELECT 618, map.grp, 0 FROM permission.grp_perm_map AS map WHERE map.perm = 2;

SELECT evergreen.upgrade_deps_block_check('1185', :eg_version); -- csharp / gmcharlt / jboyer

ALTER FUNCTION permission.grp_descendants( INT ) STABLE;

SELECT evergreen.upgrade_deps_block_check('1186', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_org_unit_copies ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    rec             vandelay.bib_match%ROWTYPE;
    v_owning_lib    INT;
    scope_org       INT;
    scope_orgs      INT[];
    copy_count      INT := 0;
    max_copy_count  INT := 0;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    -- Gather all the owning libs for our import items.
    -- These are our initial scope_orgs.
    SELECT ARRAY_AGG(DISTINCT owning_lib) INTO scope_orgs
        FROM vandelay.import_item
        WHERE record = import_id;

    WHILE CARDINALITY(scope_orgs) > 0 LOOP
        FOR scope_org IN SELECT * FROM UNNEST(scope_orgs) LOOP
            -- For each match, get a count of all copies at descendants of our scope org.
            FOR rec IN SELECT * FROM vandelay.bib_match AS vbm
                WHERE queued_record = import_id
                ORDER BY vbm.eg_record DESC
            LOOP
                SELECT COUNT(acp.id) INTO copy_count
                    FROM asset.copy AS acp
                    INNER JOIN asset.call_number AS acn
                        ON acp.call_number = acn.id
                    WHERE acn.owning_lib IN (SELECT id FROM
                        actor.org_unit_descendants(scope_org))
                    AND acn.record = rec.eg_record
                    AND acp.deleted = FALSE;
                IF copy_count > max_copy_count THEN
                    max_copy_count := copy_count;
                    eg_id := rec.eg_record;
                END IF;
            END LOOP;
        END LOOP;

        -- If no matching bibs had holdings, gather our next set of orgs to check, and iterate.
        IF max_copy_count = 0 THEN 
            SELECT ARRAY_AGG(DISTINCT parent_ou) INTO scope_orgs
                FROM actor.org_unit
                WHERE id IN (SELECT * FROM UNNEST(scope_orgs))
                AND parent_ou IS NOT NULL;
        END IF;
    END LOOP;

    IF eg_id IS NULL THEN
        -- Could not determine best match via copy count
        -- fall back to default best match
        IF (SELECT * FROM vandelay.auto_overlay_bib_record_with_best( import_id, merge_profile_id, lwm_ratio_value_p )) THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

SELECT evergreen.upgrade_deps_block_check('1187', :eg_version);
SELECT evergreen.upgrade_deps_block_check('1192', :eg_version);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

/* LP 1858448 : Disable initial aged money migration
    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = OLD.id;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view WHERE xact = OLD.id;

    DELETE FROM money.payment WHERE xact = OLD.id;
    DELETE FROM money.billing WHERE xact = OLD.id;
*/

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

SELECT evergreen.upgrade_deps_block_check('1188', :eg_version);

UPDATE action.circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;
UPDATE action.aged_circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;


SELECT evergreen.upgrade_deps_block_check('1189', :eg_version);

CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

CREATE OR REPLACE VIEW reporter.overdue_circs AS
SELECT  *
  FROM  "action".circulation
  WHERE checkin_time is null
        AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED') OR stop_fines IS NULL)
        AND due_date < now();

CREATE OR REPLACE VIEW reporter.circ_type AS
SELECT	id,
	CASE WHEN opac_renewal OR phone_renewal OR desk_renewal OR auto_renewal
		THEN 'RENEWAL'
		ELSE 'CHECKOUT'
	END AS "type"
  FROM	action.circulation;

SELECT evergreen.upgrade_deps_block_check('1190', :eg_version);

UPDATE action.circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;

UPDATE action.aged_circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;


SELECT evergreen.upgrade_deps_block_check('1191', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
  619,
  'EDIT_SELF_IN_CLIENT',
  oils_i18n_gettext(619,
    'Allow a user to edit their own account in the staff client', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'EDIT_SELF_IN_CLIENT');

COMMIT;

-- The following two changes from 1188 cannot occur in a transaction with the
-- above updates because we will get an error about not being able to
-- alter a table with pending transactions.  They also need to occur
-- after the above updates or the SET NOT NULL change will fail.

ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET NOT NULL;

ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET NOT NULL;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
