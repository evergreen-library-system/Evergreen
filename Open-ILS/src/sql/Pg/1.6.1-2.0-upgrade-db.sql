-- Before starting the transaction: drop some constraints that
-- may or may not exist.

CREATE OR REPLACE FUNCTION oils_text_as_bytea (TEXT) RETURNS BYTEA AS $_$
    SELECT CAST(REGEXP_REPLACE(UPPER($1), $$\\$$, $$\\\\$$, 'g') AS BYTEA);
$_$ LANGUAGE SQL IMMUTABLE;

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (oils_text_as_bytea(label),id,owning_lib);

\qecho Before starting the transaction: drop some constraints.
\qecho If a DROP fails because the constraint doesn't exist, ignore the failure.

-- ARG! VIM! '

ALTER TABLE permission.grp_perm_map        DROP CONSTRAINT grp_perm_map_perm_fkey;
ALTER TABLE permission.usr_perm_map        DROP CONSTRAINT usr_perm_map_perm_fkey;
ALTER TABLE permission.usr_object_perm_map DROP CONSTRAINT usr_object_perm_map_perm_fkey;
ALTER TABLE booking.resource_type          DROP CONSTRAINT brt_name_or_record_once_per_owner;
ALTER TABLE booking.resource_type          DROP CONSTRAINT brt_name_once_per_owner;

\qecho Before starting the transaction: create seed data for the asset.uri table
\qecho If the INSERT fails because the -1 value already exists, ignore the failure.
INSERT INTO asset.uri (id, href, active) VALUES (-1, 'http://example.com/fake', FALSE);

\qecho Beginning the transaction now

BEGIN;

UPDATE biblio.record_entry SET marc = '<record xmlns="http://www.loc.gov/MARC21/slim"/>' WHERE id = -1;

-- Highest-numbered individual upgrade script incorporated herein:

INSERT INTO config.upgrade_log (version) VALUES ('0475');

-- Push the auri sequence in case it's out of date
-- Add 2 as the sequence value must be 1 or higher, and seed is -1
SELECT SETVAL('asset.uri_id_seq'::TEXT, (SELECT MAX(id) + 2 FROM asset.uri));

-- Remove some uses of the connectby() function from the tablefunc contrib module
CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT, INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id)
          WHERE ad.depth = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou
          FROM  actor.org_unit ou
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou
          FROM  actor.org_unit ou
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ) SELECT ou.* FROM actor.org_unit ou JOIN anscestor_depth USING (id);
$$ LANGUAGE SQL;

-- Support merge template buckets
INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('template_merge','Template Merge Container');

-- Recreate one of the constraints that we just dropped,
-- under a different name:

ALTER TABLE booking.resource_type
	ADD CONSTRAINT brt_name_and_record_once_per_owner UNIQUE(owner, name, record);

-- Now upgrade permission.perm_list.  This is fairly complicated.

-- Add ON UPDATE CASCADE to some foreign keys so that, when we renumber the
-- permissions, the dependents will follow and stay in sync:

ALTER TABLE permission.grp_perm_map ADD CONSTRAINT grp_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE permission.usr_perm_map ADD CONSTRAINT usr_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE permission.usr_object_perm_map ADD CONSTRAINT usr_object_perm_map_perm_fkey FOREIGN KEY (perm)
    REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

UPDATE permission.perm_list
    SET code = 'UPDATE_ORG_UNIT_SETTING.credit.payments.allow'
    WHERE code = 'UPDATE_ORG_UNIT_SETTING.global.credit.allow';

-- The following UPDATES were originally in an individual upgrade script, but should
-- no longer be necessary now that the foreign key has an ON UPDATE CASCADE clause.
-- We retain the UPDATES here, commented out, as historical relics.

-- UPDATE permission.grp_perm_map SET perm = perm + 1000 WHERE perm NOT IN ( SELECT id FROM permission.perm_list );
-- UPDATE permission.usr_perm_map SET perm = perm + 1000 WHERE perm NOT IN ( SELECT id FROM permission.perm_list );

-- Spelling correction
UPDATE permission.perm_list SET code = 'ADMIN_RECURRING_FINE_RULE' WHERE code = 'ADMIN_RECURING_FINE_RULE';

-- Now we engage in a Great Renumbering of the permissions in permission.perm_list,
-- in order to clean up accumulated cruft.

-- The first step is to establish some triggers so that, when we change the id of a permission,
-- the associated translations are updated accordingly.

CREATE OR REPLACE FUNCTION oils_i18n_update_apply(old_ident TEXT, new_ident TEXT, hint TEXT) RETURNS VOID AS $_$
BEGIN

    EXECUTE $$
        UPDATE  config.i18n_core
          SET   identity_value = $$ || quote_literal( new_ident ) || $$ 
          WHERE fq_field LIKE '$$ || hint || $$.%' 
                AND identity_value = $$ || quote_literal( old_ident ) || $$;$$;

    RETURN;

END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_id_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.id::TEXT, NEW.id::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_code_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.code::TEXT, NEW.code::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;


CREATE TRIGGER maintain_perm_i18n_tgr
    AFTER UPDATE ON permission.perm_list
    FOR EACH ROW EXECUTE PROCEDURE oils_i18n_id_tracking('ppl');

-- Next, create a new table as a convenience for sloshing data back and forth,
-- and for recording which permission went where.  It looks just like
-- permission.perm_list, but with two extra columns: one for the old id, and one to
-- distinguish between predefined permissions and non-predefined permissions.

-- This table is, in effect, a temporary table, because we can drop it once the
-- upgrade is complete.  It is not technically temporary as far as PostgreSQL is
-- concerned, because we don't want it to disappear at the end of the session.
-- We keep it around so that we have a map showing the old id and the new id for
-- each permission.  However there is no IDL entry for it, nor is it defined
-- in the base sql files.

CREATE TABLE permission.temp_perm (
	id          INT        PRIMARY KEY,
	code        TEXT       UNIQUE,
	description TEXT,
	old_id      INT,
	predefined  BOOL       NOT NULL DEFAULT TRUE
);

-- Populate the temp table with a definitive set of predefined permissions,
-- hard-coding the ids.

-- The first set of permissions is derived from the database, as loaded in a
-- loaded 1.6.1 database, plus a few changes previously applied in this upgrade
-- script.  The second set is derived from the IDL -- permissions that are referenced
-- in <permacrud> elements but not defined in the database.

INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( -1, 'EVERYTHING',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 1, 'OPAC_LOGIN',
     'Allow a user to log in to the OPAC' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 2, 'STAFF_LOGIN',
     'Allow a user to log in to the staff client' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 3, 'MR_HOLDS',
     'Allow a user to create a metarecord holds' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 4, 'TITLE_HOLDS',
     'Allow a user to place a hold at the title level' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 5, 'VOLUME_HOLDS',
     'Allow a user to place a volume level hold' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 6, 'COPY_HOLDS',
     'Allow a user to place a hold on a specific copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 7, 'REQUEST_HOLDS',
     'Allow a user to create holds for another user (if true, we still check to make sure they have permission to make the type of hold they are requesting, for example, COPY_HOLDS)' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 8, 'REQUEST_HOLDS_OVERRIDE',
     '* no longer applicable' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 9, 'VIEW_HOLD',
     'Allow a user to view another user''s holds' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 10, 'DELETE_HOLDS',
     '* no longer applicable' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 11, 'UPDATE_HOLD',
     'Allow a user to update another user''s hold' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 12, 'RENEW_CIRC',
     'Allow a user to renew items' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 13, 'VIEW_USER_FINES_SUMMARY',
     'Allow a user to view bill details' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 14, 'VIEW_USER_TRANSACTIONS',
     'Allow a user to see another user''s grocery or circulation transactions in the Bills Interface; duplicate of VIEW_TRANSACTION' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 15, 'UPDATE_MARC',
     'Allow a user to edit a MARC record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 16, 'CREATE_MARC',
     'Allow a user to create new MARC records' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 17, 'IMPORT_MARC',
     'Allow a user to import a MARC record via the Z39.50 interface' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 18, 'CREATE_VOLUME',
     'Allow a user to create a volume' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 19, 'UPDATE_VOLUME',
     'Allow a user to edit volumes - needed for merging records. This is a duplicate of VOLUME_UPDATE; user must have both permissions at appropriate level to merge records.' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 20, 'DELETE_VOLUME',
     'Allow a user to delete a volume' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 21, 'CREATE_COPY',
     'Allow a user to create a new copy object' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 22, 'UPDATE_COPY',
     'Allow a user to edit a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 23, 'DELETE_COPY',
     'Allow a user to delete a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 24, 'RENEW_HOLD_OVERRIDE',
     'Allow a user to continue to renew an item even if it is required for a hold' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 25, 'CREATE_USER',
     'Allow a user to create another user' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 26, 'UPDATE_USER',
     'Allow a user to edit a user''s record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 27, 'DELETE_USER',
     'Allow a user to mark a user as deleted' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 28, 'VIEW_USER',
     'Allow a user to view another user''s Patron Record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 29, 'COPY_CHECKIN',
     'Allow a user to check in a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 30, 'CREATE_TRANSIT',
     'Allow a user to place an item in transit' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 31, 'VIEW_PERMISSION',
     'Allow a user to view user permissions within the user permissions editor' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 32, 'CHECKIN_BYPASS_HOLD_FULFILL',
     '* no longer applicable' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 33, 'CREATE_PAYMENT',
     'Allow a user to record payments in the Billing Interface' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 34, 'SET_CIRC_LOST',
     'Allow a user to mark an item as ''lost''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 35, 'SET_CIRC_MISSING',
     'Allow a user to mark an item as ''missing''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 36, 'SET_CIRC_CLAIMS_RETURNED',
     'Allow a user to mark an item as ''claims returned''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 37, 'CREATE_TRANSACTION',
     'Allow a user to create a new billable transaction' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 38, 'VIEW_TRANSACTION',
     'Allow a user may view another user''s transactions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 39, 'CREATE_BILL',
     'Allow a user to create a new bill on a transaction' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 40, 'VIEW_CONTAINER',
     'Allow a user to view another user''s containers (buckets)' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 41, 'CREATE_CONTAINER',
     'Allow a user to create a new container for another user' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 42, 'UPDATE_ORG_UNIT',
     'Allow a user to change the settings for an organization unit' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 43, 'VIEW_CIRCULATIONS',
     'Allow a user to see what another user has checked out' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 44, 'DELETE_CONTAINER',
     'Allow a user to delete another user''s container' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 45, 'CREATE_CONTAINER_ITEM',
     'Allow a user to create a container item for another user' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 46, 'CREATE_USER_GROUP_LINK',
     'Allow a user to add other users to permission groups' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 47, 'REMOVE_USER_GROUP_LINK',
     'Allow a user to remove other users from permission groups' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 48, 'VIEW_PERM_GROUPS',
     'Allow a user to view other users'' permission groups' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 49, 'VIEW_PERMIT_CHECKOUT',
     'Allow a user to determine whether another user can check out an item' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 50, 'UPDATE_BATCH_COPY',
     'Allow a user to edit copies in batch' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 51, 'CREATE_PATRON_STAT_CAT',
     'User may create a new patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 52, 'CREATE_COPY_STAT_CAT',
     'User may create a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 53, 'CREATE_PATRON_STAT_CAT_ENTRY',
     'User may create an entry in a patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 54, 'CREATE_COPY_STAT_CAT_ENTRY',
     'User may create an entry in a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 55, 'UPDATE_PATRON_STAT_CAT',
     'User may update a patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 56, 'UPDATE_COPY_STAT_CAT',
     'User may update a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 57, 'UPDATE_PATRON_STAT_CAT_ENTRY',
     'User may update an entry in a patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 58, 'UPDATE_COPY_STAT_CAT_ENTRY',
     'User may update an entry in a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 59, 'CREATE_PATRON_STAT_CAT_ENTRY_MAP',
     'User may link another user to an entry in a statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 60, 'CREATE_COPY_STAT_CAT_ENTRY_MAP',
     'User may link a copy to an entry in a statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 61, 'DELETE_PATRON_STAT_CAT',
     'User may delete a patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 62, 'DELETE_COPY_STAT_CAT',
     'User may delete a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 63, 'DELETE_PATRON_STAT_CAT_ENTRY',
     'User may delete an entry from a patron statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 64, 'DELETE_COPY_STAT_CAT_ENTRY',
     'User may delete an entry from a copy statistical category' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 65, 'DELETE_PATRON_STAT_CAT_ENTRY_MAP',
     'User may delete a patron statistical category entry map' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 66, 'DELETE_COPY_STAT_CAT_ENTRY_MAP',
     'User may delete a copy statistical category entry map' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 67, 'CREATE_NON_CAT_TYPE',
     'Allow a user to create a new non-cataloged item type' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 68, 'UPDATE_NON_CAT_TYPE',
     'Allow a user to update a non-cataloged item type' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 69, 'CREATE_IN_HOUSE_USE',
     'Allow a user to create a new in-house-use ' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 70, 'COPY_CHECKOUT',
     'Allow a user to check out a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 71, 'CREATE_COPY_LOCATION',
     'Allow a user to create a new copy location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 72, 'UPDATE_COPY_LOCATION',
     'Allow a user to update a copy location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 73, 'DELETE_COPY_LOCATION',
     'Allow a user to delete a copy location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 74, 'CREATE_COPY_TRANSIT',
     'Allow a user to create a transit_copy object for transiting a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 75, 'COPY_TRANSIT_RECEIVE',
     'Allow a user to close out a transit on a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 76, 'VIEW_HOLD_PERMIT',
     'Allow a user to see if another user has permission to place a hold on a given copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 77, 'VIEW_COPY_CHECKOUT_HISTORY',
     'Allow a user to view which users have checked out a given copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 78, 'REMOTE_Z3950_QUERY',
     'Allow a user to perform Z39.50 queries against remote servers' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 79, 'REGISTER_WORKSTATION',
     'Allow a user to register a new workstation' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 80, 'VIEW_COPY_NOTES',
     'Allow a user to view all notes attached to a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 81, 'VIEW_VOLUME_NOTES',
     'Allow a user to view all notes attached to a volume' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 82, 'VIEW_TITLE_NOTES',
     'Allow a user to view all notes attached to a title' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 83, 'CREATE_COPY_NOTE',
     'Allow a user to create a new copy note' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 84, 'CREATE_VOLUME_NOTE',
     'Allow a user to create a new volume note' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 85, 'CREATE_TITLE_NOTE',
     'Allow a user to create a new title note' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 86, 'DELETE_COPY_NOTE',
     'Allow a user to delete another user''s copy notes' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 87, 'DELETE_VOLUME_NOTE',
     'Allow a user to delete another user''s volume note' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 88, 'DELETE_TITLE_NOTE',
     'Allow a user to delete another user''s title note' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 89, 'UPDATE_CONTAINER',
     'Allow a user to update another user''s container' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 90, 'CREATE_MY_CONTAINER',
     'Allow a user to create a container for themselves' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 91, 'VIEW_HOLD_NOTIFICATION',
     'Allow a user to view notifications attached to a hold' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 92, 'CREATE_HOLD_NOTIFICATION',
     'Allow a user to create new hold notifications' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 93, 'UPDATE_ORG_SETTING',
     'Allow a user to update an organization unit setting' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 94, 'OFFLINE_UPLOAD',
     'Allow a user to upload an offline script' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 95, 'OFFLINE_VIEW',
     'Allow a user to view uploaded offline script information' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 96, 'OFFLINE_EXECUTE',
     'Allow a user to execute an offline script batch' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 97, 'CIRC_OVERRIDE_DUE_DATE',
     'Allow a user to change the due date on an item to any date' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 98, 'CIRC_PERMIT_OVERRIDE',
     'Allow a user to bypass the circulation permit call for check out' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 99, 'COPY_IS_REFERENCE.override',
     'Allow a user to override the copy_is_reference event' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 100, 'VOID_BILLING',
     'Allow a user to void a bill' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 101, 'CIRC_CLAIMS_RETURNED.override',
     'Allow a user to check in or check out an item that has a status of ''claims returned''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 102, 'COPY_BAD_STATUS.override',
     'Allow a user to check out an item in a non-circulatable status' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 103, 'COPY_ALERT_MESSAGE.override',
     'Allow a user to check in/out an item that has an alert message' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 104, 'COPY_STATUS_LOST.override',
     'Allow a user to remove the lost status from a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 105, 'COPY_STATUS_MISSING.override',
     'Allow a user to change the missing status on a copy' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 106, 'ABORT_TRANSIT',
     'Allow a user to abort a copy transit if the user is at the transit destination or source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 107, 'ABORT_REMOTE_TRANSIT',
     'Allow a user to abort a copy transit if the user is not at the transit source or dest' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 108, 'VIEW_ZIP_DATA',
     'Allow a user to query the ZIP code data method' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 109, 'CANCEL_HOLDS',
     'Allow a user to cancel holds' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 110, 'CREATE_DUPLICATE_HOLDS',
     'Allow a user to create duplicate holds (two or more holds on the same title)' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 111, 'actor.org_unit.closed_date.delete',
     'Allow a user to remove a closed date interval for a given location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 112, 'actor.org_unit.closed_date.update',
     'Allow a user to update a closed date interval for a given location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 113, 'actor.org_unit.closed_date.create',
     'Allow a user to create a new closed date for a location' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 114, 'DELETE_NON_CAT_TYPE',
     'Allow a user to delete a non cataloged type' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 115, 'money.collections_tracker.create',
     'Allow a user to put someone into collections' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 116, 'money.collections_tracker.delete',
     'Allow a user to remove someone from collections' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 117, 'BAR_PATRON',
     'Allow a user to bar a patron' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 118, 'UNBAR_PATRON',
     'Allow a user to un-bar a patron' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 119, 'DELETE_WORKSTATION',
     'Allow a user to remove an existing workstation so a new one can replace it' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 120, 'group_application.user',
     'Allow a user to add/remove users to/from the "User" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 121, 'group_application.user.patron',
     'Allow a user to add/remove users to/from the "Patron" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 122, 'group_application.user.staff',
     'Allow a user to add/remove users to/from the "Staff" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 123, 'group_application.user.staff.circ',
     'Allow a user to add/remove users to/from the "Circulator" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 124, 'group_application.user.staff.cat',
     'Allow a user to add/remove users to/from the "Cataloger" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 125, 'group_application.user.staff.admin.global_admin',
     'Allow a user to add/remove users to/from the "GlobalAdmin" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 126, 'group_application.user.staff.admin.local_admin',
     'Allow a user to add/remove users to/from the "LocalAdmin" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 127, 'group_application.user.staff.admin.lib_manager',
     'Allow a user to add/remove users to/from the "LibraryManager" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 128, 'group_application.user.staff.cat.cat1',
     'Allow a user to add/remove users to/from the "Cat1" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 129, 'group_application.user.staff.supercat',
     'Allow a user to add/remove users to/from the "Supercat" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 130, 'group_application.user.sip_client',
     'Allow a user to add/remove users to/from the "SIP-Client" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 131, 'group_application.user.vendor',
     'Allow a user to add/remove users to/from the "Vendor" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 132, 'ITEM_AGE_PROTECTED.override',
     'Allow a user to place a hold on an age-protected item' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 133, 'MAX_RENEWALS_REACHED.override',
     'Allow a user to renew an item past the maximum renewal count' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 134, 'PATRON_EXCEEDS_CHECKOUT_COUNT.override',
     'Allow staff to override checkout count failure' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 135, 'PATRON_EXCEEDS_OVERDUE_COUNT.override',
     'Allow staff to override overdue count failure' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 136, 'PATRON_EXCEEDS_FINES.override',
     'Allow staff to override fine amount checkout failure' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 137, 'CIRC_EXCEEDS_COPY_RANGE.override',
     'Allow staff to override circulation copy range failure' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 138, 'ITEM_ON_HOLDS_SHELF.override',
     'Allow staff to override item on holds shelf failure' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 139, 'COPY_NOT_AVAILABLE.override',
     'Allow staff to force checkout of Missing/Lost type items' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 140, 'HOLD_EXISTS.override',
     'Allow a user to place multiple holds on a single title' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 141, 'RUN_REPORTS',
     'Allow a user to run reports' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 142, 'SHARE_REPORT_FOLDER',
     'Allow a user to share report his own folders' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 143, 'VIEW_REPORT_OUTPUT',
     'Allow a user to view report output' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 144, 'COPY_CIRC_NOT_ALLOWED.override',
     'Allow a user to checkout an item that is marked as non-circ' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 145, 'DELETE_CONTAINER_ITEM',
     'Allow a user to delete an item out of another user''s container' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 146, 'ASSIGN_WORK_ORG_UNIT',
     'Allow a staff member to define where another staff member has their permissions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 147, 'CREATE_FUNDING_SOURCE',
     'Allow a user to create a new funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 148, 'DELETE_FUNDING_SOURCE',
     'Allow a user to delete a funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 149, 'VIEW_FUNDING_SOURCE',
     'Allow a user to view a funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 150, 'UPDATE_FUNDING_SOURCE',
     'Allow a user to update a funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 151, 'CREATE_FUND',
     'Allow a user to create a new fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 152, 'DELETE_FUND',
     'Allow a user to delete a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 153, 'VIEW_FUND',
     'Allow a user to view a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 154, 'UPDATE_FUND',
     'Allow a user to update a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 155, 'CREATE_FUND_ALLOCATION',
     'Allow a user to create a new fund allocation' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 156, 'DELETE_FUND_ALLOCATION',
     'Allow a user to delete a fund allocation' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 157, 'VIEW_FUND_ALLOCATION',
     'Allow a user to view a fund allocation' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 158, 'UPDATE_FUND_ALLOCATION',
     'Allow a user to update a fund allocation' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 159, 'GENERAL_ACQ',
     'Lowest level permission required to access the ACQ interface' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 160, 'CREATE_PROVIDER',
     'Allow a user to create a new provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 161, 'DELETE_PROVIDER',
     'Allow a user to delate a provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 162, 'VIEW_PROVIDER',
     'Allow a user to view a provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 163, 'UPDATE_PROVIDER',
     'Allow a user to update a provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 164, 'ADMIN_FUNDING_SOURCE',
     'Allow a user to create/view/update/delete a funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 165, 'ADMIN_FUND',
     '(Deprecated) Allow a user to create/view/update/delete a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 166, 'MANAGE_FUNDING_SOURCE',
     'Allow a user to view/credit/debit a funding source' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 167, 'MANAGE_FUND',
     'Allow a user to view/credit/debit a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 168, 'CREATE_PICKLIST',
     'Allows a user to create a picklist' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 169, 'ADMIN_PROVIDER',
     'Allow a user to create/view/update/delete a provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 170, 'MANAGE_PROVIDER',
     'Allow a user to view and purchase from a provider' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 171, 'VIEW_PICKLIST',
     'Allow a user to view another users picklist' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 172, 'DELETE_RECORD',
     'Allow a staff member to directly remove a bibliographic record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 173, 'ADMIN_CURRENCY_TYPE',
     'Allow a user to create/view/update/delete a currency_type' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 174, 'MARK_BAD_DEBT',
     'Allow a user to mark a transaction as bad (unrecoverable) debt' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 175, 'VIEW_BILLING_TYPE',
     'Allow a user to view billing types' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 176, 'MARK_ITEM_AVAILABLE',
     'Allow a user to mark an item status as ''available''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 177, 'MARK_ITEM_CHECKED_OUT',
     'Allow a user to mark an item status as ''checked out''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 178, 'MARK_ITEM_BINDERY',
     'Allow a user to mark an item status as ''bindery''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 179, 'MARK_ITEM_LOST',
     'Allow a user to mark an item status as ''lost''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 180, 'MARK_ITEM_MISSING',
     'Allow a user to mark an item status as ''missing''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 181, 'MARK_ITEM_IN_PROCESS',
     'Allow a user to mark an item status as ''in process''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 182, 'MARK_ITEM_IN_TRANSIT',
     'Allow a user to mark an item status as ''in transit''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 183, 'MARK_ITEM_RESHELVING',
     'Allow a user to mark an item status as ''reshelving''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 184, 'MARK_ITEM_ON_HOLDS_SHELF',
     'Allow a user to mark an item status as ''on holds shelf''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 185, 'MARK_ITEM_ON_ORDER',
     'Allow a user to mark an item status as ''on order''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 186, 'MARK_ITEM_ILL',
     'Allow a user to mark an item status as ''inter-library loan''' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 187, 'group_application.user.staff.acq',
     'Allows a user to add/remove/edit users in the "ACQ" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 188, 'CREATE_PURCHASE_ORDER',
     'Allows a user to create a purchase order' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 189, 'VIEW_PURCHASE_ORDER',
     'Allows a user to view a purchase order' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 190, 'IMPORT_ACQ_LINEITEM_BIB_RECORD',
     'Allows a user to import a bib record from the acq staging area (on-order record) into the ILS bib data set' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 191, 'RECEIVE_PURCHASE_ORDER',
     'Allows a user to mark a purchase order, lineitem, or individual copy as received' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 192, 'VIEW_ORG_SETTINGS',
     'Allows a user to view all org settings at the specified level' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 193, 'CREATE_MFHD_RECORD',
     'Allows a user to create a new MFHD record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 194, 'UPDATE_MFHD_RECORD',
     'Allows a user to update an MFHD record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 195, 'DELETE_MFHD_RECORD',
     'Allows a user to delete an MFHD record' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 196, 'ADMIN_ACQ_FUND',
     'Allow a user to create/view/update/delete a fund' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 197, 'group_application.user.staff.acq_admin',
     'Allows a user to add/remove/edit users in the "Acquisitions Administrators" group' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 198, 'SET_CIRC_CLAIMS_RETURNED.override',
     'Allows staff to override the max claims returned value for a patron' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 199, 'UPDATE_PATRON_CLAIM_RETURN_COUNT',
     'Allows staff to manually change a patron''s claims returned count' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 200, 'UPDATE_BILL_NOTE',
     'Allows staff to edit the note for a bill on a transaction' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 201, 'UPDATE_PAYMENT_NOTE',
     'Allows staff to edit the note for a payment on a transaction' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 202, 'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT',
     'Allows staff to manually change a patron''s claims never checkout out count' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 203, 'ADMIN_COPY_LOCATION_ORDER',
     'Allow a user to create/view/update/delete a copy location order' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 204, 'ASSIGN_GROUP_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 205, 'CREATE_AUDIENCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 206, 'CREATE_BIB_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 207, 'CREATE_CIRC_DURATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 208, 'CREATE_CIRC_MOD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 209, 'CREATE_COPY_STATUS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 210, 'CREATE_HOURS_OF_OPERATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 211, 'CREATE_ITEM_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 212, 'CREATE_ITEM_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 213, 'CREATE_LANGUAGE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 214, 'CREATE_LASSO',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 215, 'CREATE_LASSO_MAP',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 216, 'CREATE_LIT_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 217, 'CREATE_METABIB_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 218, 'CREATE_NET_ACCESS_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 219, 'CREATE_ORG_ADDRESS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 220, 'CREATE_ORG_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 221, 'CREATE_ORG_UNIT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 222, 'CREATE_ORG_UNIT_CLOSING',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 223, 'CREATE_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 224, 'CREATE_RELEVANCE_ADJUSTMENT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 225, 'CREATE_SURVEY',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 226, 'CREATE_VR_FORMAT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 227, 'CREATE_XML_TRANSFORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 228, 'DELETE_AUDIENCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 229, 'DELETE_BIB_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 230, 'DELETE_CIRC_DURATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 231, 'DELETE_CIRC_MOD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 232, 'DELETE_COPY_STATUS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 233, 'DELETE_HOURS_OF_OPERATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 234, 'DELETE_ITEM_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 235, 'DELETE_ITEM_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 236, 'DELETE_LANGUAGE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 237, 'DELETE_LASSO',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 238, 'DELETE_LASSO_MAP',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 239, 'DELETE_LIT_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 240, 'DELETE_METABIB_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 241, 'DELETE_NET_ACCESS_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 242, 'DELETE_ORG_ADDRESS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 243, 'DELETE_ORG_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 244, 'DELETE_ORG_UNIT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 245, 'DELETE_ORG_UNIT_CLOSING',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 246, 'DELETE_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 247, 'DELETE_RELEVANCE_ADJUSTMENT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 248, 'DELETE_SURVEY',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 249, 'DELETE_TRANSIT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 250, 'DELETE_VR_FORMAT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 251, 'DELETE_XML_TRANSFORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 252, 'REMOVE_GROUP_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 253, 'TRANSIT_COPY',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 254, 'UPDATE_AUDIENCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 255, 'UPDATE_BIB_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 256, 'UPDATE_CIRC_DURATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 257, 'UPDATE_CIRC_MOD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 258, 'UPDATE_COPY_NOTE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 259, 'UPDATE_COPY_STATUS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 260, 'UPDATE_GROUP_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 261, 'UPDATE_HOURS_OF_OPERATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 262, 'UPDATE_ITEM_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 263, 'UPDATE_ITEM_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 264, 'UPDATE_LANGUAGE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 265, 'UPDATE_LASSO',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 266, 'UPDATE_LASSO_MAP',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 267, 'UPDATE_LIT_FORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 268, 'UPDATE_METABIB_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 269, 'UPDATE_NET_ACCESS_LEVEL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 270, 'UPDATE_ORG_ADDRESS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 271, 'UPDATE_ORG_TYPE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 272, 'UPDATE_ORG_UNIT_CLOSING',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 273, 'UPDATE_PERM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 274, 'UPDATE_RELEVANCE_ADJUSTMENT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 275, 'UPDATE_SURVEY',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 276, 'UPDATE_TRANSIT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 277, 'UPDATE_VOLUME_NOTE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 278, 'UPDATE_VR_FORMAT',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 279, 'UPDATE_XML_TRANSFORM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 280, 'MERGE_BIB_RECORDS',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 281, 'UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 282, 'CREATE_ACQ_FUNDING_SOURCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 283, 'CREATE_AUTHORITY_IMPORT_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 284, 'CREATE_AUTHORITY_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 285, 'CREATE_AUTHORITY_RECORD_NOTE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 286, 'CREATE_BIB_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 287, 'CREATE_BIB_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 288, 'CREATE_LOCALE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 289, 'CREATE_MARC_CODE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 290, 'CREATE_TRANSLATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 291, 'DELETE_ACQ_FUNDING_SOURCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 292, 'DELETE_AUTHORITY_IMPORT_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 293, 'DELETE_AUTHORITY_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 294, 'DELETE_AUTHORITY_RECORD_NOTE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 295, 'DELETE_BIB_IMPORT_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 296, 'DELETE_BIB_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 297, 'DELETE_LOCALE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 298, 'DELETE_MARC_CODE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 299, 'DELETE_TRANSLATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 300, 'UPDATE_ACQ_FUNDING_SOURCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 301, 'UPDATE_AUTHORITY_IMPORT_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 302, 'UPDATE_AUTHORITY_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 303, 'UPDATE_AUTHORITY_RECORD_NOTE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 304, 'UPDATE_BIB_IMPORT_IMPORT_FIELD_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 305, 'UPDATE_BIB_IMPORT_QUEUE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 306, 'UPDATE_LOCALE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 307, 'UPDATE_MARC_CODE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 308, 'UPDATE_TRANSLATION',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 309, 'VIEW_ACQ_FUNDING_SOURCE',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 310, 'VIEW_AUTHORITY_RECORD_NOTES',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 311, 'CREATE_IMPORT_ITEM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 312, 'CREATE_IMPORT_ITEM_ATTR_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 313, 'CREATE_IMPORT_TRASH_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 314, 'DELETE_IMPORT_ITEM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 315, 'DELETE_IMPORT_ITEM_ATTR_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 316, 'DELETE_IMPORT_TRASH_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 317, 'UPDATE_IMPORT_ITEM',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 318, 'UPDATE_IMPORT_ITEM_ATTR_DEF',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 319, 'UPDATE_IMPORT_TRASH_FIELD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 320, 'UPDATE_ORG_UNIT_SETTING_ALL',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 321, 'UPDATE_ORG_UNIT_SETTING.circ.lost_materials_processing_fee',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 322, 'UPDATE_ORG_UNIT_SETTING.cat.default_item_price',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 323, 'UPDATE_ORG_UNIT_SETTING.auth.opac_timeout',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 324, 'UPDATE_ORG_UNIT_SETTING.auth.staff_timeout',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 325, 'UPDATE_ORG_UNIT_SETTING.org.bounced_emails',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 326, 'UPDATE_ORG_UNIT_SETTING.circ.hold_expire_alert_interval',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 327, 'UPDATE_ORG_UNIT_SETTING.circ.hold_expire_interval',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 328, 'UPDATE_ORG_UNIT_SETTING.credit.payments.allow',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 329, 'UPDATE_ORG_UNIT_SETTING.circ.void_overdue_on_lost',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 330, 'UPDATE_ORG_UNIT_SETTING.circ.hold_stalling.soft',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 331, 'UPDATE_ORG_UNIT_SETTING.circ.hold_boundary.hard',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 332, 'UPDATE_ORG_UNIT_SETTING.circ.hold_boundary.soft',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 333, 'UPDATE_ORG_UNIT_SETTING.opac.barcode_regex',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 334, 'UPDATE_ORG_UNIT_SETTING.global.password_regex',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 335, 'UPDATE_ORG_UNIT_SETTING.circ.item_checkout_history.max',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 336, 'UPDATE_ORG_UNIT_SETTING.circ.reshelving_complete.interval',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 337, 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.patron_login_timeout',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 338, 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.alert_on_checkout_event',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 339, 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 340, 'UPDATE_ORG_UNIT_SETTING.global.juvenile_age_threshold',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 341, 'UPDATE_ORG_UNIT_SETTING.cat.bib.keep_on_empty',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 342, 'UPDATE_ORG_UNIT_SETTING.cat.bib.alert_on_empty',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 343, 'UPDATE_ORG_UNIT_SETTING.patron.password.use_phone',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 344, 'HOLD_ITEM_CHECKED_OUT.override',
     'Allows a user to place a hold on an item that they already have checked out' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 345, 'ADMIN_ACQ_CANCEL_CAUSE',
     'Allow a user to create/update/delete reasons for order cancellations' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 346, 'ACQ_XFER_MANUAL_DFUND_AMOUNT',
     'Allow a user to transfer different amounts of money out of one fund and into another' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 347, 'OVERRIDE_HOLD_HAS_LOCAL_COPY',
     'Allow a user to override the circ.holds.hold_has_copy_at.block setting' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 348, 'UPDATE_PICKUP_LIB_FROM_TRANSIT',
     'Allow a user to change the pickup and transit destination for a captured hold item already in transit' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 349, 'COPY_NEEDED_FOR_HOLD.override',
     'Allow a user to force renewal of an item that could fulfill a hold request' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 350, 'MERGE_AUTH_RECORDS',
     'Allow a user to merge authority records together' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 351, 'ALLOW_ALT_TCN',
     'Allows staff to import a record using an alternate TCN to avoid conflicts' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 352, 'ADMIN_TRIGGER_EVENT_DEF',
     'Allow a user to administer trigger event definitions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 353, 'ADMIN_TRIGGER_CLEANUP',
     'Allow a user to create, delete, and update trigger cleanup entries' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 354, 'CREATE_TRIGGER_CLEANUP',
     'Allow a user to create trigger cleanup entries' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 355, 'DELETE_TRIGGER_CLEANUP',
     'Allow a user to delete trigger cleanup entries' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 356, 'UPDATE_TRIGGER_CLEANUP',
     'Allow a user to update trigger cleanup entries' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 357, 'CREATE_TRIGGER_EVENT_DEF',
     'Allow a user to create trigger event definitions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 358, 'DELETE_TRIGGER_EVENT_DEF',
     'Allow a user to delete trigger event definitions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 359, 'UPDATE_TRIGGER_EVENT_DEF',
     'Allow a user to update trigger event definitions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 360, 'VIEW_TRIGGER_EVENT_DEF',
     'Allow a user to view trigger event definitions' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 361, 'ADMIN_TRIGGER_HOOK',
     'Allow a user to create, update, and delete trigger hooks' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 362, 'CREATE_TRIGGER_HOOK',
     'Allow a user to create trigger hooks' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 363, 'DELETE_TRIGGER_HOOK',
     'Allow a user to delete trigger hooks' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 364, 'UPDATE_TRIGGER_HOOK',
     'Allow a user to update trigger hooks' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 365, 'ADMIN_TRIGGER_REACTOR',
     'Allow a user to create, update, and delete trigger reactors' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 366, 'CREATE_TRIGGER_REACTOR',
     'Allow a user to create trigger reactors' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 367, 'DELETE_TRIGGER_REACTOR',
     'Allow a user to delete trigger reactors' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 368, 'UPDATE_TRIGGER_REACTOR',
     'Allow a user to update trigger reactors' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 369, 'ADMIN_TRIGGER_TEMPLATE_OUTPUT',
     'Allow a user to delete trigger template output' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 370, 'DELETE_TRIGGER_TEMPLATE_OUTPUT',
     'Allow a user to delete trigger template output' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 371, 'ADMIN_TRIGGER_VALIDATOR',
     'Allow a user to create, update, and delete trigger validators' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 372, 'CREATE_TRIGGER_VALIDATOR',
     'Allow a user to create trigger validators' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 373, 'DELETE_TRIGGER_VALIDATOR',
     'Allow a user to delete trigger validators' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 374, 'UPDATE_TRIGGER_VALIDATOR',
     'Allow a user to update trigger validators' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 376, 'ADMIN_BOOKING_RESOURCE',
     'Enables the user to create/update/delete booking resources' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 377, 'ADMIN_BOOKING_RESOURCE_TYPE',
     'Enables the user to create/update/delete booking resource types' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 378, 'ADMIN_BOOKING_RESOURCE_ATTR',
     'Enables the user to create/update/delete booking resource attributes' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 379, 'ADMIN_BOOKING_RESOURCE_ATTR_MAP',
     'Enables the user to create/update/delete booking resource attribute maps' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 380, 'ADMIN_BOOKING_RESOURCE_ATTR_VALUE',
     'Enables the user to create/update/delete booking resource attribute values' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 381, 'ADMIN_BOOKING_RESERVATION',
     'Enables the user to create/update/delete booking reservations' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 382, 'ADMIN_BOOKING_RESERVATION_ATTR_VALUE_MAP',
     'Enables the user to create/update/delete booking reservation attribute value maps' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 383, 'RETRIEVE_RESERVATION_PULL_LIST',
     'Allows a user to retrieve a booking reservation pull list' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 384, 'CAPTURE_RESERVATION',
     'Allows a user to capture booking reservations' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 385, 'UPDATE_RECORD',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 386, 'UPDATE_ORG_UNIT_SETTING.circ.block_renews_for_holds',
     '' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 387, 'MERGE_USERS',
     'Allows user records to be merged' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 388, 'ISSUANCE_HOLDS',
     'Allow a user to place holds on serials issuances' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 389, 'VIEW_CREDIT_CARD_PROCESSING',
     'View org unit settings related to credit card processing' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 390, 'ADMIN_CREDIT_CARD_PROCESSING',
     'Update org unit settings related to credit card processing' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 391, 'ADMIN_SERIAL_CAPTION_PATTERN',
	'Create/update/delete serial caption and pattern objects' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 392, 'ADMIN_SERIAL_SUBSCRIPTION',
	'Create/update/delete serial subscription objects' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 393, 'ADMIN_SERIAL_DISTRIBUTION',
	'Create/update/delete serial distribution objects' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 394, 'ADMIN_SERIAL_STREAM',
	'Create/update/delete serial stream objects' );
INSERT INTO permission.temp_perm ( id, code, description ) VALUES ( 395, 'RECEIVE_SERIAL',
	'Receive serial items' );

-- Now for the permissions from the IDL.  We don't have descriptions for them.

INSERT INTO permission.temp_perm ( id, code ) VALUES ( 396, 'ADMIN_ACQ_CLAIM' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 397, 'ADMIN_ACQ_CLAIM_EVENT_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 398, 'ADMIN_ACQ_CLAIM_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 399, 'ADMIN_ACQ_DISTRIB_FORMULA' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 400, 'ADMIN_ACQ_FISCAL_YEAR' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 401, 'ADMIN_ACQ_FUND_ALLOCATION_PERCENT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 402, 'ADMIN_ACQ_FUND_TAG' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 403, 'ADMIN_ACQ_LINEITEM_ALERT_TEXT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 404, 'ADMIN_AGE_PROTECT_RULE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 405, 'ADMIN_ASSET_COPY_TEMPLATE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 406, 'ADMIN_BOOKING_RESERVATION_ATTR_MAP' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 407, 'ADMIN_CIRC_MATRIX_MATCHPOINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 408, 'ADMIN_CIRC_MOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 409, 'ADMIN_CLAIM_POLICY' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 410, 'ADMIN_CONFIG_REMOTE_ACCOUNT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 411, 'ADMIN_FIELD_DOC' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 412, 'ADMIN_GLOBAL_FLAG' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 413, 'ADMIN_GROUP_PENALTY_THRESHOLD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 414, 'ADMIN_HOLD_CANCEL_CAUSE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 415, 'ADMIN_HOLD_MATRIX_MATCHPOINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 416, 'ADMIN_IDENT_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 417, 'ADMIN_IMPORT_ITEM_ATTR_DEF' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 418, 'ADMIN_INDEX_NORMALIZER' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 419, 'ADMIN_INVOICE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 420, 'ADMIN_INVOICE_METHOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 421, 'ADMIN_INVOICE_PAYMENT_METHOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 422, 'ADMIN_LINEITEM_MARC_ATTR_DEF' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 423, 'ADMIN_MARC_CODE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 424, 'ADMIN_MAX_FINE_RULE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 425, 'ADMIN_MERGE_PROFILE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 426, 'ADMIN_ORG_UNIT_SETTING_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 427, 'ADMIN_RECURRING_FINE_RULE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 428, 'ADMIN_STANDING_PENALTY' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 429, 'ADMIN_SURVEY' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 430, 'ADMIN_USER_REQUEST_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 431, 'ADMIN_USER_SETTING_GROUP' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 432, 'ADMIN_USER_SETTING_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 433, 'ADMIN_Z3950_SOURCE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 434, 'CREATE_BIB_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 435, 'CREATE_BIBLIO_FINGERPRINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 436, 'CREATE_BIB_SOURCE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 437, 'CREATE_BILLING_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 438, 'CREATE_CN_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 439, 'CREATE_COPY_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 440, 'CREATE_INVOICE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 441, 'CREATE_INVOICE_ITEM_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 442, 'CREATE_INVOICE_METHOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 443, 'CREATE_MERGE_PROFILE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 444, 'CREATE_METABIB_CLASS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 445, 'CREATE_METABIB_SEARCH_ALIAS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 446, 'CREATE_USER_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 447, 'DELETE_BIB_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 448, 'DELETE_BIBLIO_FINGERPRINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 449, 'DELETE_BIB_SOURCE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 450, 'DELETE_BILLING_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 451, 'DELETE_CN_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 452, 'DELETE_COPY_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 453, 'DELETE_INVOICE_ITEM_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 454, 'DELETE_INVOICE_METHOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 455, 'DELETE_MERGE_PROFILE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 456, 'DELETE_METABIB_CLASS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 457, 'DELETE_METABIB_SEARCH_ALIAS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 458, 'DELETE_USER_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 459, 'MANAGE_CLAIM' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 460, 'UPDATE_BIB_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 461, 'UPDATE_BIBLIO_FINGERPRINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 462, 'UPDATE_BIB_SOURCE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 463, 'UPDATE_BILLING_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 464, 'UPDATE_CN_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 465, 'UPDATE_COPY_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 466, 'UPDATE_INVOICE_ITEM_TYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 467, 'UPDATE_INVOICE_METHOD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 468, 'UPDATE_MERGE_PROFILE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 469, 'UPDATE_METABIB_CLASS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 470, 'UPDATE_METABIB_SEARCH_ALIAS' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 471, 'UPDATE_USER_BTYPE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 472, 'user_request.create' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 473, 'user_request.delete' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 474, 'user_request.update' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 475, 'user_request.view' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 476, 'VIEW_ACQ_FUND_ALLOCATION_PERCENT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 477, 'VIEW_CIRC_MATRIX_MATCHPOINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 478, 'VIEW_CLAIM' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 479, 'VIEW_GROUP_PENALTY_THRESHOLD' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 480, 'VIEW_HOLD_MATRIX_MATCHPOINT' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 481, 'VIEW_INVOICE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 482, 'VIEW_MERGE_PROFILE' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 483, 'VIEW_SERIAL_SUBSCRIPTION' );
INSERT INTO permission.temp_perm ( id, code ) VALUES ( 484, 'VIEW_STANDING_PENALTY' );

-- For every permission in the temp_perm table that has a matching
-- permission in the real table: record the original id.

UPDATE permission.temp_perm AS tp
SET old_id =
	(
		SELECT id
		FROM permission.perm_list AS ppl
		WHERE ppl.code = tp.code
	)
WHERE code IN ( SELECT code FROM permission.perm_list );

-- Start juggling ids.

-- If any permissions have negative ids (with the special exception of -1),
-- we need to move them into the positive range in order to avoid duplicate
-- key problems (since we are going to use the negative range as a temporary
-- staging area).

-- First, move any predefined permissions that have negative ids (again with
-- the special exception of -1).  Temporarily give them positive ids based on
-- the sequence.

UPDATE permission.perm_list
SET id = NEXTVAL('permission.perm_list_id_seq'::regclass)
WHERE id < -1
  AND code IN (SELECT code FROM permission.temp_perm);

-- Identify any non-predefined permissions whose ids are either negative
-- or within the range (0-1000) reserved for predefined permissions.
-- Assign them ids above 1000, based on the sequence.  Record the new
-- ids in the temp_perm table.

INSERT INTO permission.temp_perm ( id, code, description, old_id, predefined )
(
	SELECT NEXTVAL('permission.perm_list_id_seq'::regclass),
		code, description, id, false
	FROM permission.perm_list
	WHERE  ( id < -1 OR id BETWEEN 0 AND 1000 )
	AND code NOT IN (SELECT code FROM permission.temp_perm)
);

-- Now update the ids of those non-predefined permissions, using the
-- values assigned in the previous step.

UPDATE permission.perm_list AS ppl
SET id = (
		SELECT id
		FROM permission.temp_perm AS tp
		WHERE tp.code = ppl.code
	)
WHERE id IN ( SELECT old_id FROM permission.temp_perm WHERE NOT predefined );

-- Now the negative ids have been eliminated, except for -1.  Move all the
-- predefined permissions temporarily into the negative range.

UPDATE permission.perm_list
SET id = -1 - id
WHERE id <> -1
AND code IN ( SELECT code from permission.temp_perm WHERE predefined );

-- Apply the final ids to the existing predefined permissions.

UPDATE permission.perm_list AS ppl
SET id =
	(
		SELECT id
		FROM permission.temp_perm AS tp
		WHERE tp.code = ppl.code
	)
WHERE
	id <> -1
	AND ppl.code IN
	(
		SELECT code from permission.temp_perm
		WHERE predefined
		AND old_id IS NOT NULL
	);

-- If there are any predefined permissions that don't exist yet in
-- permission.perm_list, insert them now.

INSERT INTO permission.perm_list ( id, code, description )
(
	SELECT id, code, description
	FROM permission.temp_perm
	WHERE old_id IS NULL
);

-- Reset the sequence to the lowest feasible value.  This may or may not
-- accomplish anything, but it will do no harm.

SELECT SETVAL('permission.perm_list_id_seq'::TEXT, GREATEST( 
	(SELECT MAX(id) FROM permission.perm_list), 1000 ));

-- If any permission lacks a description, use the code as a description.
-- It's better than nothing.

UPDATE permission.perm_list
SET description = code
WHERE description IS NULL
   OR description = '';

-- Thus endeth the Great Renumbering.

-- Having massaged the permissions, massage the way they are assigned, by inserting
-- rows into permission.grp_perm_map.  Some of these permissions may have already
-- been assigned, so we insert the rows only if they aren't already there.

-- for backwards compat, give everyone the permission
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 1, id, 0, false FROM permission.perm_list AS perm
	WHERE code = 'HOLD_ITEM_CHECKED_OUT.override'
		AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				grp = 1
				AND map.perm = perm.id
		);

-- Add trigger administration permissions to the Local System Administrator group.
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 1, false FROM permission.perm_list AS perm
    WHERE (
		perm.code LIKE 'ADMIN_TRIGGER%'
        OR perm.code LIKE 'CREATE_TRIGGER%'
        OR perm.code LIKE 'DELETE_TRIGGER%'
        OR perm.code LIKE 'UPDATE_TRIGGER%'
	) AND NOT EXISTS (
		SELECT 1
		FROM permission.grp_perm_map AS map
		WHERE
			grp = 10
			AND map.perm = perm.id
	);

-- View trigger permissions are required at a consortial level for initial setup
-- (as before, only if the row doesn't already exist)
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 10, id, 0, false FROM permission.perm_list AS perm
	WHERE code LIKE 'VIEW_TRIGGER%'
		AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				grp = 10
				AND map.perm = perm.id
		);

-- Permission for merging auth records may already be defined,
-- so add it only if it isn't there.
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT 4, id, 1, false FROM permission.perm_list AS perm
	WHERE code = 'MERGE_AUTH_RECORDS'
		AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				grp = 4
				AND map.perm = perm.id
		);

-- Create a reference table as parent to both
-- config.org_unit_setting_type and config_usr_setting_type

CREATE TABLE config.settings_group (
    name    TEXT PRIMARY KEY,
    label   TEXT UNIQUE NOT NULL -- I18N
);

-- org_unit setting types
CREATE TABLE config.org_unit_setting_type (
    name            TEXT    PRIMARY KEY,
    label           TEXT    UNIQUE NOT NULL,
    grp             TEXT    REFERENCES config.settings_group (name),
    description     TEXT,
    datatype        TEXT    NOT NULL DEFAULT 'string',
    fm_class        TEXT,
    view_perm       INT,
    update_perm     INT,
    --
    -- define valid datatypes
    --
    CONSTRAINT coust_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
      'date', 'string', 'object', 'array', 'link' ) ),
    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT coust_no_empty_link CHECK
    ( ( datatype =  'link' AND fm_class IS NOT NULL ) OR
      ( datatype <> 'link' AND fm_class IS NULL ) ),
	CONSTRAINT view_perm_fkey FOREIGN KEY (view_perm) REFERENCES permission.perm_list (id)
		ON UPDATE CASCADE
		ON DELETE RESTRICT
		DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT update_perm_fkey FOREIGN KEY (update_perm) REFERENCES permission.perm_list (id)
		ON UPDATE CASCADE
		DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE config.usr_setting_type (

    name TEXT PRIMARY KEY,
    opac_visible BOOL NOT NULL DEFAULT FALSE,
    label TEXT UNIQUE NOT NULL,
    description TEXT,
    grp             TEXT    REFERENCES config.settings_group (name),
    datatype TEXT NOT NULL DEFAULT 'string',
    fm_class TEXT,

    --
    -- define valid datatypes
    --
    CONSTRAINT coust_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
        'date', 'string', 'object', 'array', 'link' ) ),

    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT coust_no_empty_link CHECK
    ( ( datatype = 'link' AND fm_class IS NOT NULL ) OR
        ( datatype <> 'link' AND fm_class IS NULL ) )

);

--------------------------------------
-- Seed data for org_unit_setting_type
--------------------------------------

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES

( 'auth.opac_timeout',
  'OPAC Inactivity Timeout (in seconds)',
  null,
  'integer' ),

( 'auth.staff_timeout',
  'Staff Login Inactivity Timeout (in seconds)',
  null,
  'integer' ),

( 'circ.lost_materials_processing_fee',
  'Lost Materials Processing Fee',
  null,
  'currency' ),

( 'cat.default_item_price',
  'Default Item Price',
  null,
  'currency' ),

( 'org.bounced_emails',
  'Sending email address for patron notices',
  null,
  'string' ),

( 'circ.hold_expire_alert_interval',
  'Holds: Expire Alert Interval',
  'Amount of time before a hold expires at which point the patron should be alerted',
  'interval' ),

( 'circ.hold_expire_interval',
  'Holds: Expire Interval',
  'Amount of time after a hold is placed before the hold expires.  Example "100 days"',
  'interval' ),

( 'credit.payments.allow',
  'Allow Credit Card Payments',
  'If enabled, patrons will be able to pay fines accrued at this location via credit card',
  'bool' ),

( 'global.default_locale',
  'Global Default Locale',
  null,
  'string' ),

( 'circ.void_overdue_on_lost',
  'Void overdue fines when items are marked lost',
  null,
  'bool' ),

( 'circ.hold_stalling.soft',
  'Holds: Soft stalling interval',
  'How long to wait before allowing remote items to be opportunistically captured for a hold.  Example "5 days"',
  'interval' ),

( 'circ.hold_stalling_hard',
  'Holds: Hard stalling interval',
  '',
  'interval' ),

( 'circ.hold_boundary.hard',
  'Holds: Hard boundary',
  null,
  'integer' ),

( 'circ.hold_boundary.soft',
  'Holds: Soft boundary',
  null,
  'integer' ),

( 'opac.barcode_regex',
  'Patron barcode format',
  'Regular expression defining the patron barcode format',
  'string' ),

( 'global.password_regex',
  'Password format',
  'Regular expression defining the password format',
  'string' ),

( 'circ.item_checkout_history.max',
  'Maximum previous checkouts displayed',
  'This is the maximum number of previous circulations the staff client will display when investigating item details',
  'integer' ),

( 'circ.reshelving_complete.interval',
  'Change reshelving status interval',
  'Amount of time to wait before changing an item from "reshelving" status to "available".  Examples: "1 day", "6 hours"',
  'interval' ),

( 'circ.holds.default_estimated_wait_interval',
  'Holds: Default Estimated Wait',
  'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the default estimated length of time to assume an item will be checked out.',
  'interval' ),

( 'circ.holds.min_estimated_wait_interval',
  'Holds: Minimum Estimated Wait',
  'When predicting the amount of time a patron will be waiting for a hold to be fulfilled, this is the minimum estimated length of time to assume an item will be checked out.',
  'interval' ),

( 'circ.selfcheck.patron_login_timeout',
  'Selfcheck: Patron Login Timeout (in seconds)',
  'Number of seconds of inactivity before the patron is logged out of the selfcheck interface',
  'integer' ),

( 'circ.selfcheck.alert.popup',
  'Selfcheck: Pop-up alert for errors',
  'If true, checkout/renewal errors will cause a pop-up window in addition to the on-screen message',
  'bool' ),

( 'circ.selfcheck.require_patron_password',
  'Selfcheck: Require patron password',
  'If true, patrons will be required to enter their password in addition to their username/barcode to log into the selfcheck interface',
  'bool' ),

( 'global.juvenile_age_threshold',
  'Juvenile Age Threshold',
  'The age at which a user is no long considered a juvenile.  For example, "18 years".',
  'interval' ),

( 'cat.bib.keep_on_empty',
  'Retain empty bib records',
  'Retain a bib record even when all attached copies are deleted',
  'bool' ),

( 'cat.bib.alert_on_empty',
  'Alert on empty bib records',
  'Alert staff when the last copy for a record is being deleted',
  'bool' ),

( 'patron.password.use_phone',
  'Patron: password from phone #',
  'Use the last 4 digits of the patrons phone number as the default password when creating new users',
  'bool' ),

( 'circ.charge_on_damaged',
  'Charge item price when marked damaged',
  'Charge item price when marked damaged',
  'bool' ),

( 'circ.charge_lost_on_zero',
  'Charge lost on zero',
  '',
  'bool' ),

( 'circ.damaged_item_processing_fee',
  'Charge processing fee for damaged items',
  'Charge processing fee for damaged items',
  'currency' ),

( 'circ.void_lost_on_checkin',
  'Circ: Void lost item billing when returned',
  'Void lost item billing when returned',
  'bool' ),

( 'circ.max_accept_return_of_lost',
  'Circ: Void lost max interval',
  'Items that have been lost this long will not result in voided billings when returned.  E.g. ''6 months''',
  'interval' ),

( 'circ.void_lost_proc_fee_on_checkin',
  'Circ: Void processing fee on lost item return',
  'Void processing fee when lost item returned',
  'bool' ),

( 'circ.restore_overdue_on_lost_return',
  'Circ: Restore overdues on lost item return',
  'Restore overdue fines on lost item return',
  'bool' ),

( 'circ.lost_immediately_available',
  'Circ: Lost items usable on checkin',
  'Lost items are usable on checkin instead of going ''home'' first',
  'bool' ),

( 'circ.holds_fifo',
  'Holds: FIFO',
  'Force holds to a more strict First-In, First-Out capture',
  'bool' ),

( 'opac.allow_pending_address',
  'OPAC: Allow pending addresses',
  'If enabled, patrons can create and edit existing addresses.  Addresses are kept in a pending state until staff approves the changes',
  'bool' ),

( 'ui.circ.show_billing_tab_on_bills',
  'Show billing tab first when bills are present',
  'If enabled and a patron has outstanding bills and the alert page is not required, show the billing tab by default, instead of the checkout tab, when a patron is loaded',
  'bool' ),

( 'ui.general.idle_timeout',
    'GUI: Idle timeout',
    'If you want staff client windows to be minimized after a certain amount of system idle time, set this to the number of seconds of idle time that you want to allow before minimizing (requires staff client restart).',
    'integer' ),

( 'ui.circ.in_house_use.entry_cap',
  'GUI: Record In-House Use: Maximum # of uses allowed per entry.',
  'The # of uses entry in the Record In-House Use interface may not exceed the value of this setting.',
  'integer' ),

( 'ui.circ.in_house_use.entry_warn',
  'GUI: Record In-House Use: # of uses threshold for Are You Sure? dialog.',
  'In the Record In-House Use interface, a submission attempt will warn if the # of uses field exceeds the value of this setting.',
  'integer' ),

( 'acq.default_circ_modifier',
  'Default circulation modifier',
  null,
  'string' ),

( 'acq.tmp_barcode_prefix',
  'Temporary barcode prefix',
  null,
  'string' ),

( 'acq.tmp_callnumber_prefix',
  'Temporary call number prefix',
  null,
  'string' ),

( 'ui.circ.patron_summary.horizontal',
  'Patron circulation summary is horizontal',
  null,
  'bool' ),

( 'ui.staff.require_initials',
  oils_i18n_gettext('ui.staff.require_initials', 'GUI: Require staff initials for entry/edit of item/patron/penalty notes/messages.', 'coust', 'label'),
  oils_i18n_gettext('ui.staff.require_initials', 'Appends staff initials and edit date into note content.', 'coust', 'description'),
  'bool' ),

( 'ui.general.button_bar',
  'Button bar',
  null,
  'bool' ),

( 'circ.hold_shelf_status_delay',
  'Hold Shelf Status Delay',
  'The purpose is to provide an interval of time after an item goes into the on-holds-shelf status before it appears to patrons that it is actually on the holds shelf.  This gives staff time to process the item before it shows as ready-for-pickup.',
  'interval' ),

( 'circ.patron_invalid_address_apply_penalty',
  'Invalid patron address penalty',
  'When set, if a patron address is set to invalid, a penalty is applied.',
  'bool' ),

( 'circ.checkout_fills_related_hold',
  'Checkout Fills Related Hold',
  'When a patron checks out an item and they have no holds that directly target the item, the system will attempt to find a hold for the patron that could be fulfilled by the checked out item and fulfills it',
  'bool'),

( 'circ.selfcheck.auto_override_checkout_events',
  'Selfcheck override events list',
  'List of checkout/renewal events that the selfcheck interface should automatically override instead instead of alerting and stopping the transaction',
  'array' ),

( 'circ.staff_client.do_not_auto_attempt_print',
  'Disable Automatic Print Attempt Type List',
  'Disable automatic print attempts from staff client interfaces for the receipt types in this list.  Possible values: "Checkout", "Bill Pay", "Hold Slip", "Transit Slip", and "Hold/Transit Slip".  This is different from the Auto-Print checkbox in the pertinent interfaces in that it disables automatic print attempts altogether, rather than encouraging silent printing by suppressing the print dialog.  The Auto-Print checkbox in these interfaces have no effect on the behavior for this setting.  In the case of the Hold, Transit, and Hold/Transit slips, this also suppresses the alert dialogs that precede the print dialog (the ones that offer Print and Do Not Print as options).',
  'array' ),

( 'ui.patron.default_inet_access_level',
  'Default level of patrons'' internet access',
  null,
  'integer' ),

( 'circ.max_patron_claim_return_count',
    'Max Patron Claims Returned Count',
    'When this count is exceeded, a staff override is required to mark the item as claims returned',
    'integer' ),

( 'circ.obscure_dob',
    'Obscure the Date of Birth field',
    'When true, the Date of Birth column in patron lists will default to Not Visible, and in the Patron Summary sidebar the value will display as <Hidden> unless the field label is clicked.',
    'bool' ),

( 'circ.auto_hide_patron_summary',
    'GUI: Toggle off the patron summary sidebar after first view.',
    'When true, the patron summary sidebar will collapse after a new patron sub-interface is selected.',
    'bool' ),

( 'credit.processor.default',
    'Credit card processing: Name default credit processor',
    'This can be "AuthorizeNet", "PayPal" (for the Website Payment Pro API), or "PayflowPro".',
    'string' ),

( 'credit.processor.authorizenet.enabled',
    'Credit card processing: AuthorizeNet enabled',
    '',
    'bool' ),

( 'credit.processor.authorizenet.login',
    'Credit card processing: AuthorizeNet login',
    '',
    'string' ),

( 'credit.processor.authorizenet.password',
    'Credit card processing: AuthorizeNet password',
    '',
    'string' ),

( 'credit.processor.authorizenet.server',
    'Credit card processing: AuthorizeNet server',
    'Required if using a developer/test account with AuthorizeNet',
    'string' ),

( 'credit.processor.authorizenet.testmode',
    'Credit card processing: AuthorizeNet test mode',
    '',
    'bool' ),

( 'credit.processor.paypal.enabled',
    'Credit card processing: PayPal enabled',
    '',
    'bool' ),
( 'credit.processor.paypal.login',
    'Credit card processing: PayPal login',
    '',
    'string' ),
( 'credit.processor.paypal.password',
    'Credit card processing: PayPal password',
    '',
    'string' ),
( 'credit.processor.paypal.signature',
    'Credit card processing: PayPal signature',
    '',
    'string' ),
( 'credit.processor.paypal.testmode',
    'Credit card processing: PayPal test mode',
    '',
    'bool' ),

( 'ui.admin.work_log.max_entries',
    oils_i18n_gettext('ui.admin.work_log.max_entries', 'GUI: Work Log: Maximum Actions Logged', 'coust', 'label'),
    oils_i18n_gettext('ui.admin.work_log.max_entries', 'Maximum entries for "Most Recent Staff Actions" section of the Work Log interface.', 'coust', 'description'),
  'interval' ),

( 'ui.admin.patron_log.max_entries',
    oils_i18n_gettext('ui.admin.patron_log.max_entries', 'GUI: Work Log: Maximum Patrons Logged', 'coust', 'label'),
    oils_i18n_gettext('ui.admin.patron_log.max_entries', 'Maximum entries for "Most Recently Affected Patrons..." section of the Work Log interface.', 'coust', 'description'),
  'interval' ),

( 'lib.courier_code',
    oils_i18n_gettext('lib.courier_code', 'Courier Code', 'coust', 'label'),
    oils_i18n_gettext('lib.courier_code', 'Courier Code for the library.  Available in transit slip templates as the %courier_code% macro.', 'coust', 'description'),
    'string'),

( 'circ.block_renews_for_holds',
    oils_i18n_gettext('circ.block_renews_for_holds', 'Holds: Block Renewal of Items Needed for Holds', 'coust', 'label'),
    oils_i18n_gettext('circ.block_renews_for_holds', 'When an item could fulfill a hold, do not allow the current patron to renew', 'coust', 'description'),
    'bool' ),

( 'circ.password_reset_request_per_user_limit',
    oils_i18n_gettext('circ.password_reset_request_per_user_limit', 'Circulation: Maximum concurrently active self-serve password reset requests per user', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_per_user_limit', 'When a user has more than this number of concurrently active self-serve password reset requests for their account, prevent the user from creating any new self-serve password reset requests until the number of active requests for the user drops back below this number.', 'coust', 'description'),
    'string'),

( 'circ.password_reset_request_time_to_live',
    oils_i18n_gettext('circ.password_reset_request_time_to_live', 'Circulation: Self-serve password reset request time-to-live', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_time_to_live', 'Length of time (in seconds) a self-serve password reset request should remain active.', 'coust', 'description'),
    'string'),

( 'circ.password_reset_request_throttle',
    oils_i18n_gettext('circ.password_reset_request_throttle', 'Circulation: Maximum concurrently active self-serve password reset requests', 'coust', 'label'),
    oils_i18n_gettext('circ.password_reset_request_throttle', 'Prevent the creation of new self-serve password reset requests until the number of active requests drops back below this number.', 'coust', 'description'),
    'string')
;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.circ.suppress_checkin_popups',
        oils_i18n_gettext(
            'ui.circ.suppress_checkin_popups', 
            'Circ: Suppress popup-dialogs during check-in.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'ui.circ.suppress_checkin_popups', 
            'Circ: Suppress popup-dialogs during check-in.', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'format.date',
        oils_i18n_gettext(
            'format.date',
            'GUI: Format Dates with this pattern.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'format.date',
            'GUI: Format Dates with this pattern (examples: "yyyy-MM-dd" for "2010-04-26", "MMM d, yyyy" for "Apr 26, 2010")', 
            'coust', 
            'description'),
        'string'
), (
        'format.time',
        oils_i18n_gettext(
            'format.time',
            'GUI: Format Times with this pattern.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'format.time',
            'GUI: Format Times with this pattern (examples: "h:m:s.SSS a z" for "2:07:20.666 PM Eastern Daylight Time", "HH:mm" for "14:07")', 
            'coust', 
            'description'),
        'string'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
        oils_i18n_gettext(
            'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
            'CAT: Delete bib if all copies are deleted via Acquisitions lineitem cancellation.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel',
            'CAT: Delete bib if all copies are deleted via Acquisitions lineitem cancellation.', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'url.remote_column_settings',
        oils_i18n_gettext(
            'url.remote_column_settings',
            'GUI: URL for remote directory containing list column settings.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'url.remote_column_settings',
            'GUI: URL for remote directory containing list column settings.  The format and naming convention for the files found in this directory match those in the local settings directory for a given workstation.  An administrator could create the desired settings locally and then copy all the tree_columns_for_* files to the remote directory.', 
            'coust', 
            'description'),
        'string'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'gui.disable_local_save_columns',
        oils_i18n_gettext(
            'gui.disable_local_save_columns',
            'GUI: Disable the ability to save list column configurations locally.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'gui.disable_local_save_columns',
            'GUI: Disable the ability to save list column configurations locally.  If set, columns may still be manipulated, however, the changes do not persist.  Also, existing local configurations are ignored if this setting is true.', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.password_reset_request_requires_matching_email',
        oils_i18n_gettext(
            'circ.password_reset_request_requires_matching_email',
            'Circulation: Require matching email address for password reset requests', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.password_reset_request_requires_matching_email',
            'Circulation: Require matching email address for password reset requests', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.holds.expired_patron_block',
        oils_i18n_gettext(
            'circ.holds.expired_patron_block',
            'Circulation: Block hold request if hold recipient privileges have expired', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'circ.holds.expired_patron_block',
            'Circulation: Block hold request if hold recipient privileges have expired', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type
    (name, label, description, datatype) VALUES (
        'circ.booking_reservation.default_elbow_room',
        oils_i18n_gettext(
            'circ.booking_reservation.default_elbow_room',
            'Booking: Elbow room',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.booking_reservation.default_elbow_room',
            'Elbow room specifies how far in the future you must make a reservation on an item if that item will have to transit to reach its pickup location.  It secondarily defines how soon a reservation on a given item must start before the check-in process will opportunistically capture it for the reservation shelf.',
            'coust',
            'label'
        ),
        'interval'
    );

-- Org_unit_setting_type(s) that need an fm_class:
INSERT into config.org_unit_setting_type
( name, label, description, datatype, fm_class ) VALUES
( 'acq.default_copy_location',
  'Default copy location',
  null,
  'link',
  'acpl' );

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.org_unit_target_weight',
    'Holds: Org Unit Target Weight',
    'Org Units can be organized into hold target groups based on a weight.  Potential copies from org units with the same weight are chosen at random.',
    'integer'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.target_holds_by_org_unit_weight',
    'Holds: Use weight-based hold targeting',
    'Use library weight based hold targeting',
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.max_org_unit_target_loops',
    'Holds: Maximum library target attempts',
    'When this value is set and greater than 0, the system will only attempt to find a copy at each possible branch the configured number of times',
    'integer'
);


-- Org setting for overriding the circ lib of a precat copy
INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.pre_cat_copy_circ_lib',
    'Pre-cat Item Circ Lib',
    'Override the default circ lib of "here" with a pre-configured circ lib for pre-cat items.  The value should be the "shortname" (aka policy name) of the org unit',
    'string'
);

-- Circ auto-renew interval setting
INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.checkout_auto_renew_age',
    'Checkout auto renew age',
    'When an item has been checked out for at least this amount of time, an attempt to check out the item to the patron that it is already checked out to will simply renew the circulation',
    'interval'
);

-- Setting for behind the desk hold pickups
INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.behind_desk_pickup_supported',
    'Holds: Behind Desk Pickup Supported',
    'If a branch supports both a public holds shelf and behind-the-desk pickups, set this value to true.  This gives the patron the option to enable behind-the-desk pickups for their holds',
    'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'acq.holds.allow_holds_from_purchase_request',
        oils_i18n_gettext(
            'acq.holds.allow_holds_from_purchase_request', 
            'Allows patrons to create automatic holds from purchase requests.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'acq.holds.allow_holds_from_purchase_request', 
            'Allows patrons to create automatic holds from purchase requests.', 
            'coust', 
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.target_skip_me',
    'Skip For Hold Targeting',
    'When true, don''t target any copies at this org unit for holds',
    'bool'
);

-- claims returned mark item missing 
INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.claim_return.mark_missing',
        'Claim Return: Mark copy as missing', 
        'When a circ is marked as claims-returned, also mark the copy as missing',
        'bool'
    );

-- claims never checked out mark item missing 
INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.claim_never_checked_out.mark_missing',
        'Claim Never Checked Out: Mark copy as missing', 
        'When a circ is marked as claims-never-checked-out, mark the copy as missing',
        'bool'
    );

-- mark damaged void overdue setting
INSERT INTO
    config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.damaged.void_ovedue',
        'Mark item damaged voids overdues',
        'When an item is marked damaged, overdue fines on the most recent circulation are voided.',
        'bool'
    );

-- hold cancel display limits
INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.canceled.display_count',
        'Holds: Canceled holds display count',
        'How many canceled holds to show in patron holds interfaces',
        'integer'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.canceled.display_age',
        'Holds: Canceled holds display age',
        'Show all canceled holds that were canceled within this amount of time',
        'interval'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.uncancel.reset_request_time',
        'Holds: Reset request time on un-cancel',
        'When a hold is uncanceled, reset the request time to push it to the end of the queue',
        'bool'
    );

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES (
        'circ.holds.default_shelf_expire_interval',
        'Default hold shelf expire interval',
        '',
        'interval'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype, fm_class)
    VALUES (
        'circ.claim_return.copy_status', 
        'Claim Return Copy Status', 
        'Claims returned copies are put into this status.  Default is to leave the copy in the Checked Out status',
        'link', 
        'ccs' 
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'circ.max_fine.cap_at_price',
        oils_i18n_gettext('circ.max_fine.cap_at_price', 'Circ: Cap Max Fine at Item Price', 'coust', 'label'),
        oils_i18n_gettext('circ.max_fine.cap_at_price', 'This prevents the system from charging more than the item price in overdue fines', 'coust', 'description'),
        'bool' 
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) 
    VALUES ( 
        'circ.holds.clear_shelf.copy_status',
        oils_i18n_gettext('circ.holds.clear_shelf.copy_status', 'Holds: Clear shelf copy status', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.clear_shelf.copy_status', 'Any copies that have not been put into reshelving, in-transit, or on-holds-shelf (for a new hold) during the clear shelf process will be put into this status.  This is basically a purgatory status for copies waiting to be pulled from the shelf and processed by hand', 'coust', 'description'),
        'link',
        'ccs'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.selfcheck.workstation_required',
        oils_i18n_gettext('circ.selfcheck.workstation_required', 'Selfcheck: Workstation Required', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.workstation_required', 'All selfcheck stations must use a workstation', 'coust', 'description'),
        'bool'
    ), (
        'circ.selfcheck.patron_password_required',
        oils_i18n_gettext('circ.selfcheck.patron_password_required', 'Selfcheck: Require Patron Password', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.patron_password_required', 'Patron must log in with barcode and password at selfcheck station', 'coust', 'description'),
        'bool'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.selfcheck.alert.sound',
        oils_i18n_gettext('circ.selfcheck.alert.sound', 'Selfcheck: Audio Alerts', 'coust', 'label'),
        oils_i18n_gettext('circ.selfcheck.alert.sound', 'Use audio alerts for selfcheck events', 'coust', 'description'),
        'bool'
    );

INSERT INTO
    config.org_unit_setting_type (name, label, description, datatype)
    VALUES (
        'notice.telephony.callfile_lines',
        'Telephony: Arbitrary line(s) to include in each notice callfile',
        $$
        This overrides lines from opensrf.xml.
        Line(s) must be valid for your target server and platform
        (e.g. Asterisk 1.4).
        $$,
        'string'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.offline.username_allowed',
        oils_i18n_gettext('circ.offline.username_allowed', 'Offline: Patron Usernames Allowed', 'coust', 'label'),
        oils_i18n_gettext('circ.offline.username_allowed', 'During offline circulations, allow patrons to identify themselves with usernames in addition to barcode.  For this setting to work, a barcode format must also be defined', 'coust', 'description'),
        'bool'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
    'acq.fund.balance_limit.warn',
    oils_i18n_gettext('acq.fund.balance_limit.warn', 'Fund Spending Limit for Warning', 'coust', 'label'),
    oils_i18n_gettext('acq.fund.balance_limit.warn', 'When the amount remaining in the fund, including spent money and encumbrances, goes below this percentage, attempts to spend from the fund will result in a warning to the staff.', 'coust', 'descripton'),
    'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
    'acq.fund.balance_limit.block',
    oils_i18n_gettext('acq.fund.balance_limit.block', 'Fund Spending Limit for Block', 'coust', 'label'),
    oils_i18n_gettext('acq.fund.balance_limit.block', 'When the amount remaining in the fund, including spent money and encumbrances, goes below this percentage, attempts to spend from the fund will be blocked.', 'coust', 'description'),
    'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.holds.hold_has_copy_at.alert',
        oils_i18n_gettext('circ.holds.hold_has_copy_at.alert', 'Holds: Has Local Copy Alert', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.hold_has_copy_at.alert', 'If there is an available copy at the requesting library that could fulfill a hold during hold placement time, alert the patron', 'coust', 'description'),
        'bool'
    ),(
        'circ.holds.hold_has_copy_at.block',
        oils_i18n_gettext('circ.holds.hold_has_copy_at.block', 'Holds: Has Local Copy Block', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.hold_has_copy_at.block', 'If there is an available copy at the requesting library that could fulfill a hold during hold placement time, do not allow the hold to be placed', 'coust', 'description'),
        'bool'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
VALUES (
    'auth.persistent_login_interval',
    oils_i18n_gettext('auth.persistent_login_interval', 'Persistent Login Duration', 'coust', 'label'),
    oils_i18n_gettext('auth.persistent_login_interval', 'How long a persistent login lasts.  E.g. ''2 weeks''', 'coust', 'description'),
    'interval'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'cat.marc_control_number_identifier',
        oils_i18n_gettext(
            'cat.marc_control_number_identifier', 
            'Cat: Defines the control number identifier used in 003 and 035 fields.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'cat.marc_control_number_identifier', 
            'Cat: Defines the control number identifier used in 003 and 035 fields.', 
            'coust', 
            'description'),
        'string'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) 
    VALUES (
        'circ.selfcheck.block_checkout_on_copy_status',
        oils_i18n_gettext(
            'circ.selfcheck.block_checkout_on_copy_status',
            'Selfcheck: Block copy checkout status',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.selfcheck.block_checkout_on_copy_status',
            'List of copy status IDs that will block checkout even if the generic COPY_NOT_AVAILABLE event is overridden',
            'coust',
            'description'
        ),
        'array'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class )
VALUES (
    'serial.prev_issuance_copy_location',
    oils_i18n_gettext(
        'serial.prev_issuance_copy_location',
        'Serials: Previous Issuance Copy Location',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'serial.prev_issuance_copy_location',
        'When a serial issuance is received, copies (units) of the previous issuance will be automatically moved into the configured shelving location',
        'coust',
        'descripton'
        ),
    'link',
    'acpl'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class )
VALUES (
    'cat.default_classification_scheme',
    oils_i18n_gettext(
        'cat.default_classification_scheme',
        'Cataloging: Default Classification Scheme',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'cat.default_classification_scheme',
        'Defines the default classification scheme for new call numbers: 1 = Generic; 2 = Dewey; 3 = LC',
        'coust',
        'descripton'
        ),
    'link',
    'acnc'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'opac.org_unit_hiding.depth',
        oils_i18n_gettext(
            'opac.org_unit_hiding.depth',
            'OPAC: Org Unit Hiding Depth', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'opac.org_unit_hiding.depth',
            'This will hide certain org units in the public OPAC if the Original Location (url param "ol") for the OPAC inherits this setting.  This setting specifies an org unit depth, that together with the OPAC Original Location determines which section of the Org Hierarchy should be visible in the OPAC.  For example, a stock Evergreen installation will have a 3-tier hierarchy (Consortium/System/Branch), where System has a depth of 1 and Branch has a depth of 2.  If this setting contains a depth of 1 in such an installation, then every library in the System in which the Original Location belongs will be visible, and everything else will be hidden.  A depth of 0 will effectively make every org visible.  The embedded OPAC in the staff client ignores this setting.', 
            'coust', 
            'description'),
        'integer'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES ( 
        'circ.holds.clear_shelf.no_capture_holds',
        oils_i18n_gettext('circ.holds.clear_shelf.no_capture_holds', 'Holds: Bypass hold capture during clear shelf process', 'coust', 'label'),
        oils_i18n_gettext('circ.holds.clear_shelf.no_capture_holds', 'During the clear shelf process, avoid capturing new holds on cleared items.', 'coust', 'description'),
        'bool'
    );

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.booking_reservation.stop_circ',
    'Disallow circulation of items when they are on booking reserve and that reserve overlaps with the checkout period',
    'When true, items on booking reserve during the proposed checkout period will not be allowed to circulate unless overridden with the COPY_RESERVED.override permission.',
    'bool'
);

---------------------------------
-- Seed data for usr_setting_type
----------------------------------

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_font', TRUE, 'OPAC Font Size', 'OPAC Font Size', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_search_depth', TRUE, 'OPAC Search Depth', 'OPAC Search Depth', 'integer');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.default_search_location', TRUE, 'OPAC Search Location', 'OPAC Search Location', 'integer');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.hits_per_page', TRUE, 'Hits per Page', 'Hits per Page', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('opac.hold_notify', TRUE, 'Hold Notification Format', 'Hold Notification Format', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('staff_client.catalog.record_view.default', TRUE, 'Default Record View', 'Default Record View', 'string');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('staff_client.copy_editor.templates', TRUE, 'Copy Editor Template', 'Copy Editor Template', 'object');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES ('circ.holds_behind_desk', FALSE, 'Hold is behind Circ Desk', 'Hold is behind Circ Desk', 'bool');

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES (
        'history.circ.retention_age',
        TRUE,
        oils_i18n_gettext('history.circ.retention_age','Historical Circulation Retention Age','cust','label'),
        oils_i18n_gettext('history.circ.retention_age','Historical Circulation Retention Age','cust','description'),
        'interval'
    ),(
        'history.circ.retention_start',
        FALSE,
        oils_i18n_gettext('history.circ.retention_start','Historical Circulation Retention Start Date','cust','label'),
        oils_i18n_gettext('history.circ.retention_start','Historical Circulation Retention Start Date','cust','description'),
        'date'
    );

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES (
        'history.hold.retention_age',
        TRUE,
        oils_i18n_gettext('history.hold.retention_age','Historical Hold Retention Age','cust','label'),
        oils_i18n_gettext('history.hold.retention_age','Historical Hold Retention Age','cust','description'),
        'interval'
    ),(
        'history.hold.retention_start',
        TRUE,
        oils_i18n_gettext('history.hold.retention_start','Historical Hold Retention Start Date','cust','label'),
        oils_i18n_gettext('history.hold.retention_start','Historical Hold Retention Start Date','cust','description'),
        'interval'
    ),(
        'history.hold.retention_count',
        TRUE,
        oils_i18n_gettext('history.hold.retention_count','Historical Hold Retention Count','cust','label'),
        oils_i18n_gettext('history.hold.retention_count','Historical Hold Retention Count','cust','description'),
        'integer'
    );

INSERT INTO config.usr_setting_type (name, opac_visible, label, description, datatype)
    VALUES (
        'opac.default_sort',
        TRUE,
        oils_i18n_gettext(
            'opac.default_sort',
            'OPAC Default Search Sort',
            'cust',
            'label'
        ),
        oils_i18n_gettext(
            'opac.default_sort',
            'OPAC Default Search Sort',
            'cust',
            'description'
        ),
        'string'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) VALUES (
        'circ.missing_pieces.copy_status',
        oils_i18n_gettext(
            'circ.missing_pieces.copy_status',
            'Circulation: Item Status for Missing Pieces',
            'coust',
            'label'),
        oils_i18n_gettext(
            'circ.missing_pieces.copy_status',
            'This is the Item Status to use for items that have been marked or scanned as having Missing Pieces.  In the absence of this setting, the Damaged status is used.',
            'coust',
            'description'),
        'link',
        'ccs'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.do_not_tally_claims_returned',
        oils_i18n_gettext(
            'circ.do_not_tally_claims_returned',
            'Circulation: Do not include outstanding Claims Returned circulations in lump sum tallies in Patron Display.',
            'coust',
            'label'),
        oils_i18n_gettext(
            'circ.do_not_tally_claims_returned',
            'In the Patron Display interface, the number of total active circulations for a given patron is presented in the Summary sidebar and underneath the Items Out navigation button.  This setting will prevent Claims Returned circulations from counting toward these tallies.',
            'coust',
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('cat.label.font.size',
            oils_i18n_gettext('cat.label.font.size',
                'Cataloging: Spine and pocket label font size', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.size',
                'Set the default font size for spine and pocket labels', 'coust', 'description'),
            'integer'
        )
        ,('cat.label.font.family',
            oils_i18n_gettext('cat.label.font.family',
                'Cataloging: Spine and pocket label font family', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.family',
                'Set the preferred font family for spine and pocket labels. You can specify a list of fonts, separated by commas, in order of preference; the system will use the first font it finds with a matching name. For example, "Arial, Helvetica, serif".',
                'coust', 'description'),
            'string'
        )
        ,('cat.spine.line.width',
            oils_i18n_gettext('cat.spine.line.width',
                'Cataloging: Spine label line width', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.width',
                'Set the default line width for spine labels in number of characters. This specifies the boundary at which lines must be wrapped.',
                'coust', 'description'),
            'integer'
        )
        ,('cat.spine.line.height',
            oils_i18n_gettext('cat.spine.line.height',
                'Cataloging: Spine label maximum lines', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.height',
                'Set the default maximum number of lines for spine labels.',
                'coust', 'description'),
            'integer'
        )
        ,('cat.spine.line.margin',
            oils_i18n_gettext('cat.spine.line.margin',
                'Cataloging: Spine label left margin', 'coust', 'label'),
            oils_i18n_gettext('cat.spine.line.margin',
                'Set the left margin for spine labels in number of characters.',
                'coust', 'description'),
            'integer'
        )
;

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('cat.label.font.weight',
            oils_i18n_gettext('cat.label.font.weight',
                'Cataloging: Spine and pocket label font weight', 'coust', 'label'),
            oils_i18n_gettext('cat.label.font.weight',
                'Set the preferred font weight for spine and pocket labels. You can specify "normal", "bold", "bolder", or "lighter".',
                'coust', 'description'),
            'string'
        )
;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.patron_edit.clone.copy_address',
        oils_i18n_gettext(
            'circ.patron_edit.clone.copy_address',
            'Patron Registration: Cloned patrons get address copy',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.patron_edit.clone.copy_address',
            'In the Patron editor, copy addresses from the cloned user instead of linking directly to the address',
            'coust',
            'description'
        ),
        'bool'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, fm_class ) VALUES (
        'ui.patron.default_ident_type',
        oils_i18n_gettext(
            'ui.patron.default_ident_type',
            'GUI: Default Ident Type for Patron Registration',
            'coust',
            'label'),
        oils_i18n_gettext(
            'ui.patron.default_ident_type',
            'This is the default Ident Type for new users in the patron editor.',
            'coust',
            'description'),
        'link',
        'cit'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.patron.default_country',
        oils_i18n_gettext(
            'ui.patron.default_country',
            'GUI: Default Country for New Addresses in Patron Editor',
            'coust',
            'label'),
        oils_i18n_gettext(
            'ui.patron.default_country',
            'This is the default Country for new addresses in the patron editor.',
            'coust',
            'description'),
        'string'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'ui.patron.registration.require_address',
        oils_i18n_gettext(
            'ui.patron.registration.require_address',
            'GUI: Require at least one address for Patron Registration',
            'coust',
            'label'),
        oils_i18n_gettext(
            'ui.patron.registration.require_address',
            'Enforces a requirement for having at least one address for a patron during registration.',
            'coust',
            'description'),
        'bool'
);

INSERT INTO config.org_unit_setting_type (
    name, label, description, datatype
) VALUES
    ('credit.processor.payflowpro.enabled',
        'Credit card processing: Enable PayflowPro payments',
        'This is NOT the same thing as the settings labeled with just "PayPal."',
        'bool'
    ),
    ('credit.processor.payflowpro.login',
        'Credit card processing: PayflowPro login/merchant ID',
        'Often the same thing as the PayPal manager login',
        'string'
    ),
    ('credit.processor.payflowpro.password',
        'Credit card processing: PayflowPro password',
        'PayflowPro password',
        'string'
    ),
    ('credit.processor.payflowpro.testmode',
        'Credit card processing: PayflowPro test mode',
        'Do not really process transactions, but stay in test mode - uses pilot-payflowpro.paypal.com instead of the usual host',
        'bool'
    ),
    ('credit.processor.payflowpro.vendor',
        'Credit card processing: PayflowPro vendor',
        'Often the same thing as the login',
        'string'
    ),
    ('credit.processor.payflowpro.partner',
        'Credit card processing: PayflowPro partner',
        'Often "PayPal" or "VeriSign", sometimes others',
        'string'
    );

-- Patch the name of an old selfcheck setting
UPDATE actor.org_unit_setting
    SET name = 'circ.selfcheck.alert.popup'
    WHERE name = 'circ.selfcheck.alert_on_checkout_event';

-- Rename certain existing org_unit settings, if present,
-- and make sure their values are JSON
UPDATE actor.org_unit_setting SET
    name = 'circ.holds.default_estimated_wait_interval',
    --
    -- The value column should be JSON.  The old value should be a number,
    -- but it may or may not be quoted.  The following CASE behaves
    -- differently depending on whether value is quoted.  It is simplistic,
    -- and will be defeated by leading or trailing white space, or various
    -- malformations.
    --
    value = CASE WHEN SUBSTR( value, 1, 1 ) = '"'
                THEN '"' || SUBSTR( value, 2, LENGTH(value) - 2 ) || ' days"'
                ELSE '"' || value || ' days"'
            END
WHERE name = 'circ.hold_estimate_wait_interval';

-- Create types for existing org unit settings
-- not otherwise accounted for

INSERT INTO config.org_unit_setting_type(
 name,
 label,
 description
)
SELECT DISTINCT
	name,
	name,
	'FIXME'
FROM
	actor.org_unit_setting
WHERE
	name NOT IN (
		SELECT name
		FROM config.org_unit_setting_type
	);

-- Add foreign key to org_unit_setting

ALTER TABLE actor.org_unit_setting
	ADD FOREIGN KEY (name) REFERENCES config.org_unit_setting_type (name)
		DEFERRABLE INITIALLY DEFERRED;

-- Create types for existing user settings
-- not otherwise accounted for

INSERT INTO config.usr_setting_type (
	name,
	label,
	description
)
SELECT DISTINCT
	name,
	name,
	'FIXME'
FROM
	actor.usr_setting
WHERE
	name NOT IN (
		SELECT name
		FROM config.usr_setting_type
	);

-- Add foreign key to user_setting_type

ALTER TABLE actor.usr_setting
	ADD FOREIGN KEY (name) REFERENCES config.usr_setting_type (name)
		ON DELETE CASCADE ON UPDATE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES
    (1, 'cat.spine.line.margin', 0)
    ,(1, 'cat.spine.line.height', 9)
    ,(1, 'cat.spine.line.width', 8)
    ,(1, 'cat.label.font.family', '"monospace"')
    ,(1, 'cat.label.font.size', 10)
    ,(1, 'cat.label.font.weight', '"normal"')
;

ALTER TABLE action_trigger.event_definition ADD COLUMN granularity TEXT;
ALTER TABLE action_trigger.event ADD COLUMN async_output BIGINT REFERENCES action_trigger.event_output (id);
ALTER TABLE action_trigger.event_definition ADD COLUMN usr_field TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN opt_in_setting TEXT REFERENCES config.usr_setting_type (name) DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION is_json( TEXT ) RETURNS BOOL AS $f$
    use JSON::XS;
    my $json = shift();
    eval { JSON::XS->new->allow_nonref->decode( $json ) };
    return $@ ? 0 : 1;
$f$ LANGUAGE PLPERLU;

ALTER TABLE action_trigger.event ADD COLUMN user_data TEXT CHECK (user_data IS NULL OR is_json( user_data ));

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.expire_no_target',
    'ahr',
    'A hold is cancelled because no copies were found'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.expire_holds_shelf',
    'ahr',
    'A hold is cancelled because it was on the holds shelf too long'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.staff',
    'ahr',
    'A hold is cancelled because it was cancelled by staff'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'hold_request.cancel.patron',
    'ahr',
    'A hold is cancelled by the patron'
);

-- Fix typos in descriptions
UPDATE action_trigger.hook SET description = 'A hold is successfully placed' WHERE key = 'hold_request.success';
UPDATE action_trigger.hook SET description = 'A hold is attempted but not successfully placed' WHERE key = 'hold_request.failure';

-- Add a hook for renewals
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('renewal','circ','Item renewed to user');

INSERT INTO action_trigger.validator (module,description) VALUES ('MaxPassiveDelayAge','Check that the event is not too far past the delay_field time -- requires a max_delay_age interval parameter');

-- Sample Pre-due Notice --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template) 
    VALUES (6, 'f', 1, '3 Day Courtesy Notice', 'checkout.due', 'CircIsOpen', 'SendEmail', '-3 days', 'due_date', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Courtesy Notice

Dear [% user.family_name %], [% user.first_given_name %]
As a reminder, the following items are due in 3 days.

[% FOR circ IN target %]
    Title: [% circ.target_copy.call_number.record.simple_record.title %] 
    Barcode: [% circ.target_copy.barcode %] 
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Item Cost: [% helpers.get_copy_price(circ.target_copy) %]
    Library: [% circ.circ_lib.name %]
    Library Phone: [% circ.circ_lib.phone %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (6, 'target_copy.call_number.record.simple_record'),
    (6, 'usr'),
    (6, 'circ_lib.billing_address');

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
    (6, 'max_delay_age', '"1 day"');

-- also add the max delay age to the default overdue notice event def
INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
    (1, 'max_delay_age', '"1 day"');
  
INSERT INTO action_trigger.validator (module,description) VALUES ('MinPassiveTargetAge','Check that the target is old enough to be used by this event -- requires a min_target_age interval parameter, and accepts an optional target_age_field to specify what time to use for offsetting');

INSERT INTO action_trigger.reactor (module,description) VALUES ('ApplyPatronPenalty','Applies the configured penalty to a patron.  Required named environment variables are "user", which refers to the user object, and "context_org", which refers to the org_unit object that acts as the focus for the penalty.');

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'hold_request.shelf_expires_soon',
        'ahr',
        'A hold on the shelf will expire there soon.',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        delay,
        delay_field,
        group_field,
        template
    ) VALUES (
        7,
        FALSE,
        1,
        'Hold Expires from Shelf Soon',
        'hold_request.shelf_expires_soon',
        'HoldIsAvailable',
        'SendEmail',
        '- 1 DAY',
        'shelf_expire_time',
        'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Available Notification

Dear [% user.family_name %], [% user.first_given_name %]
You requested holds on the following item(s), which are available for
pickup, but these holds will soon expire.

[% FOR hold IN target %]
    [%- data = helpers.get_copy_bib_basics(hold.current_copy.id) -%]
    Title: [% data.title %]
    Author: [% data.author %]
    Library: [% hold.pickup_lib.name %]
[% END %]
$$
    );

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
    ( 7, 'current_copy'),
    ( 7, 'pickup_lib.billing_address'),
    ( 7, 'usr');

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'hold_request.long_wait',
        'ahr',
        'A patron has been waiting on a hold to be fulfilled for a long time.',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        delay,
        delay_field,
        group_field,
        template
    ) VALUES (
        9,
        FALSE,
        1,
        'Hold waiting for pickup for long time',
        'hold_request.long_wait',
        'NOOP_True',
        'SendEmail',
        '6 MONTHS',
        'request_time',
        'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Long Wait Hold Notification

Dear [% user.family_name %], [% user.first_given_name %]

You requested hold(s) on the following item(s), but unfortunately
we have not been able to fulfill your request after a considerable
length of time.  If you would still like to receive these items,
no action is required.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
[% END %]
$$
);

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
    (9, 'pickup_lib'),
    (9, 'usr'),
    (9, 'bib_rec.bib_record.simple_record');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.checkout',
        'circ',
        'Formats circ objects for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        10,
        TRUE,
        1,
        'Self-Checkout Receipt',
        'format.selfcheck.checkout',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
[%- SET lib = target.0.circ_lib -%]
[%- SET lib_addr = target.0.circ_lib.billing_address -%]
[%- SET hours = lib.hours_of_operation -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <div>[% lib.name %]</div>
    <div>[% lib_addr.street1 %] [% lib_addr.street2 %]</div>
    <div>[% lib_addr.city %], [% lib_addr.state %] [% lb_addr.post_code %]</div>
    <div>[% lib.phone %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        [%-
            SET idx = loop.count - 1;
            SET udata =  user_data.$idx
        -%]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            [% IF udata.renewal_failure %]
                <div style='color:red;'>Renewal Failed</div>
            [% ELSE %]
                <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            [% END %]
        </li>
    [% END %]
    </ol>
    
    <div>
        Library Hours
        [%- BLOCK format_time; date.format(time _ ' 1/1/1000', format='%I:%M %p'); END -%]
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
$$
);

INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 10, 'target_copy'),
    ( 10, 'circ_lib.billing_address'),
    ( 10, 'circ_lib.hours_of_operation'),
    ( 10, 'usr');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.items_out',
        'circ',
        'Formats items out for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        11,
        TRUE,
        1,
        'Self-Checkout Items Out Receipt',
        'format.selfcheck.items_out',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$
);


INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 11, 'target_copy'),
    ( 11, 'circ_lib.billing_address'),
    ( 11, 'circ_lib.hours_of_operation'),
    ( 11, 'usr');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.holds',
        'ahr',
        'Formats holds for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        12,
        TRUE,
        1,
        'Self-Checkout Holds Receipt',
        'format.selfcheck.holds',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR hold IN target %]
        [%-
            SET idx = loop.count - 1;
            SET udata =  user_data.$idx
        -%]
        <li>
            <div>Title: [% hold.bib_rec.bib_record.simple_record.title %]</div>
            <div>Author: [% hold.bib_rec.bib_record.simple_record.author %]</div>
            <div>Pickup Location: [% hold.pickup_lib.name %]</div>
            <div>Status: 
                [%- IF udata.ready -%]
                    Ready for pickup
                [% ELSE %]
                    #[% udata.queue_position %] of [% udata.potential_copies %] copies.
                [% END %]
            </div>
        </li>
    [% END %]
    </ol>
</div>
$$
);


INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 12, 'bib_rec.bib_record.simple_record'),
    ( 12, 'pickup_lib'),
    ( 12, 'usr');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.fines',
        'au',
        'Formats fines for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, granularity, template )
    VALUES (
        13,
        TRUE,
        1,
        'Self-Checkout Fines Receipt',
        'format.selfcheck.fines',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR xact IN user.open_billable_transactions_summary %]
        <li>
            <div>Details: 
                [% IF xact.xact_type == 'circulation' %]
                    [%- helpers.get_copy_bib_basics(xact.circulation.target_copy).title -%]
                [% ELSE %]
                    [%- xact.last_billing_type -%]
                [% END %]
            </div>
            <div>Total Billed: [% xact.total_owed %]</div>
            <div>Total Paid: [% xact.total_paid %]</div>
            <div>Balance Owed : [% xact.balance_owed %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$
);

INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 13, 'open_billable_transactions_summary.circulation' );

INSERT INTO action_trigger.reactor (module,description) VALUES
(   'SendFile',
    oils_i18n_gettext(
        'SendFile',
        'Build and transfer a file to a remote server.  Required parameter "remote_host" specifying target server.  Optional parameters: remote_user, remote_password, remote_account, port, type (FTP, SFTP or SCP), and debug.',
        'atreact',
        'description'
    )
);

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.acqli.html',
        'jub',
        'Formats lineitem worksheet for titles received',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, granularity, template)
    VALUES (
        14,
        TRUE,
        1,
        'Lineitem Worksheet',
        'format.acqli.html',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET li = target; -%]
<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>

        <div>Title: [% helpers.get_li_attr("title", "", li.attributes) %]</div>
        <div>Author: [% helpers.get_li_attr("author", "", li.attributes) %]</div>
        <div class="count">Item Count: [% li.lineitem_details.size %]</div>
        <div class="lineid">Lineitem ID: [% li.id %]</div>

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
                <th>Recd.</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
        [% FOREACH detail IN li.lineitem_details.sort('owning_lib') %]
            [% 
                IF copy.eg_copy_id;
                    SET copy = copy.eg_copy_id;
                    SET cn_label = copy.call_number.label;
                ELSE; 
                    SET copy = detail; 
                    SET cn_label = detail.cn_label;
                END 
            %]
            <tr>
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td style='padding:5px;'>[% detail.owning_lib.shortname %]</td>
                <td style='padding:5px;'>[% IF copy.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF cn_label %]<span class="cn_label" >[% cn_label  %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.fund %]<span class="fund">[% detail.fund.code %] ([% detail.fund.year %])</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% detail.recv_time %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$$
);


INSERT INTO action_trigger.environment (event_def, path) VALUES
    ( 14, 'attributes' ),
    ( 14, 'lineitem_details' ),
    ( 14, 'lineitem_details.owning_lib' ),
    ( 14, 'lineitem_notes' )
;

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'aur.ordered',
        'aur', 
        oils_i18n_gettext(
            'aur.ordered',
            'A patron acquisition request has been marked On-Order.',
            'ath',
            'description'
        ), 
        TRUE
    ), (
        'aur.received', 
        'aur', 
        oils_i18n_gettext(
            'aur.received', 
            'A patron acquisition request has been marked Received.',
            'ath',
            'description'
        ),
        TRUE
    ), (
        'aur.cancelled',
        'aur',
        oils_i18n_gettext(
            'aur.cancelled',
            'A patron acquisition request has been marked Cancelled.',
            'ath',
            'description'
        ),
        TRUE
    )
;

INSERT INTO action_trigger.validator (module,description) VALUES (
        'Acq::UserRequestOrdered',
        oils_i18n_gettext(
            'Acq::UserRequestOrdered',
            'Tests to see if the corresponding Line Item has a state of "on-order".',
            'atval',
            'description'
        )
    ), (
        'Acq::UserRequestReceived',
        oils_i18n_gettext(
            'Acq::UserRequestReceived',
            'Tests to see if the corresponding Line Item has a state of "received".',
            'atval',
            'description'
        )
    ), (
        'Acq::UserRequestCancelled',
        oils_i18n_gettext(
            'Acq::UserRequestCancelled',
            'Tests to see if the corresponding Line Item has a state of "cancelled".',
            'atval',
            'description'
        )
    )
;

-- What was event_definition #15 in v1.6.1 will be recreated as #20.  This
-- renumbering requires some juggling:
--
-- 1. Update any child rows to point to #20.  These updates will temporarily
-- violate foreign key constraints, but that's okay as long as we create
-- #20 before committing.
--
-- 2. Delete the old #15.
--
-- 3. Insert the new #15.
--
-- 4. Insert #20.
--
-- We could combine steps 2 and 3 into a single update, but that would create
-- additional opportunities for typos, since we already have the insert from
-- an upgrade script.

UPDATE action_trigger.environment
SET event_def = 20
WHERE event_def = 15;

UPDATE action_trigger.event
SET event_def = 20
WHERE event_def = 15;

UPDATE action_trigger.event_params
SET event_def = 20
WHERE event_def = 15;

DELETE FROM action_trigger.event_definition
WHERE id = 15;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        template
    ) VALUES (
        15,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked On-Order.',
        'aur.ordered',
        'Acq::UserRequestOrdered',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) -%]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) -%]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) -%]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) -%]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been placed on order.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    ), (
        16,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked Received.',
        'aur.received',
        'Acq::UserRequestReceived',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) %]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) %]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) %]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) %]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the materials for the following acquisition request have been received.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    ), (
        17,
        FALSE,
        1,
        'Email Notice: Patron Acquisition Request marked Cancelled.',
        'aur.cancelled',
        'Acq::UserRequestCancelled',
        'SendEmail',
$$
[%- USE date -%]
[%- SET li = target.lineitem; -%]
[%- SET user = target.usr -%]
[%- SET title = helpers.get_li_attr("title", "", li.attributes) %]
[%- SET author = helpers.get_li_attr("author", "", li.attributes) %]
[%- SET edition = helpers.get_li_attr("edition", "", li.attributes) %]
[%- SET isbn = helpers.get_li_attr("isbn", "", li.attributes) %]
[%- SET publisher = helpers.get_li_attr("publisher", "", li.attributes) -%]
[%- SET pubdate = helpers.get_li_attr("pubdate", "", li.attributes) -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been cancelled.

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
Lineitem ID: [% li.id %]
$$
    );

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
        ( 15, 'lineitem' ),
        ( 15, 'lineitem.attributes' ),
        ( 15, 'usr' ),

        ( 16, 'lineitem' ),
        ( 16, 'lineitem.attributes' ),
        ( 16, 'usr' ),

        ( 17, 'lineitem' ),
        ( 17, 'lineitem.attributes' ),
        ( 17, 'usr' )
    ;

INSERT INTO action_trigger.event_definition
(id, active, owner, name, hook, validator, reactor, cleanup_success, cleanup_failure, delay, delay_field, group_field, template) VALUES
(23, true, 1, 'PO JEDI', 'acqpo.activated', 'Acq::PurchaseOrderEDIRequired', 'GeneratePurchaseOrderJEDI', NULL, NULL, '00:05:00', NULL, NULL,
$$
[%- USE date -%]
[%# start JEDI document 
  # Vendor specific kludges:
  # BT      - vendcode goes to NAD/BY *suffix*  w/ 91 qualifier
  # INGRAM  - vendcode goes to NAD/BY *segment* w/ 91 qualifier (separately)
  # BRODART - vendcode goes to FTX segment (lineitem level)
-%]
[%- 
IF target.provider.edi_default.vendcode && target.provider.code == 'BRODART';
    xtra_ftx = target.provider.edi_default.vendcode;
END;
-%]
[%- BLOCK big_block -%]
{
   "recipient":"[% target.provider.san %]",
   "sender":"[% target.ordering_agency.mailing_address.san %]",
   "body": [{
     "ORDERS":[ "order", {
        "po_number":[% target.id %],
        "date":"[% date.format(date.now, '%Y%m%d') %]",
        "buyer":[
            [%   IF   target.provider.edi_default.vendcode && (target.provider.code == 'BT' || target.provider.name.match('(?i)^BAKER & TAYLOR'))  -%]
                {"id-qualifier": 91, "id":"[% target.ordering_agency.mailing_address.san _ ' ' _ target.provider.edi_default.vendcode %]"}
            [%- ELSIF target.provider.edi_default.vendcode && target.provider.code == 'INGRAM' -%]
                {"id":"[% target.ordering_agency.mailing_address.san %]"},
                {"id-qualifier": 91, "id":"[% target.provider.edi_default.vendcode %]"}
            [%- ELSE -%]
                {"id":"[% target.ordering_agency.mailing_address.san %]"}
            [%- END -%]
        ],
        "vendor":[
            [%- # target.provider.name (target.provider.id) -%]
            "[% target.provider.san %]",
            {"id-qualifier": 92, "id":"[% target.provider.id %]"}
        ],
        "currency":"[% target.provider.currency_type %]",
                
        "items":[
        [%- FOR li IN target.lineitems %]
        {
            "line_index":"[% li.id %]",
            "identifiers":[   [%-# li.isbns = helpers.get_li_isbns(li.attributes) %]
            [% FOR isbn IN helpers.get_li_isbns(li.attributes) -%]
                [% IF isbn.length == 13 -%]
                {"id-qualifier":"EN","id":"[% isbn %]"},
                [% ELSE -%]
                {"id-qualifier":"IB","id":"[% isbn %]"},
                [%- END %]
            [% END %]
                {"id-qualifier":"IN","id":"[% li.id %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr('title',     '', li.attributes) %]"},
                {"BPU":"[% helpers.get_li_attr('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr('pubdate',   '', li.attributes) %]"},
                {"BPH":"[% helpers.get_li_attr('pagination','', li.attributes) %]"}
            ],
            [%- ftx_vals = []; 
                FOR note IN li.lineitem_notes; 
                    NEXT UNLESS note.vendor_public == 't'; 
                    ftx_vals.push(note.value); 
                END; 
                IF xtra_ftx;           ftx_vals.unshift(xtra_ftx); END; 
                IF ftx_vals.size == 0; ftx_vals.unshift('');       END;  # BT needs FTX+LIN for every LI, even if it is an empty one
            -%]

            "free-text":[ 
                [% FOR note IN ftx_vals -%] "[% note %]"[% UNLESS loop.last %], [% END %][% END %] 
            ],            
            "quantity":[% li.lineitem_details.size %]
        }[% UNLESS loop.last %],[% END %]
        [%-# TODO: lineitem details (later) -%]
        [% END %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [%# close ORDERS array %]
   }]    [%# close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
  (23, 'lineitems.attributes'), 
  (23, 'lineitems.lineitem_details'), 
  (23, 'lineitems.lineitem_notes'), 
  (23, 'ordering_agency.mailing_address'), 
  (23, 'provider');

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
    [% isbn = PROCESS get_li_attr attr_name = 'isbn' %]
    [% ident = PROCESS get_li_attr attr_name = 'identifier' %]

    <td>[% target.id %]</td>
    <td>[% isbn || ident %]</td>
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
WHERE id = 4;

INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (4, 'lineitems.lineitem_notes'),
    (4, 'notes');

INSERT INTO action_trigger.environment (event_def, path) VALUES
    ( 14, 'lineitem_notes.alert_text' ),
    ( 14, 'distribution_formulas.formula' ),
    ( 14, 'lineitem_details.fund' ),
    ( 14, 'lineitem_details.eg_copy_id' ),
    ( 14, 'lineitem_details.eg_copy_id.call_number' )
;

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'aur.created',
        'aur',
        oils_i18n_gettext(
            'aur.created',
            'A patron has made an acquisitions request.',
            'ath',
            'description'
        ),
        TRUE
    ), (
        'aur.rejected',
        'aur',
        oils_i18n_gettext(
            'aur.rejected',
            'A patron acquisition request has been rejected.',
            'ath',
            'description'
        ),
        TRUE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        template
    ) VALUES (
        18,
        FALSE,
        1,
        'Email Notice: Acquisition Request created.',
        'aur.created',
        'NOOP_True',
        'SendEmail',
$$
[%- USE date -%]
[%- SET user = target.usr -%]
[%- SET title = target.title -%]
[%- SET author = target.author -%]
[%- SET isxn = target.isxn -%]
[%- SET publisher = target.publisher -%]
[%- SET pubdate = target.pubdate -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate that you have made the following acquisition request:

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISXN: [% isxn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
$$
    ), (
        19,
        FALSE,
        1,
        'Email Notice: Acquisition Request Rejected.',
        'aur.rejected',
        'NOOP_True',
        'SendEmail',
$$
[%- USE date -%]
[%- SET user = target.usr -%]
[%- SET title = target.title -%]
[%- SET author = target.author -%]
[%- SET isxn = target.isxn -%]
[%- SET publisher = target.publisher -%]
[%- SET pubdate = target.pubdate -%]
[%- SET cancel_reason = target.cancel_reason.description -%]

To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Acquisition Request Notification

Dear [% user.family_name %], [% user.first_given_name %]
Our records indicate the following acquisition request has been rejected for this reason: [% cancel_reason %]

Title: [% title %]
[% IF author %]Author: [% author %][% END %]
[% IF edition %]Edition: [% edition %][% END %]
[% IF isbn %]ISBN: [% isbn %][% END %]
[% IF publisher %]Publisher: [% publisher %][% END %]
[% IF pubdate %]Publication Date: [% pubdate %][% END %]
$$
    );

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
        ( 18, 'usr' ),
        ( 19, 'usr' ),
        ( 19, 'cancel_reason' )
    ;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES (
        'format.acqcle.html',
        'acqcle',
        'Formats claim events into a voucher',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id, active, owner, name, hook, group_field,
        validator, reactor, granularity, template
    ) VALUES (
        21,
        TRUE,
        1,
        'Claim Voucher',
        'format.acqcle.html',
        'claim',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET claim = target.0.claim -%]
<!-- This will need refined/prettified. -->
<div class="acq-claim-voucher">
    <h2>Claim: [% claim.id %] ([% claim.type.code %])</h2>
    <h3>Against: [%- helpers.get_li_attr("title", "", claim.lineitem_detail.lineitem.attributes) -%]</h3>
    <ul>
        [% FOR event IN target %]
        <li>
            Event type: [% event.type.code %]
            [% IF event.type.library_initiated %](Library initiated)[% END %]
            <br />
            Event date: [% event.event_date %]<br />
            Order date: [% event.claim.lineitem_detail.lineitem.purchase_order.order_date %]<br />
            Expected receive date: [% event.claim.lineitem_detail.lineitem.expected_recv_time %]<br />
            Initiated by: [% event.creator.family_name %], [% event.creator.first_given_name %] [% event.creator.second_given_name %]<br />
            Barcode: [% event.claim.lineitem_detail.barcode %]; Fund:
            [% event.claim.lineitem_detail.fund.code %]
            ([% event.claim.lineitem_detail.fund.year %])
        </li>
        [% END %]
    </ul>
</div>
$$
);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (21, 'claim'),
    (21, 'claim.type'),
    (21, 'claim.lineitem_detail'),
    (21, 'claim.lineitem_detail.fund'),
    (21, 'claim.lineitem_detail.lineitem.attributes'),
    (21, 'claim.lineitem_detail.lineitem.purchase_order'),
    (21, 'creator'),
    (21, 'type')
;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES (
        'format.acqinv.html',
        'acqinv',
        'Formats invoices into a voucher',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id, active, owner, name, hook,
        validator, reactor, granularity, template
    ) VALUES (
        22,
        TRUE,
        1,
        'Invoice',
        'format.acqinv.html',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[% FILTER collapse %]
[%- SET invoice = target -%]
<!-- This lacks totals, info about funds (for invoice entries,
    funds are per-LID!), and general refinement -->
<div class="acq-invoice-voucher">
    <h1>Invoice</h1>
    <div>
        <strong>No.</strong> [% invoice.inv_ident %]
        [% IF invoice.inv_type %]
            / <strong>Type:</strong>[% invoice.inv_type %]
        [% END %]
    </div>
    <div>
        <dl>
            [% BLOCK ent_with_address %]
            <dt>[% ent_label %]: [% ent.name %] ([% ent.code %])</dt>
            <dd>
                [% IF ent.addresses.0 %]
                    [% SET addr = ent.addresses.0 %]
                    [% addr.street1 %]<br />
                    [% IF addr.street2 %][% addr.street2 %]<br />[% END %]
                    [% addr.city %],
                    [% IF addr.county %] [% addr.county %], [% END %]
                    [% IF addr.state %] [% addr.state %] [% END %]
                    [% IF addr.post_code %][% addr.post_code %][% END %]<br />
                    [% IF addr.country %] [% addr.country %] [% END %]
                [% END %]
                <p>
                    [% IF ent.phone %] Phone: [% ent.phone %]<br />[% END %]
                    [% IF ent.fax_phone %] Fax: [% ent.fax_phone %]<br />[% END %]
                    [% IF ent.url %] URL: [% ent.url %]<br />[% END %]
                    [% IF ent.email %] E-mail: [% ent.email %] [% END %]
                </p>
            </dd>
            [% END %]
            [% INCLUDE ent_with_address
                ent = invoice.provider
                ent_label = "Provider" %]
            [% INCLUDE ent_with_address
                ent = invoice.shipper
                ent_label = "Shipper" %]
            <dt>Receiver</dt>
            <dd>
                [% invoice.receiver.name %] ([% invoice.receiver.shortname %])
            </dd>
            <dt>Received</dt>
            <dd>
                [% helpers.format_date(invoice.recv_date) %] by
                [% invoice.recv_method %]
            </dd>
            [% IF invoice.note %]
                <dt>Note</dt>
                <dd>
                    [% invoice.note %]
                </dd>
            [% END %]
        </dl>
    </div>
    <ul>
        [% FOR entry IN invoice.entries %]
            <li>
                [% IF entry.lineitem %]
                    Title: [% helpers.get_li_attr(
                        "title", "", entry.lineitem.attributes
                    ) %]<br />
                    Author: [% helpers.get_li_attr(
                        "author", "", entry.lineitem.attributes
                    ) %]
                [% END %]
                [% IF entry.purchase_order %]
                    (PO: [% entry.purchase_order.name %])
                [% END %]<br />
                Invoice item count: [% entry.inv_item_count %]
                [% IF entry.phys_item_count %]
                    / Physical item count: [% entry.phys_item_count %]
                [% END %]
                <br />
                [% IF entry.cost_billed %]
                    Cost billed: [% entry.cost_billed %]
                    [% IF entry.billed_per_item %](per item)[% END %]
                    <br />
                [% END %]
                [% IF entry.actual_cost %]
                    Actual cost: [% entry.actual_cost %]<br />
                [% END %]
                [% IF entry.amount_paid %]
                    Amount paid: [% entry.amount_paid %]<br />
                [% END %]
                [% IF entry.note %]Note: [% entry.note %][% END %]
            </li>
        [% END %]
        [% FOR item IN invoice.items %]
            <li>
                [% IF item.inv_item_type %]
                    Item Type: [% item.inv_item_type %]<br />
                [% END %]
                [% IF item.title %]Title/Description:
                    [% item.title %]<br />
                [% END %]
                [% IF item.author %]Author: [% item.author %]<br />[% END %]
                [% IF item.purchase_order %]PO: [% item.purchase_order %]<br />[% END %]
                [% IF item.note %]Note: [% item.note %]<br />[% END %]
                [% IF item.cost_billed %]
                    Cost billed: [% item.cost_billed %]<br />
                [% END %]
                [% IF item.actual_cost %]
                    Actual cost: [% item.actual_cost %]<br />
                [% END %]
                [% IF item.amount_paid %]
                    Amount paid: [% item.amount_paid %]<br />
                [% END %]
            </li>
        [% END %]
    </ul>
</div>
[% END %]
$$
);

UPDATE action_trigger.event_definition SET template = $$[% FILTER collapse %]
[%- SET invoice = target -%]
<!-- This lacks general refinement -->
<div class="acq-invoice-voucher">
    <h1>Invoice</h1>
    <div>
        <strong>No.</strong> [% invoice.inv_ident %]
        [% IF invoice.inv_type %]
            / <strong>Type:</strong>[% invoice.inv_type %]
        [% END %]
    </div>
    <div>
        <dl>
            [% BLOCK ent_with_address %]
            <dt>[% ent_label %]: [% ent.name %] ([% ent.code %])</dt>
            <dd>
                [% IF ent.addresses.0 %]
                    [% SET addr = ent.addresses.0 %]
                    [% addr.street1 %]<br />
                    [% IF addr.street2 %][% addr.street2 %]<br />[% END %]
                    [% addr.city %],
                    [% IF addr.county %] [% addr.county %], [% END %]
                    [% IF addr.state %] [% addr.state %] [% END %]
                    [% IF addr.post_code %][% addr.post_code %][% END %]<br />
                    [% IF addr.country %] [% addr.country %] [% END %]
                [% END %]
                <p>
                    [% IF ent.phone %] Phone: [% ent.phone %]<br />[% END %]
                    [% IF ent.fax_phone %] Fax: [% ent.fax_phone %]<br />[% END %]
                    [% IF ent.url %] URL: [% ent.url %]<br />[% END %]
                    [% IF ent.email %] E-mail: [% ent.email %] [% END %]
                </p>
            </dd>
            [% END %]
            [% INCLUDE ent_with_address
                ent = invoice.provider
                ent_label = "Provider" %]
            [% INCLUDE ent_with_address
                ent = invoice.shipper
                ent_label = "Shipper" %]
            <dt>Receiver</dt>
            <dd>
                [% invoice.receiver.name %] ([% invoice.receiver.shortname %])
            </dd>
            <dt>Received</dt>
            <dd>
                [% helpers.format_date(invoice.recv_date) %] by
                [% invoice.recv_method %]
            </dd>
            [% IF invoice.note %]
                <dt>Note</dt>
                <dd>
                    [% invoice.note %]
                </dd>
            [% END %]
        </dl>
    </div>
    <ul>
        [% FOR entry IN invoice.entries %]
            <li>
                [% IF entry.lineitem %]
                    Title: [% helpers.get_li_attr(
                        "title", "", entry.lineitem.attributes
                    ) %]<br />
                    Author: [% helpers.get_li_attr(
                        "author", "", entry.lineitem.attributes
                    ) %]
                [% END %]
                [% IF entry.purchase_order %]
                    (PO: [% entry.purchase_order.name %])
                [% END %]<br />
                Invoice item count: [% entry.inv_item_count %]
                [% IF entry.phys_item_count %]
                    / Physical item count: [% entry.phys_item_count %]
                [% END %]
                <br />
                [% IF entry.cost_billed %]
                    Cost billed: [% entry.cost_billed %]
                    [% IF entry.billed_per_item %](per item)[% END %]
                    <br />
                [% END %]
                [% IF entry.actual_cost %]
                    Actual cost: [% entry.actual_cost %]<br />
                [% END %]
                [% IF entry.amount_paid %]
                    Amount paid: [% entry.amount_paid %]<br />
                [% END %]
                [% IF entry.note %]Note: [% entry.note %][% END %]
            </li>
        [% END %]
        [% FOR item IN invoice.items %]
            <li>
                [% IF item.inv_item_type %]
                    Item Type: [% item.inv_item_type %]<br />
                [% END %]
                [% IF item.title %]Title/Description:
                    [% item.title %]<br />
                [% END %]
                [% IF item.author %]Author: [% item.author %]<br />[% END %]
                [% IF item.purchase_order %]PO: [% item.purchase_order %]<br />[% END %]
                [% IF item.note %]Note: [% item.note %]<br />[% END %]
                [% IF item.cost_billed %]
                    Cost billed: [% item.cost_billed %]<br />
                [% END %]
                [% IF item.actual_cost %]
                    Actual cost: [% item.actual_cost %]<br />
                [% END %]
                [% IF item.amount_paid %]
                    Amount paid: [% item.amount_paid %]<br />
                [% END %]
            </li>
        [% END %]
    </ul>
    <div>
        Amounts spent per fund:
        <table>
        [% FOR blob IN user_data %]
            <tr>
                <th style="text-align: left;">[% blob.fund.code %] ([% blob.fund.year %]):</th>
                <td>$[% blob.total %]</td>
            </tr>
        [% END %]
        </table>
    </div>
</div>
[% END %]$$ WHERE id = 22;
INSERT INTO action_trigger.environment (event_def, path) VALUES
    (22, 'provider'),
    (22, 'provider.addresses'),
    (22, 'shipper'),
    (22, 'shipper.addresses'),
    (22, 'receiver'),
    (22, 'entries'),
    (22, 'entries.purchase_order'),
    (22, 'entries.lineitem'),
    (22, 'entries.lineitem.attributes'),
    (22, 'items')
;

INSERT INTO action_trigger.environment (event_def, path) VALUES 
  (23, 'provider.edi_default');

INSERT INTO action_trigger.validator (module, description) 
    VALUES (
        'Acq::PurchaseOrderEDIRequired',
        oils_i18n_gettext(
            'Acq::PurchaseOrderEDIRequired',
            'Purchase order is delivered via EDI',
            'atval',
            'description'
        )
    );

INSERT INTO action_trigger.reactor (module, description)
    VALUES (
        'GeneratePurchaseOrderJEDI',
        oils_i18n_gettext(
            'GeneratePurchaseOrderJEDI',
            'Creates purchase order JEDI (JSON EDI) for subsequent EDI processing',
            'atreact',
            'description'
        )
    );

UPDATE action_trigger.hook 
    SET 
        key = 'acqpo.activated', 
        passive = FALSE,
        description = oils_i18n_gettext(
            'acqpo.activated',
            'Purchase order was activated',
            'ath',
            'description'
        )
    WHERE key = 'format.po.jedi';

-- We just changed a key in action_trigger.hook.  Now redirect any
-- child rows to point to the new key.  (There probably aren't any;
-- this is just a precaution against possible local modifications.)

UPDATE action_trigger.event_definition
SET hook = 'acqpo.activated'
WHERE hook = 'format.po.jedi';

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'AstCall', 'Possibly place a phone call with Asterisk'
);

INSERT INTO
    action_trigger.event_definition (
        id, active, owner, name, hook, validator, reactor,
        cleanup_success, cleanup_failure, delay, delay_field, group_field,
        max_delay, granularity, usr_field, opt_in_setting, template
    ) VALUES (
        24,
        FALSE,
        1,
        'Telephone Overdue Notice',
        'checkout.due', 'NOOP_True', 'AstCall',
        DEFAULT, DEFAULT, '5 seconds', 'due_date', 'usr',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        $$
[% phone = target.0.usr.day_phone | replace('[\s\-\(\)]', '') -%]
[% IF phone.match('^[2-9]') %][% country = 1 %][% ELSE %][% country = '' %][% END -%]
Channel: [% channel_prefix %]/[% country %][% phone %]
Context: overdue-test
MaxRetries: 1
RetryTime: 60
WaitTime: 30
Extension: 10
Archive: 1
Set: eg_user_id=[% target.0.usr.id %]
Set: items=[% target.size %]
Set: titlestring=[% titles = [] %][% FOR circ IN target %][% titles.push(circ.target_copy.call_number.record.simple_record.title) %][% END %][% titles.join(". ") %]
$$
    );

INSERT INTO
    action_trigger.environment (id, event_def, path)
    VALUES
        (DEFAULT, 24, 'target_copy.call_number.record.simple_record'),
        (DEFAULT, 24, 'usr')
    ;

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'circ.format.history.email',
        'circ', 
        oils_i18n_gettext(
            'circ.format.history.email',
            'An email has been requested for a circ history.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'circ.format.history.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.history.print',
            'A circ history needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'ahr.format.history.email',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.history.email',
            'An email has been requested for a hold request history.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'ahr.format.history.print',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.history.print',
            'A hold request history needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )

;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        25,
        TRUE,
        1,
        'circ.history.email',
        'circ.format.history.email',
        'NOOP_True',
        'SendEmail',
        'usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Circulation History

    [% FOR circ IN target %]
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
            Barcode: [% circ.target_copy.barcode %]
            Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]
            Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
            Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]
    [% END %]
$$
    )
    ,(
        26,
        TRUE,
        1,
        'circ.history.print',
        'circ.format.history.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Checked Out: [% date.format(helpers.format_date(circ.xact_start), '%Y-%m-%d') %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            <div>Returned: [% date.format(helpers.format_date(circ.checkin_time), '%Y-%m-%d') %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$
    )
    ,(
        27,
        TRUE,
        1,
        'ahr.history.email',
        'ahr.format.history.email',
        'NOOP_True',
        'SendEmail',
        'usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Request History

    [% FOR hold IN target %]
            [% helpers.get_copy_bib_basics(hold.current_copy.id).title %]
            Requested: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
            [% IF hold.fulfillment_time %]Fulfilled: [% date.format(helpers.format_date(hold.fulfillment_time), '%Y-%m-%d') %][% END %]
    [% END %]
$$
    )
    ,(
        28,
        TRUE,
        1,
        'ahr.history.print',
        'ahr.format.history.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR hold IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(hold.current_copy.id).title %]</div>
            <div>Requested: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]</div>
            [% IF hold.fulfillment_time %]<div>Fulfilled: [% date.format(helpers.format_date(hold.fulfillment_time), '%Y-%m-%d') %]</div>[% END %]
        </li>
    [% END %]
    </ol>
</div>
$$
    )

;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES 
         ( 25, 'target_copy')
        ,( 25, 'usr' )
        ,( 26, 'target_copy' )
        ,( 26, 'usr' )
        ,( 27, 'current_copy' )
        ,( 27, 'usr' )
        ,( 28, 'current_copy' )
        ,( 28, 'usr' )
;

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'money.format.payment_receipt.email',
        'mp', 
        oils_i18n_gettext(
            'money.format.payment_receipt.email',
            'An email has been requested for a payment receipt.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'money.format.payment_receipt.print',
        'mp', 
        oils_i18n_gettext(
            'money.format.payment_receipt.print',
            'A payment receipt needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        29,
        TRUE,
        1,
        'money.payment_receipt.email',
        'money.format.payment_receipt.email',
        'NOOP_True',
        'SendEmail',
        'xact.usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Payment Receipt

[% date.format -%]
[%- SET xact_mp_hash = {} -%]
[%- FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions -%]
    [%- SET xact_id = mp.xact.id -%]
    [%- IF ! xact_mp_hash.defined( xact_id ) -%][%- xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } -%][%- END -%]
    [%- xact_mp_hash.$xact_id.payments.push(mp) -%]
[%- END -%]
[%- FOR xact_id IN xact_mp_hash.keys.sort -%]
    [%- SET xact = xact_mp_hash.$xact_id.xact %]
Transaction ID: [% xact_id %]
    [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
    [% ELSE %]Miscellaneous
    [% END %]
    Line item billings:
        [%- SET mb_type_hash = {} -%]
        [%- FOR mb IN xact.billings %][%# Group billings by their btype -%]
            [%- IF mb.voided == 'f' -%]
                [%- SET mb_type = mb.btype.id -%]
                [%- IF ! mb_type_hash.defined( mb_type ) -%][%- mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } -%][%- END -%]
                [%- IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) -%][%- mb_type_hash.$mb_type.first_ts = mb.billing_ts -%][%- END -%]
                [%- mb_type_hash.$mb_type.last_ts = mb.billing_ts -%]
                [%- mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount -%]
                [%- mb_type_hash.$mb_type.billings.push( mb ) -%]
            [%- END -%]
        [%- END -%]
        [%- FOR mb_type IN mb_type_hash.keys.sort -%]
            [%- IF mb_type == 1 %][%-# Consolidated view of overdue billings -%]
                $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                    on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
            [%- ELSE -%][%# all other billings show individually %]
                [% FOR mb IN mb_type_hash.$mb_type.billings %]
                    $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                [% END %]
            [% END %]
        [% END %]
    Line item payments:
        [% FOR mp IN xact_mp_hash.$xact_id.payments %]
            Payment ID: [% mp.id %]
                Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                    [% CASE "cash_payment" %]cash
                    [% CASE "check_payment" %]check
                    [% CASE "credit_card_payment" %]credit card (
                        [%- SET cc_chunks = mp.credit_card_payment.cc_number.replace(' ','').chunk(4); -%]
                        [%- cc_chunks.slice(0, -1+cc_chunks.max).join.replace('\S','X') -%] 
                        [% cc_chunks.last -%]
                        exp [% mp.credit_card_payment.expire_month %]/[% mp.credit_card_payment.expire_year -%]
                    )
                    [% CASE "credit_payment" %]credit
                    [% CASE "forgive_payment" %]forgiveness
                    [% CASE "goods_payment" %]goods
                    [% CASE "work_payment" %]work
                [%- END %] on [% mp.payment_ts %] [% mp.note %]
        [% END %]
[% END %]
$$
    )
    ,(
        30,
        TRUE,
        1,
        'money.payment_receipt.print',
        'money.format.payment_receipt.print',
        'NOOP_True',
        'ProcessTemplate',
        'xact.usr',
        'print-on-demand',
$$
[%- USE date -%][%- SET user = target.0.xact.usr -%]
<div style="li { padding: 8px; margin 5px; }">
    <div>[% date.format %]</div><br/>
    <ol>
    [% SET xact_mp_hash = {} %]
    [% FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions %]
        [% SET xact_id = mp.xact.id %]
        [% IF ! xact_mp_hash.defined( xact_id ) %][% xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } %][% END %]
        [% xact_mp_hash.$xact_id.payments.push(mp) %]
    [% END %]
    [% FOR xact_id IN xact_mp_hash.keys.sort %]
        [% SET xact = xact_mp_hash.$xact_id.xact %]
        <li>Transaction ID: [% xact_id %]
            [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
            [% ELSE %]Miscellaneous
            [% END %]
            Line item billings:<ol>
                [% SET mb_type_hash = {} %]
                [% FOR mb IN xact.billings %][%# Group billings by their btype %]
                    [% IF mb.voided == 'f' %]
                        [% SET mb_type = mb.btype.id %]
                        [% IF ! mb_type_hash.defined( mb_type ) %][% mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } %][% END %]
                        [% IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) %][% mb_type_hash.$mb_type.first_ts = mb.billing_ts %][% END %]
                        [% mb_type_hash.$mb_type.last_ts = mb.billing_ts %]
                        [% mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount %]
                        [% mb_type_hash.$mb_type.billings.push( mb ) %]
                    [% END %]
                [% END %]
                [% FOR mb_type IN mb_type_hash.keys.sort %]
                    <li>[% IF mb_type == 1 %][%# Consolidated view of overdue billings %]
                        $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                            on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
                    [% ELSE %][%# all other billings show individually %]
                        [% FOR mb IN mb_type_hash.$mb_type.billings %]
                            $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                        [% END %]
                    [% END %]</li>
                [% END %]
            </ol>
            Line item payments:<ol>
                [% FOR mp IN xact_mp_hash.$xact_id.payments %]
                    <li>Payment ID: [% mp.id %]
                        Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                            [% CASE "cash_payment" %]cash
                            [% CASE "check_payment" %]check
                            [% CASE "credit_card_payment" %]credit card (
                                [%- SET cc_chunks = mp.credit_card_payment.cc_number.replace(' ','').chunk(4); -%]
                                [%- cc_chunks.slice(0, -1+cc_chunks.max).join.replace('\S','X') -%] 
                                [% cc_chunks.last -%]
                                exp [% mp.credit_card_payment.expire_month %]/[% mp.credit_card_payment.expire_year -%]
                            )
                            [% CASE "credit_payment" %]credit
                            [% CASE "forgive_payment" %]forgiveness
                            [% CASE "goods_payment" %]goods
                            [% CASE "work_payment" %]work
                        [%- END %] on [% mp.payment_ts %] [% mp.note %]
                    </li>
                [% END %]
            </ol>
        </li>
    [% END %]
    </ol>
</div>
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing mp objects
         ( 29, 'xact')
        ,( 29, 'xact.usr')
        ,( 29, 'xact.grocery' )
        ,( 29, 'xact.circulation' )
        ,( 29, 'xact.summary' )
        ,( 30, 'xact')
        ,( 30, 'xact.usr')
        ,( 30, 'xact.grocery' )
        ,( 30, 'xact.circulation' )
        ,( 30, 'xact.summary' )
;

INSERT INTO action_trigger.cleanup ( module, description ) VALUES (
    'DeleteTempBiblioBucket',
    oils_i18n_gettext(
        'DeleteTempBiblioBucket',
        'Deletes a cbreb object used as a target if it has a btype of "temp"',
        'atclean',
        'description'
    )
);

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'biblio.format.record_entry.email',
        'cbreb', 
        oils_i18n_gettext(
            'biblio.format.record_entry.email',
            'An email has been requested for one or more biblio record entries.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'biblio.format.record_entry.print',
        'cbreb', 
        oils_i18n_gettext(
            'biblio.format.record_entry.print',
            'One or more biblio record entries need to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        cleanup_success,
        cleanup_failure,
        group_field,
        granularity,
        template
    ) VALUES (
        31,
        TRUE,
        1,
        'biblio.record_entry.email',
        'biblio.format.record_entry.email',
        'NOOP_True',
        'SendEmail',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Bibliographic Records

    [% FOR cbreb IN target %]
    [% FOR cbrebi IN cbreb.items %]
        Bib ID# [% cbrebi.target_biblio_record_entry.id %] ISBN: [% crebi.target_biblio_record_entry.simple_record.isbn %]
        Title: [% cbrebi.target_biblio_record_entry.simple_record.title %]
        Author: [% cbrebi.target_biblio_record_entry.simple_record.author %]
        Publication Year: [% cbrebi.target_biblio_record_entry.simple_record.pubdate %]

    [% END %]
    [% END %]
$$
    )
    ,(
        32,
        TRUE,
        1,
        'biblio.record_entry.print',
        'biblio.format.record_entry.print',
        'NOOP_True',
        'ProcessTemplate',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        'print-on-demand',
$$
[%- USE date -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR cbrebi IN cbreb.items %]
        <li>Bib ID# [% cbrebi.target_biblio_record_entry.id %] ISBN: [% crebi.target_biblio_record_entry.simple_record.isbn %]<br />
            Title: [% cbrebi.target_biblio_record_entry.simple_record.title %]<br />
            Author: [% cbrebi.target_biblio_record_entry.simple_record.author %]<br />
            Publication Year: [% cbrebi.target_biblio_record_entry.simple_record.pubdate %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing cbreb objects
         ( 31, 'owner' )
        ,( 31, 'items' )
        ,( 31, 'items.target_biblio_record_entry' )
        ,( 31, 'items.target_biblio_record_entry.simple_record' )
        ,( 31, 'items.target_biblio_record_entry.call_numbers' )
        ,( 31, 'items.target_biblio_record_entry.fixed_fields' )
        ,( 31, 'items.target_biblio_record_entry.notes' )
        ,( 31, 'items.target_biblio_record_entry.full_record_entries' )
        ,( 32, 'owner' )
        ,( 32, 'items' )
        ,( 32, 'items.target_biblio_record_entry' )
        ,( 32, 'items.target_biblio_record_entry.simple_record' )
        ,( 32, 'items.target_biblio_record_entry.call_numbers' )
        ,( 32, 'items.target_biblio_record_entry.fixed_fields' )
        ,( 32, 'items.target_biblio_record_entry.notes' )
        ,( 32, 'items.target_biblio_record_entry.full_record_entries' )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing mp objects
         ( 29, 'credit_card_payment')
        ,( 29, 'xact.billings')
        ,( 29, 'xact.billings.btype')
        ,( 30, 'credit_card_payment')
        ,( 30, 'xact.billings')
        ,( 30, 'xact.billings.btype')
;

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES 
    (   'circ.format.missing_pieces.slip.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.missing_pieces.slip.print',
            'A missing pieces slip needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(  'circ.format.missing_pieces.letter.print',
        'circ', 
        oils_i18n_gettext(
            'circ.format.missing_pieces.letter.print',
            'A missing pieces patron letter needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        33,
        TRUE,
        1,
        'circ.missing_pieces.slip.print',
        'circ.format.missing_pieces.slip.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div style="li { padding: 8px; margin 5px; }">
    <div>[% date.format %]</div><br/>
    Missing pieces for:
    <ol>
    [% FOR circ IN target %]
        <li>Barcode: [% circ.target_copy.barcode %] Transaction ID: [% circ.id %] Due: [% circ.due_date.format %]<br />
            [% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
        </li>
    [% END %]
    </ol>
</div>
$$
    )
    ,(
        34,
        TRUE,
        1,
        'circ.missing_pieces.letter.print',
        'circ.format.missing_pieces.letter.print',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
[% date.format %]
Dear [% user.prefix %] [% user.first_given_name %] [% user.family_name %],

We are missing pieces for the following returned items:
[% FOR circ IN target %]
Barcode: [% circ.target_copy.barcode %] Transaction ID: [% circ.id %] Due: [% circ.due_date.format %]
[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]
[% END %]

Please return these pieces as soon as possible.

Thanks!

Library Staff
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing circ objects
         ( 33, 'usr')
        ,( 33, 'target_copy')
        ,( 33, 'target_copy.circ_lib')
        ,( 33, 'target_copy.circ_lib.mailing_address')
        ,( 33, 'target_copy.circ_lib.billing_address')
        ,( 33, 'target_copy.call_number')
        ,( 33, 'target_copy.call_number.owning_lib')
        ,( 33, 'target_copy.call_number.owning_lib.mailing_address')
        ,( 33, 'target_copy.call_number.owning_lib.billing_address')
        ,( 33, 'circ_lib')
        ,( 33, 'circ_lib.mailing_address')
        ,( 33, 'circ_lib.billing_address')
        ,( 34, 'usr')
        ,( 34, 'target_copy')
        ,( 34, 'target_copy.circ_lib')
        ,( 34, 'target_copy.circ_lib.mailing_address')
        ,( 34, 'target_copy.circ_lib.billing_address')
        ,( 34, 'target_copy.call_number')
        ,( 34, 'target_copy.call_number.owning_lib')
        ,( 34, 'target_copy.call_number.owning_lib.mailing_address')
        ,( 34, 'target_copy.call_number.owning_lib.billing_address')
        ,( 34, 'circ_lib')
        ,( 34, 'circ_lib.mailing_address')
        ,( 34, 'circ_lib.billing_address')
;

INSERT INTO action_trigger.hook (key,core_type,description,passive) 
    VALUES (   
        'ahr.format.pull_list',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.pull_list',
            'Format holds pull list for printing',
            'ath',
            'description'
        ), 
        FALSE
    );

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        35,
        TRUE,
        1,
        'Holds Pull List',
        'ahr.format.pull_list',
        'NOOP_True',
        'ProcessTemplate',
        'pickup_lib',
        'print-on-demand',
$$
[%- USE date -%]
<style>
    table { border-collapse: collapse; } 
    td { padding: 5px; border-bottom: 1px solid #888; } 
    th { font-weight: bold; }
</style>
[% 
    # Sort the holds into copy-location buckets
    # In the main print loop, sort each bucket by callnumber before printing
    SET holds_list = [];
    SET loc_data = [];
    SET current_location = target.0.current_copy.location.id;
    FOR hold IN target;
        IF current_location != hold.current_copy.location.id;
            SET current_location = hold.current_copy.location.id;
            holds_list.push(loc_data);
            SET loc_data = [];
        END;
        SET hold_data = {
            'hold' => hold,
            'callnumber' => hold.current_copy.call_number.label
        };
        loc_data.push(hold_data);
    END;
    holds_list.push(loc_data)
%]
<table>
    <thead>
        <tr>
            <th>Title</th>
            <th>Author</th>
            <th>Shelving Location</th>
            <th>Call Number</th>
            <th>Barcode</th>
            <th>Patron</th>
        </tr>
    </thead>
    <tbody>
    [% FOR loc_data IN holds_list  %]
        [% FOR hold_data IN loc_data.sort('callnumber') %]
            [% 
                SET hold = hold_data.hold;
                SET copy_data = helpers.get_copy_bib_basics(hold.current_copy.id);
            %]
            <tr>
                <td>[% copy_data.title | truncate %]</td>
                <td>[% copy_data.author | truncate %]</td>
                <td>[% hold.current_copy.location.name %]</td>
                <td>[% hold.current_copy.call_number.label %]</td>
                <td>[% hold.current_copy.barcode %]</td>
                <td>[% hold.usr.card.barcode %]</td>
            </tr>
        [% END %]
    [% END %]
    <tbody>
</table>
$$
);

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
        (35, 'current_copy.location'),
        (35, 'current_copy.call_number'),
        (35, 'usr.card'),
        (35, 'pickup_lib')
;

INSERT INTO action_trigger.validator (module, description) VALUES ( 
    'HoldIsCancelled', 
    oils_i18n_gettext( 
        'HoldIsCancelled', 
        'Check whether a hold request is cancelled.', 
        'atval', 
        'description' 
    ) 
);

-- Create the query schema, and the tables and views therein

DROP SCHEMA IF EXISTS sql CASCADE;
DROP SCHEMA IF EXISTS query CASCADE;

CREATE SCHEMA query;

CREATE TABLE query.datatype (
	id              SERIAL            PRIMARY KEY,
	datatype_name   TEXT              NOT NULL UNIQUE,
	is_numeric      BOOL              NOT NULL DEFAULT FALSE,
	is_composite    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qdt_comp_not_num CHECK
	( is_numeric IS FALSE OR is_composite IS FALSE )
);

-- Define the most common datatypes in query.datatype.  Note that none of
-- these stock datatypes specifies a width or precision.

-- Also: set the sequence for query.datatype to 1000, leaving plenty of
-- room for more stock datatypes if we ever want to add them.

SELECT setval( 'query.datatype_id_seq', 1000 );

INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (1, 'SMALLINT', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (2, 'INTEGER', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (3, 'BIGINT', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (4, 'DECIMAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (5, 'NUMERIC', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (6, 'REAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (7, 'DOUBLE PRECISION', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (8, 'SERIAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (9, 'BIGSERIAL', true);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (10, 'MONEY', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (11, 'VARCHAR', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (12, 'CHAR', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (13, 'TEXT', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (14, '"char"', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (15, 'NAME', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (16, 'BYTEA', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (17, 'TIMESTAMP WITHOUT TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (18, 'TIMESTAMP WITH TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (19, 'DATE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (20, 'TIME WITHOUT TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (21, 'TIME WITH TIME ZONE', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (22, 'INTERVAL', false);
 
INSERT INTO query.datatype (id, datatype_name, is_numeric )
  VALUES (23, 'BOOLEAN', false);
 
CREATE TABLE query.subfield (
	id              SERIAL            PRIMARY KEY,
	composite_type  INT               NOT NULL
	                                  REFERENCES query.datatype(id)
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qsf_pos_seq_no
	                                  CHECK( seq_no > 0 ),
	subfield_type   INT               NOT NULL
	                                  REFERENCES query.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qsf_datatype_seq_no UNIQUE (composite_type, seq_no)
);

CREATE TABLE query.function_sig (
	id              SERIAL            PRIMARY KEY,
	function_name   TEXT              NOT NULL,
	return_type     INT               REFERENCES query.datatype(id)
	                                  DEFERRABLE INITIALLY DEFERRED,
	is_aggregate    BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT qfd_rtn_or_aggr CHECK
	( return_type IS NULL OR is_aggregate = FALSE )
);

CREATE INDEX query_function_sig_name_idx 
	ON query.function_sig (function_name);

CREATE TABLE query.function_param_def (
	id              SERIAL            PRIMARY KEY,
	function_id     INT               NOT NULL
	                                  REFERENCES query.function_sig( id )
	                                  ON DELETE CASCADE
	                                  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL
	                                  CONSTRAINT qfpd_pos_seq_no CHECK
	                                  ( seq_no > 0 ),
	datatype        INT               NOT NULL
	                                  REFERENCES query.datatype( id )
	                                  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT qfpd_function_param_seq UNIQUE (function_id, seq_no)
);

CREATE TABLE  query.stored_query (
	id            SERIAL         PRIMARY KEY,
	type          TEXT           NOT NULL CONSTRAINT query_type CHECK
	                             ( type IN ( 'SELECT', 'UNION', 'INTERSECT', 'EXCEPT' ) ),
	use_all       BOOLEAN        NOT NULL DEFAULT FALSE,
	use_distinct  BOOLEAN        NOT NULL DEFAULT FALSE,
	from_clause   INT            , --REFERENCES query.from_clause
	                             --DEFERRABLE INITIALLY DEFERRED,
	where_clause  INT            , --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED,
	having_clause INT            , --REFERENCES query.expression
	                             --DEFERRABLE INITIALLY DEFERRED
	limit_count   INT            , --REFERENCES query.expression( id )
	                             --DEFERRABLE INITIALLY DEFERRED,
	offset_count  INT            --REFERENCES query.expression( id )
	                             --DEFERRABLE INITIALLY DEFERRED
);

-- (Foreign keys to be defined later after other tables are created)

CREATE TABLE query.query_sequence (
	id              SERIAL            PRIMARY KEY,
	parent_query    INT               NOT NULL
	                                  REFERENCES query.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	seq_no          INT               NOT NULL,
	child_query     INT               NOT NULL
	                                  REFERENCES query.stored_query
									  ON DELETE CASCADE
									  DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT query_query_seq UNIQUE( parent_query, seq_no )
);

CREATE TABLE query.bind_variable (
	name          TEXT             PRIMARY KEY,
	type          TEXT             NOT NULL
		                           CONSTRAINT bind_variable_type CHECK
		                           ( type in ( 'string', 'number', 'string_list', 'number_list' )),
	description   TEXT             NOT NULL,
	default_value TEXT,            -- to be encoded in JSON
	label         TEXT             NOT NULL
);

CREATE TABLE query.expression (
	id            SERIAL        PRIMARY KEY,
	type          TEXT          NOT NULL CONSTRAINT expression_type CHECK
	                            ( type IN (
                                    'xbet',    -- between
                                    'xbind',   -- bind variable
                                    'xbool',   -- boolean
                                    'xcase',   -- case
                                    'xcast',   -- cast
                                    'xcol',    -- column
                                    'xex',     -- exists
                                    'xfunc',   -- function
                                    'xin',     -- in
                                    'xisnull', -- is null
                                    'xnull',   -- null
                                    'xnum',    -- number
                                    'xop',     -- operator
                                    'xser',    -- series
                                    'xstr',    -- string
                                    'xsubq'    -- subquery
								) ),
	parenthesize  BOOL          NOT NULL DEFAULT FALSE,
	parent_expr   INT           REFERENCES query.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL DEFAULT 1,
	literal       TEXT,
	table_alias   TEXT,
	column_name   TEXT,
	left_operand  INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	operator      TEXT,
	right_operand INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	function_id   INT           REFERENCES query.function_sig
	                            DEFERRABLE INITIALLY DEFERRED,
	subquery      INT           REFERENCES query.stored_query
	                            DEFERRABLE INITIALLY DEFERRED,
	cast_type     INT           REFERENCES query.datatype
	                            DEFERRABLE INITIALLY DEFERRED,
	negate        BOOL          NOT NULL DEFAULT FALSE,
	bind_variable TEXT          REFERENCES query.bind_variable
		                        DEFERRABLE INITIALLY DEFERRED
);

CREATE UNIQUE INDEX query_expr_parent_seq
	ON query.expression( parent_expr, seq_no )
	WHERE parent_expr IS NOT NULL;

-- Due to some circular references, the following foreign key definitions
-- had to be deferred until query.expression existed:

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( where_clause )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
	ADD FOREIGN KEY ( having_clause )
	REFERENCES query.expression( id )
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
    ADD FOREIGN KEY ( limit_count )
    REFERENCES query.expression( id )
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE query.stored_query
    ADD FOREIGN KEY ( offset_count )
    REFERENCES query.expression( id )
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE query.case_branch (
	id            SERIAL        PRIMARY KEY,
	parent_expr   INT           NOT NULL REFERENCES query.expression
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT           NOT NULL,
	condition     INT           REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	result        INT           NOT NULL REFERENCES query.expression
	                            DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT case_branch_parent_seq UNIQUE (parent_expr, seq_no)
);

CREATE TABLE query.from_relation (
	id               SERIAL        PRIMARY KEY,
	type             TEXT          NOT NULL CONSTRAINT relation_type CHECK (
	                                   type IN ( 'RELATION', 'SUBQUERY', 'FUNCTION' ) ),
	table_name       TEXT,
	class_name       TEXT,
	subquery         INT           REFERENCES query.stored_query,
	function_call    INT           REFERENCES query.expression,
	table_alias      TEXT,
	parent_relation  INT           REFERENCES query.from_relation
	                               ON DELETE CASCADE
	                               DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT           NOT NULL DEFAULT 1,
	join_type        TEXT          CONSTRAINT good_join_type CHECK (
	                                   join_type IS NULL OR join_type IN
	                                   ( 'INNER', 'LEFT', 'RIGHT', 'FULL' )
	                               ),
	on_clause        INT           REFERENCES query.expression
	                               DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT join_or_core CHECK (
        ( parent_relation IS NULL AND join_type IS NULL
          AND on_clause IS NULL )
        OR
        ( parent_relation IS NOT NULL AND join_type IS NOT NULL
          AND on_clause IS NOT NULL )
	)
);

CREATE UNIQUE INDEX from_parent_seq
	ON query.from_relation( parent_relation, seq_no )
	WHERE parent_relation IS NOT NULL;

-- The following foreign key had to be deferred until
-- query.from_relation existed

ALTER TABLE query.stored_query
	ADD FOREIGN KEY (from_clause)
	REFERENCES query.from_relation
	DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE query.record_column (
	id            SERIAL            PRIMARY KEY,
	from_relation INT               NOT NULL REFERENCES query.from_relation
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no        INT               NOT NULL,
	column_name   TEXT              NOT NULL,
	column_type   INT               NOT NULL REFERENCES query.datatype
	                                ON DELETE CASCADE
									DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT column_sequence UNIQUE (from_relation, seq_no)
);

CREATE TABLE query.select_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES query.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES query.expression
	                                DEFERRABLE INITIALLY DEFERRED,
	column_alias     TEXT,
	grouped_by       BOOL           NOT NULL DEFAULT FALSE,
	CONSTRAINT select_sequence UNIQUE( stored_query, seq_no )
);

CREATE TABLE query.order_by_item (
	id               SERIAL         PRIMARY KEY,
	stored_query     INT            NOT NULL REFERENCES query.stored_query
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	seq_no           INT            NOT NULL,
	expression       INT            NOT NULL REFERENCES query.expression
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT order_by_sequence UNIQUE( stored_query, seq_no )
);

------------------------------------------------------------
-- Create updatable views for different kinds of expressions
------------------------------------------------------------

-- Create updatable view for BETWEEN expressions

CREATE OR REPLACE VIEW query.expr_xbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xbet';

CREATE OR REPLACE RULE query_expr_xbet_insert_rule AS
    ON INSERT TO query.expr_xbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbet_update_rule AS
    ON UPDATE TO query.expr_xbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbet_delete_rule AS
    ON DELETE TO query.expr_xbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for bind variable expressions

CREATE OR REPLACE VIEW query.expr_xbind AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    FROM
        query.expression
    WHERE
        type = 'xbind';

CREATE OR REPLACE RULE query_expr_xbind_insert_rule AS
    ON INSERT TO query.expr_xbind
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbind',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.bind_variable
    );

CREATE OR REPLACE RULE query_expr_xbind_update_rule AS
    ON UPDATE TO query.expr_xbind
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		bind_variable = NEW.bind_variable
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbind_delete_rule AS
    ON DELETE TO query.expr_xbind
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for boolean expressions

CREATE OR REPLACE VIEW query.expr_xbool AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal,
		negate
    FROM
        query.expression
    WHERE
        type = 'xbool';

CREATE OR REPLACE RULE query_expr_xbool_insert_rule AS
    ON INSERT TO query.expr_xbool
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbool',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbool_update_rule AS
    ON UPDATE TO query.expr_xbool
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbool_delete_rule AS
    ON DELETE TO query.expr_xbool
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for CASE expressions

CREATE OR REPLACE VIEW query.expr_xcase AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcase';

CREATE OR REPLACE RULE query_expr_xcase_insert_rule AS
    ON INSERT TO query.expr_xcase
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcase',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcase_update_rule AS
    ON UPDATE TO query.expr_xcase
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcase_delete_rule AS
    ON DELETE TO query.expr_xcase
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for cast expressions

CREATE OR REPLACE VIEW query.expr_xcast AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		cast_type,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcast';

CREATE OR REPLACE RULE query_expr_xcast_insert_rule AS
    ON INSERT TO query.expr_xcast
    DO INSTEAD
    INSERT INTO query.expression (
        id,
        type,
        parenthesize,
        parent_expr,
        seq_no,
        left_operand,
        cast_type,
        negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcast',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.left_operand,
        NEW.cast_type,
        COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcast_update_rule AS
    ON UPDATE TO query.expr_xcast
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		cast_type = NEW.cast_type,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcast_delete_rule AS
    ON DELETE TO query.expr_xcast
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for column expressions

CREATE OR REPLACE VIEW query.expr_xcol AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name,
		negate
    FROM
        query.expression
    WHERE
        type = 'xcol';

CREATE OR REPLACE RULE query_expr_xcol_insert_rule AS
    ON INSERT TO query.expr_xcol
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcol',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.table_alias,
		NEW.column_name,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcol_update_rule AS
    ON UPDATE TO query.expr_xcol
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		table_alias = NEW.table_alias,
		column_name = NEW.column_name,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcol_delete_rule AS
    ON DELETE TO query.expr_xcol
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for EXISTS expressions

CREATE OR REPLACE VIEW query.expr_xex AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xex';

CREATE OR REPLACE RULE query_expr_xex_insert_rule AS
    ON INSERT TO query.expr_xex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xex_update_rule AS
    ON UPDATE TO query.expr_xex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xex_delete_rule AS
    ON DELETE TO query.expr_xex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for function call expressions

CREATE OR REPLACE VIEW query.expr_xfunc AS
    SELECT
        id,
        parenthesize,
        parent_expr,
        seq_no,
        column_name,
        function_id,
        negate
    FROM
        query.expression
    WHERE
        type = 'xfunc';

CREATE OR REPLACE RULE query_expr_xfunc_insert_rule AS
    ON INSERT TO query.expr_xfunc
    DO INSTEAD
    INSERT INTO query.expression (
        id,
        type,
        parenthesize,
        parent_expr,
        seq_no,
        column_name,
        function_id,
        negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.column_name,
        NEW.function_id,
        COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xfunc_update_rule AS
    ON UPDATE TO query.expr_xfunc
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        column_name = NEW.column_name,
        function_id = NEW.function_id,
        negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfunc_delete_rule AS
    ON DELETE TO query.expr_xfunc
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for IN expressions

CREATE OR REPLACE VIEW query.expr_xin AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xin';

CREATE OR REPLACE RULE query_expr_xin_insert_rule AS
    ON INSERT TO query.expr_xin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xin_update_rule AS
    ON UPDATE TO query.expr_xin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xin_delete_rule AS
    ON DELETE TO query.expr_xin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for IS NULL expressions

CREATE OR REPLACE VIEW query.expr_xisnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xisnull';

CREATE OR REPLACE RULE query_expr_xisnull_insert_rule AS
    ON INSERT TO query.expr_xisnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xisnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xisnull_update_rule AS
    ON UPDATE TO query.expr_xisnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xisnull_delete_rule AS
    ON DELETE TO query.expr_xisnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NULL expressions

CREATE OR REPLACE VIEW query.expr_xnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    FROM
        query.expression
    WHERE
        type = 'xnull';

CREATE OR REPLACE RULE query_expr_xnull_insert_rule AS
    ON INSERT TO query.expr_xnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xnull_update_rule AS
    ON UPDATE TO query.expr_xnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnull_delete_rule AS
    ON DELETE TO query.expr_xnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for numeric literal expressions

CREATE OR REPLACE VIEW query.expr_xnum AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    FROM
        query.expression
    WHERE
        type = 'xnum';

CREATE OR REPLACE RULE query_expr_xnum_insert_rule AS
    ON INSERT TO query.expr_xnum
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnum',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_xnum_update_rule AS
    ON UPDATE TO query.expr_xnum
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnum_delete_rule AS
    ON DELETE TO query.expr_xnum
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for operator expressions

CREATE OR REPLACE VIEW query.expr_xop AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xop';

CREATE OR REPLACE RULE query_expr_xop_insert_rule AS
    ON INSERT TO query.expr_xop
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xop',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.operator,
		NEW.right_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xop_update_rule AS
    ON UPDATE TO query.expr_xop
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		operator = NEW.operator,
		right_operand = NEW.right_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xop_delete_rule AS
    ON DELETE TO query.expr_xop
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for series expressions
-- i.e. series of expressions separated by operators

CREATE OR REPLACE VIEW query.expr_xser AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    FROM
        query.expression
    WHERE
        type = 'xser';

CREATE OR REPLACE RULE query_expr_xser_insert_rule AS
    ON INSERT TO query.expr_xser
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xser',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.operator,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xser_update_rule AS
    ON UPDATE TO query.expr_xser
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		operator = NEW.operator,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xser_delete_rule AS
    ON DELETE TO query.expr_xser
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for string literal expressions

CREATE OR REPLACE VIEW query.expr_xstr AS
    SELECT
        id,
        parenthesize,
        parent_expr,
        seq_no,
        literal
    FROM
        query.expression
    WHERE
        type = 'xstr';

CREATE OR REPLACE RULE query_expr_string_insert_rule AS
    ON INSERT TO query.expr_xstr
    DO INSTEAD
    INSERT INTO query.expression (
        id,
        type,
        parenthesize,
        parent_expr,
        seq_no,
        literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xstr',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_string_update_rule AS
    ON UPDATE TO query.expr_xstr
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_string_delete_rule AS
    ON DELETE TO query.expr_xstr
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for subquery expressions

CREATE OR REPLACE VIEW query.expr_xsubq AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    FROM
        query.expression
    WHERE
        type = 'xsubq';

CREATE OR REPLACE RULE query_expr_xsubq_insert_rule AS
    ON INSERT TO query.expr_xsubq
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xsubq',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xsubq_update_rule AS
    ON UPDATE TO query.expr_xsubq
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xsubq_delete_rule AS
    ON DELETE TO query.expr_xsubq
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

CREATE TABLE action.fieldset (
    id              SERIAL          PRIMARY KEY,
    owner           INT             NOT NULL REFERENCES actor.usr (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    owning_lib      INT             NOT NULL REFERENCES actor.org_unit (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    status          TEXT            NOT NULL
                                    CONSTRAINT valid_status CHECK ( status in
                                    ( 'PENDING', 'APPLIED', 'ERROR' )),
    creation_time   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    scheduled_time  TIMESTAMPTZ,
    applied_time    TIMESTAMPTZ,
    classname       TEXT            NOT NULL, -- an IDL class name
    name            TEXT            NOT NULL,
    stored_query    INT             REFERENCES query.stored_query (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    pkey_value      TEXT,
    CONSTRAINT lib_name_unique UNIQUE (owning_lib, name),
    CONSTRAINT fieldset_one_or_the_other CHECK (
        (stored_query IS NOT NULL AND pkey_value IS NULL) OR
        (pkey_value IS NOT NULL AND stored_query IS NULL)
    )
    -- the CHECK constraint means we can update the fields for a single
    -- row without all the extra overhead involved in a query
);

CREATE INDEX action_fieldset_sched_time_idx ON action.fieldset( scheduled_time );
CREATE INDEX action_owner_idx               ON action.fieldset( owner );

CREATE TABLE action.fieldset_col_val (
    id              SERIAL  PRIMARY KEY,
    fieldset        INT     NOT NULL REFERENCES action.fieldset
                                         ON DELETE CASCADE
                                         DEFERRABLE INITIALLY DEFERRED,
    col             TEXT    NOT NULL,  -- "field" from the idl ... the column on the table
    val             TEXT,              -- value for the column ... NULL means, well, NULL
    CONSTRAINT fieldset_col_once_per_set UNIQUE (fieldset, col)
);

CREATE OR REPLACE FUNCTION action.apply_fieldset(
	fieldset_id IN INT,        -- id from action.fieldset
	table_name  IN TEXT,       -- table to be updated
	pkey_name   IN TEXT,       -- name of primary key column in that table
	query       IN TEXT        -- query constructed by qstore (for query-based
	                           --    fieldsets only; otherwise null
)
RETURNS TEXT AS $$
DECLARE
	statement TEXT;
	fs_status TEXT;
	fs_pkey_value TEXT;
	fs_query TEXT;
	sep CHAR;
	status_code TEXT;
	msg TEXT;
	update_count INT;
	cv RECORD;
BEGIN
	-- Sanity checks
	IF fieldset_id IS NULL THEN
		RETURN 'Fieldset ID parameter is NULL';
	END IF;
	IF table_name IS NULL THEN
		RETURN 'Table name parameter is NULL';
	END IF;
	IF pkey_name IS NULL THEN
		RETURN 'Primary key name parameter is NULL';
	END IF;
	--
	statement := 'UPDATE ' || table_name || ' SET';
	--
	SELECT
		status,
		quote_literal( pkey_value )
	INTO
		fs_status,
		fs_pkey_value
	FROM
		action.fieldset
	WHERE
		id = fieldset_id;
	--
	IF fs_status IS NULL THEN
		RETURN 'No fieldset found for id = ' || fieldset_id;
	ELSIF fs_status = 'APPLIED' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
	END IF;
	--
	sep := '';
	FOR cv IN
		SELECT  col,
				val
		FROM    action.fieldset_col_val
		WHERE   fieldset = fieldset_id
	LOOP
		statement := statement || sep || ' ' || cv.col
					 || ' = ' || coalesce( quote_literal( cv.val ), 'NULL' );
		sep := ',';
	END LOOP;
	--
	IF sep = '' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
	END IF;
	--
	-- Add the WHERE clause.  This differs according to whether it's a
	-- single-row fieldset or a query-based fieldset.
	--
	IF query IS NULL        AND fs_pkey_value IS NULL THEN
		RETURN 'Incomplete fieldset: neither a primary key nor a query available';
	ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
	    fs_query := rtrim( query, ';' );
	    statement := statement || ' WHERE ' || pkey_name || ' IN ( '
	                 || fs_query || ' );';
	ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
		statement := statement || ' WHERE ' || pkey_name || ' = '
				     || fs_pkey_value || ';';
	ELSE  -- both are not null
		RETURN 'Ambiguous fieldset: both a primary key and a query provided';
	END IF;
	--
	-- Execute the update
	--
	BEGIN
		EXECUTE statement;
		GET DIAGNOSTICS update_count = ROW_COUNT;
		--
		IF UPDATE_COUNT > 0 THEN
			status_code := 'APPLIED';
			msg := NULL;
		ELSE
			status_code := 'ERROR';
			msg := 'No eligible rows found for fieldset ' || fieldset_id;
    	END IF;
	EXCEPTION WHEN OTHERS THEN
		status_code := 'ERROR';
		msg := 'Unable to apply fieldset ' || fieldset_id
			   || ': ' || sqlerrm;
	END;
	--
	-- Update fieldset status
	--
	UPDATE action.fieldset
	SET status       = status_code,
	    applied_time = now()
	WHERE id = fieldset_id;
	--
	RETURN msg;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION action.apply_fieldset( INT, TEXT, TEXT, TEXT ) IS $$
/**
 * Applies a specified fieldset, using a supplied table name and primary
 * key name.  The query parameter should be non-null only for
 * query-based fieldsets.
 *
 * Returns NULL if successful, or an error message if not.
 */
$$;

CREATE INDEX uhr_hold_idx ON action.unfulfilled_hold_list (hold);

CREATE OR REPLACE VIEW action.unfulfilled_hold_loops AS
    SELECT  u.hold,
            c.circ_lib,
            count(*)
      FROM  action.unfulfilled_hold_list u
            JOIN asset.copy c ON (c.id = u.current_copy)
      GROUP BY 1,2;

CREATE OR REPLACE VIEW action.unfulfilled_hold_min_loop AS
    SELECT  hold,
            min(count)
      FROM  action.unfulfilled_hold_loops
      GROUP BY 1;

CREATE OR REPLACE VIEW action.unfulfilled_hold_innermost_loop AS
    SELECT  DISTINCT l.*
      FROM  action.unfulfilled_hold_loops l
            JOIN action.unfulfilled_hold_min_loop m USING (hold)
      WHERE l.count = m.min;

ALTER TABLE asset.copy
ADD COLUMN dummy_isbn TEXT;

ALTER TABLE auditor.asset_copy_history
ADD COLUMN dummy_isbn TEXT;

-- Add new column status_changed_date to asset.copy, with trigger to maintain it
-- Add corresponding new column to auditor.asset_copy_history

ALTER TABLE asset.copy
	ADD COLUMN status_changed_time TIMESTAMPTZ;

ALTER TABLE auditor.asset_copy_history
	ADD COLUMN status_changed_time TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> OLD.status THEN
        NEW.status_changed_time := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_status_changed_trig
	BEFORE UPDATE ON asset.copy
	FOR EACH ROW EXECUTE PROCEDURE asset.acp_status_changed();

ALTER TABLE asset.copy
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE auditor.asset_copy_history
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE asset.copy ADD COLUMN floating BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE auditor.asset_copy_history ADD COLUMN floating BOOL;

DROP INDEX IF EXISTS asset.copy_barcode_key;
CREATE UNIQUE INDEX copy_barcode_key ON asset.copy (barcode) WHERE deleted = FALSE OR deleted IS FALSE;

-- Note: later we create a trigger a_opac_vis_mat_view_tgr
-- AFTER INSERT OR UPDATE ON asset.copy

ALTER TABLE asset.copy ADD COLUMN cost NUMERIC(8,2);
ALTER TABLE auditor.asset_copy_history ADD COLUMN cost NUMERIC(8,2);

-- Moke mostly parallel changes to action.circulation
-- and action.aged_circulation

ALTER TABLE action.circulation
ADD COLUMN workstation INT
    REFERENCES actor.workstation
	ON DELETE SET NULL
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.aged_circulation
ADD COLUMN workstation INT;

ALTER TABLE action.circulation
ADD COLUMN parent_circ BIGINT
	REFERENCES action.circulation(id)
	DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX circ_parent_idx
ON action.circulation( parent_circ )
WHERE parent_circ IS NOT NULL;

ALTER TABLE action.aged_circulation
ADD COLUMN parent_circ BIGINT;

ALTER TABLE action.circulation
ADD COLUMN checkin_workstation INT
	REFERENCES actor.workstation(id)
	ON DELETE SET NULL
	DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.aged_circulation
ADD COLUMN checkin_workstation INT;

ALTER TABLE action.circulation
ADD COLUMN checkin_scan_time TIMESTAMPTZ;

ALTER TABLE action.aged_circulation
ADD COLUMN checkin_scan_time TIMESTAMPTZ;

CREATE INDEX action_circulation_target_copy_idx
ON action.circulation (target_copy);

CREATE INDEX action_aged_circulation_target_copy_idx
ON action.aged_circulation (target_copy);

ALTER TABLE action.circulation
DROP CONSTRAINT circulation_stop_fines_check;

ALTER TABLE action.circulation
	ADD CONSTRAINT circulation_stop_fines_check
	CHECK (stop_fines IN (
        'CHECKIN','CLAIMSRETURNED','LOST','MAXFINES','RENEW','LONGOVERDUE','CLAIMSNEVERCHECKEDOUT'));

-- Hard due-date functionality
CREATE TABLE config.hard_due_date (
        id          SERIAL      PRIMARY KEY,
        name        TEXT        NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
        ceiling_date    TIMESTAMPTZ NOT NULL,
        forceto     BOOL        NOT NULL,
        owner       INT         NOT NULL
);

CREATE TABLE config.hard_due_date_values (
    id                  SERIAL      PRIMARY KEY,
    hard_due_date       INT         NOT NULL REFERENCES config.hard_due_date (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    ceiling_date        TIMESTAMPTZ NOT NULL,
    active_date         TIMESTAMPTZ NOT NULL
);

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN hard_due_date INT REFERENCES config.hard_due_date (id);

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY hard_due_date, active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date; -- Time is equal if we've already updated the chdd

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;

-- Correct some long-standing misspellings involving variations of "recur"

ALTER TABLE action.circulation RENAME COLUMN recuring_fine TO recurring_fine;
ALTER TABLE action.circulation RENAME COLUMN recuring_fine_rule TO recurring_fine_rule;

ALTER TABLE action.aged_circulation RENAME COLUMN recuring_fine TO recurring_fine;
ALTER TABLE action.aged_circulation RENAME COLUMN recuring_fine_rule TO recurring_fine_rule;

ALTER TABLE config.rule_recuring_fine RENAME TO rule_recurring_fine;
ALTER TABLE config.rule_recuring_fine_id_seq RENAME TO rule_recurring_fine_id_seq;

ALTER TABLE config.rule_recurring_fine RENAME COLUMN recurance_interval TO recurrence_interval;

-- Might as well keep the comment in sync as well
COMMENT ON TABLE config.rule_recurring_fine IS $$
/*
 * Copyright (C) 2005  Georgia Public Library Service 
 * Mike Rylander <mrylander@gmail.com>
 *
 * Circulation Recurring Fine rules
 *
 * Each circulation is given a recurring fine amount based on one of
 * these rules.  The recurrence_interval should not be any shorter
 * than the interval between runs of the fine_processor.pl script
 * (which is run from CRON), or you could miss fines.
 * 
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

-- Extend the name change to some related views:

DROP VIEW IF EXISTS reporter.overdue_circs;

CREATE OR REPLACE VIEW reporter.overdue_circs AS
SELECT  *
  FROM  action.circulation
    WHERE checkin_time is null
	        AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED') OR stop_fines IS NULL)
			        AND due_date < now();

DROP VIEW IF EXISTS stats.fleshed_circulation;

DROP VIEW IF EXISTS stats.fleshed_copy;

CREATE VIEW stats.fleshed_copy AS
        SELECT  cp.*,
        CAST(cp.create_date AS DATE) AS create_date_day,
        CAST(cp.edit_date AS DATE) AS edit_date_day,
        DATE_TRUNC('hour', cp.create_date) AS create_date_hour,
        DATE_TRUNC('hour', cp.edit_date) AS edit_date_hour,
                cn.label AS call_number_label,
                cn.owning_lib,
                rd.item_lang,
                rd.item_type,
                rd.item_form
        FROM    asset.copy cp
                JOIN asset.call_number cn ON (cp.call_number = cn.id)
                JOIN metabib.rec_descriptor rd ON (rd.record = cn.record);

CREATE VIEW stats.fleshed_circulation AS
        SELECT  c.*,
                CAST(c.xact_start AS DATE) AS start_date_day,
                CAST(c.xact_finish AS DATE) AS finish_date_day,
                DATE_TRUNC('hour', c.xact_start) AS start_date_hour,
                DATE_TRUNC('hour', c.xact_finish) AS finish_date_hour,
                cp.call_number_label,
                cp.owning_lib,
                cp.item_lang,
                cp.item_type,
                cp.item_form
        FROM    action.circulation c
                JOIN stats.fleshed_copy cp ON (cp.id = c.target_copy);

-- Drop a view temporarily in order to alter action.all_circulation, upon
-- which it is dependent.  We will recreate the view later.

DROP VIEW IF EXISTS extend_reporter.full_circ_count;

-- You would think that CREATE OR REPLACE would be enough, but in testing
-- PostgreSQL complained about renaming the columns in the view. So we
-- drop the view first.
DROP VIEW IF EXISTS action.all_circulation;

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = a.id);

-- Recreate the temporarily dropped view, having altered the action.all_circulation view:

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(sum(c.circ_count), 0::bigint) + COALESCE(count(circ.id), 0::bigint) + COALESCE(count(acirc.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".circulation circ ON circ.target_copy = cp.id
   LEFT JOIN "action".aged_circulation acirc ON acirc.target_copy = cp.id
  GROUP BY cp.id;

CREATE UNIQUE INDEX only_one_concurrent_checkout_per_copy ON action.circulation(target_copy) WHERE checkin_time IS NULL;

ALTER TABLE action.circulation DROP CONSTRAINT action_circulation_target_copy_fkey;

-- Rebuild dependent views

DROP VIEW IF EXISTS action.billable_circulations;

CREATE OR REPLACE VIEW action.billable_circulations AS
    SELECT  *
      FROM  action.circulation
      WHERE xact_finish IS NULL;

DROP VIEW IF EXISTS action.open_circulation;

CREATE OR REPLACE VIEW action.open_circulation AS
    SELECT  *
      FROM  action.circulation
      WHERE checkin_time IS NULL
      ORDER BY due_date;

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
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
        FROM action.all_circulation WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'biblios' AND name = 'title';

UPDATE config.z3950_attr SET truncation = 1 WHERE source = 'biblios' AND truncation = 0;

-- Adding circ.holds.target_skip_me OU setting logic to the pre-matchpoint tests

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS INT AS $func$
DECLARE
    current_requestor_group    permission.grp_tree%ROWTYPE;
    requestor_object    actor.usr%ROWTYPE;
    user_object        actor.usr%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object        asset.call_number%ROWTYPE;
    rec_descriptor        metabib.rec_descriptor%ROWTYPE;
    current_mp_weight    FLOAT;
    matchpoint_weight    FLOAT;
    tmp_weight        FLOAT;
    current_mp        config.hold_matrix_matchpoint%ROWTYPE;
    matchpoint        config.hold_matrix_matchpoint%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO requestor_object * FROM actor.usr WHERE id = match_requestor;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r WHERE r.record = item_cn_object.record;

    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF NOT FOUND THEN
        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = requestor_object.profile;
    ELSE
        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = user_object.profile;
    END IF;

    LOOP 
        -- for each potential matchpoint for this ou and group ...
        FOR current_mp IN
            SELECT    m.*
              FROM    config.hold_matrix_matchpoint m
              WHERE    m.requestor_grp = current_requestor_group.id AND m.active
              ORDER BY    CASE WHEN m.circ_modifier    IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.juvenile_flag    IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.marc_type        IS NOT NULL THEN 8 ELSE 0 END +
                    CASE WHEN m.marc_form        IS NOT NULL THEN 4 ELSE 0 END +
                    CASE WHEN m.marc_vr_format    IS NOT NULL THEN 2 ELSE 0 END +
                    CASE WHEN m.ref_flag        IS NOT NULL THEN 1 ELSE 0 END DESC LOOP

            current_mp_weight := 5.0;

            IF current_mp.circ_modifier IS NOT NULL THEN
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier OR item_object.circ_modifier IS NULL;
            END IF;

            IF current_mp.marc_type IS NOT NULL THEN
                IF item_object.circ_as_type IS NOT NULL THEN
                    CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
                ELSE
                    CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
                END IF;
            END IF;

            IF current_mp.marc_form IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
            END IF;

            IF current_mp.marc_vr_format IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
            END IF;

            IF current_mp.juvenile_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.juvenile_flag <> user_object.juvenile;
            END IF;

            IF current_mp.ref_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
            END IF;


            -- caclulate the rule match weight
            IF current_mp.item_owning_ou IS NOT NULL THEN
                CONTINUE WHEN current_mp.item_owning_ou NOT IN (SELECT (actor.org_unit_ancestors(item_cn_object.owning_lib)).id);
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_owning_ou, item_cn_object.owning_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.item_circ_ou IS NOT NULL THEN
                CONTINUE WHEN current_mp.item_circ_ou NOT IN (SELECT (actor.org_unit_ancestors(item_object.circ_lib)).id);
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_circ_ou, item_object.circ_lib)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.pickup_ou IS NOT NULL THEN
                CONTINUE WHEN current_mp.pickup_ou NOT IN (SELECT (actor.org_unit_ancestors(pickup_ou)).id);
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.pickup_ou, pickup_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.request_ou IS NOT NULL THEN
                CONTINUE WHEN current_mp.request_ou NOT IN (SELECT (actor.org_unit_ancestors(request_ou)).id);
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.request_ou, request_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            IF current_mp.user_home_ou IS NOT NULL THEN
                CONTINUE WHEN current_mp.user_home_ou NOT IN (SELECT (actor.org_unit_ancestors(user_object.home_ou)).id);
                SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.user_home_ou, user_object.home_ou)::FLOAT + 1.0)::FLOAT;
                current_mp_weight := current_mp_weight - tmp_weight;
            END IF; 

            -- set the matchpoint if we found the best one
            IF matchpoint_weight IS NULL OR matchpoint_weight > current_mp_weight THEN
                matchpoint = current_mp;
                matchpoint_weight = current_mp_weight;
            END IF;

        END LOOP;

        EXIT WHEN current_requestor_group.parent IS NULL OR matchpoint.id IS NOT NULL;

        SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = current_requestor_group.parent;
    END LOOP;

    RETURN matchpoint.id;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( pickup_ou );

    result.success := TRUE;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    IF NOT retargetting THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%HOLD%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    
        IF hold_test.stop_blocked_user IS TRUE THEN
            FOR standing_penalty IN
                SELECT  DISTINCT csp.*
                  FROM  actor.usr_standing_penalty usp
                        JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
                  WHERE usr = match_user
                        AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                        AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                        AND csp.block_list LIKE '%CIRC%' LOOP
        
                result.fail_part := standing_penalty.name;
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END LOOP;
        END IF;
    
        IF hold_test.max_holds IS NOT NULL THEN
            SELECT    INTO hold_count COUNT(*)
              FROM    action.hold_request
              WHERE    usr = match_user
                AND fulfillment_time IS NULL
                AND cancel_time IS NULL
                AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;
    
            IF hold_count >= hold_test.max_holds THEN
                result.fail_part := 'config.hold_matrix_test.max_holds';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;

        IF item_object.create_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.hold_request_permit_test( $1, $2, $3, $4, $5, FALSE);
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.hold_retarget_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.hold_request_permit_test( $1, $2, $3, $4, $5, TRUE );
$func$ LANGUAGE SQL;

-- New post-delete trigger to propagate deletions to parent(s)

CREATE OR REPLACE FUNCTION action.age_parent_circ_on_delete () RETURNS TRIGGER AS $$
BEGIN

    -- Having deleted a renewal, we can delete the original circulation (or a previous
    -- renewal, if that's what parent_circ is pointing to).  That deletion will trigger
    -- deletion of any prior parents, etc. recursively.

    IF OLD.parent_circ IS NOT NULL THEN
        DELETE FROM action.circulation
        WHERE id = OLD.parent_circ;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER age_parent_circ AFTER DELETE ON action.circulation
FOR EACH ROW EXECUTE PROCEDURE action.age_parent_circ_on_delete ();

-- This only gets inserted if there are no other id > 100 billing types
INSERT INTO config.billing_type (id, name, owner) SELECT DISTINCT 101, oils_i18n_gettext(101, 'Misc', 'cbt', 'name'), 1 FROM config.billing_type_id_seq WHERE last_value < 101;
SELECT SETVAL('config.billing_type_id_seq'::TEXT, 101) FROM config.billing_type_id_seq WHERE last_value < 101;

-- Populate xact_type column in the materialized version of billable_xact_summary

CREATE OR REPLACE FUNCTION money.mat_summary_create () RETURNS TRIGGER AS $$
BEGIN
	INSERT INTO money.materialized_billable_xact_summary (id, usr, xact_start, xact_finish, total_paid, total_owed, balance_owed, xact_type)
		VALUES ( NEW.id, NEW.usr, NEW.xact_start, NEW.xact_finish, 0.0, 0.0, 0.0, TG_ARGV[0]);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;
 
DROP TRIGGER IF EXISTS mat_summary_create_tgr ON action.circulation;
CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('circulation');
 
DROP TRIGGER IF EXISTS mat_summary_create_tgr ON money.grocery;
CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('grocery');

CREATE RULE money_payment_view_update AS ON UPDATE TO money.payment_view DO INSTEAD 
    UPDATE money.payment SET xact = NEW.xact, payment_ts = NEW.payment_ts, voided = NEW.voided, amount = NEW.amount, note = NEW.note WHERE id = NEW.id;

-- Generate the equivalent of compound subject entries from the existing rows
-- so that we don't have to laboriously reindex them

--INSERT INTO config.metabib_field (field_class, name, format, xpath ) VALUES
--    ( 'subject', 'complete', 'mods32', $$//mods32:mods/mods32:subject//text()$$ );
--
--CREATE INDEX metabib_subject_field_entry_source_idx ON metabib.subject_field_entry (source);
--
--INSERT INTO metabib.subject_field_entry (source, field, value)
--    SELECT source, (
--            SELECT id 
--            FROM config.metabib_field
--            WHERE field_class = 'subject' AND name = 'complete'
--        ), 
--        ARRAY_TO_STRING ( 
--            ARRAY (
--                SELECT value 
--                FROM metabib.subject_field_entry msfe
--                WHERE msfe.source = groupee.source
--                ORDER BY source 
--            ), ' ' 
--        ) AS grouped
--    FROM ( 
--        SELECT source
--        FROM metabib.subject_field_entry
--        GROUP BY source
--    ) AS groupee;

CREATE OR REPLACE FUNCTION money.materialized_summary_billing_del () RETURNS TRIGGER AS $$
DECLARE
        prev_billing    money.billing%ROWTYPE;
        old_billing     money.billing%ROWTYPE;
BEGIN
        SELECT * INTO prev_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1 OFFSET 1;
        SELECT * INTO old_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;

        IF OLD.id = old_billing.id THEN
                UPDATE  money.materialized_billable_xact_summary
                  SET   last_billing_ts = prev_billing.billing_ts,
                        last_billing_note = prev_billing.note,
                        last_billing_type = prev_billing.billing_type
                  WHERE id = OLD.xact;
        END IF;

        IF NOT OLD.voided THEN
                UPDATE  money.materialized_billable_xact_summary
                  SET   total_owed = total_owed - OLD.amount,
                        balance_owed = balance_owed + OLD.amount
                  WHERE id = OLD.xact;
        END IF;

        RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

-- ARG! need to rid ourselves of the broken table definition ... this mechanism is not ideal, sorry.
DROP TABLE IF EXISTS config.index_normalizer CASCADE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = decode_utf8(shift);
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- Some handy functions, based on existing ones, to provide optional ingest normalization

CREATE OR REPLACE FUNCTION public.left_trunc( TEXT, INT ) RETURNS TEXT AS $func$
	SELECT SUBSTRING($1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.right_trunc( TEXT, INT ) RETURNS TEXT AS $func$
	SELECT SUBSTRING($1,1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.split_date_range( TEXT ) RETURNS TEXT AS $func$
	SELECT REGEXP_REPLACE( $1, E'(\\d{4})-(\\d{4})', E'\\1 \\2', 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

-- And ... a table in which to register them

CREATE TABLE config.index_normalizer (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	UNIQUE NOT NULL,
	description	TEXT,
	func		TEXT	NOT NULL,
	param_count	INT	NOT NULL DEFAULT 0
);

CREATE TABLE config.metabib_field_index_norm_map (
	id	SERIAL	PRIMARY KEY,
	field	INT	NOT NULL REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	norm	INT	NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	params	TEXT,
	pos	INT	NOT NULL DEFAULT 0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'NACO Normalize',
	'Apply NACO normalization rules to the extracted text.  See http://www.loc.gov/catdir/pcc/naco/normrule-2.html for details.',
	'naco_normalize',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Normalize date range',
	'Split date ranges in the form of "XXXX-YYYY" into "XXXX YYYY" for proper index.',
	'split_date_range',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'NACO Normalize -- retain first comma',
	'Apply NACO normalization rules to the extracted text, retaining the first comma.  See http://www.loc.gov/catdir/pcc/naco/normrule-2.html for details.',
	'naco_normalize_keep_comma',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Strip Diacritics',
	'Convert text to NFD form and remove non-spacing combining marks.',
	'remove_diacritics',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Up-case',
	'Convert text upper case.',
	'uppercase',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Down-case',
	'Convert text lower case.',
	'lowercase',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Extract Dewey-like number',
	'Extract a string of numeric characters ther resembles a DDC number.',
	'call_number_dewey',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Left truncation',
	'Discard the specified number of characters from the left side of the string.',
	'left_trunc',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Right truncation',
	'Include only the specified number of characters from the left side of the string.',
	'right_trunc',
	1
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'First word',
	'Include only the first space-separated word of a string.',
	'first_word',
	0
);

INSERT INTO config.metabib_field_index_norm_map (field,norm)
	SELECT	m.id,
		i.id
	  FROM	config.metabib_field m,
		config.index_normalizer i
	  WHERE	i.func IN ('naco_normalize','split_date_range');

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
BEGIN

    value := NEW.value;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
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

        NEW.value := value;
    END IF;

    IF NEW.index_vector = ''::tsvector THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
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
    END IF;

    IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT > 8.2 THEN
        NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0], value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT  ARRAY_TO_STRING(
                oils_xpath(
                    $1 ||
                        CASE WHEN $1 ~ $re$/[^/[]*@[^]]+$$re$ OR $1 ~ $re$text\(\)$$re$ THEN '' ELSE '//text()' END,
                    $2,
                    $4
                ),
                $3
            );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, $3, '{}'::TEXT[] );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '', $3 );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oils_xpath_string ( TEXT, TEXT ) RETURNS TEXT AS $func$
    SELECT oils_xpath_string( $1, $2, '{}'::TEXT[] );
$func$ LANGUAGE SQL IMMUTABLE;

CREATE TYPE metabib.field_entry_template AS (
        field_class     TEXT,
        field           INT,
        source          BIGINT,
        value           TEXT
);

CREATE OR REPLACE FUNCTION oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
  use strict;

  use XML::LibXSLT;
  use XML::LibXML;

  my $doc = shift;
  my $xslt = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  my $xslt_parser = $_SHARED{'_xslt_process'}{parsers}{xslt} || XML::LibXSLT->new();

  # Cache the XSLT processor, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xslt} = $xslt_parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xslt});

  my $stylesheet = $_SHARED{'_xslt_process'}{stylesheets}{$xslt} ||
    $xslt_parser->parse_stylesheet( $parser->parse_string($xslt) );

  $_SHARED{'_xslt_process'}{stylesheets}{$xslt} = $stylesheet
    unless ($_SHARED{'_xslt_process'}{stylesheets}{$xslt});

  return $stylesheet->output_string(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- Add two columns so that the following function will compile.
-- Eventually the label column will be NOT NULL, but not yet.
ALTER TABLE config.metabib_field ADD COLUMN label TEXT;
ALTER TABLE config.metabib_field ADD COLUMN facet_xpath TEXT;

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( rid BIGINT, default_joiner TEXT ) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    output_row  metabib.field_entry_template%ROWTYPE;
BEGIN

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field ORDER BY format LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM explode_array(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            curr_text := ARRAY_TO_STRING(
                oils_xpath( '//text()',
                    REGEXP_REPLACE( -- This escapes all &s not followed by "amp;".  Data ise returned from oils_xpath (above) in UTF-8, not entity encoded
                        REGEXP_REPLACE( -- This escapes embeded <s
                            xml_node,
                            $re$(>[^<]+)(<)([^>]+<)$re$,
                            E'\\1&lt;\\3',
                            'g'
                        ),
                        '&(?!amp;)',
                        '&amp;',
                        'g'
                    )
                ),
                ' '
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                RETURN NEXT output_row;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            RETURN NEXT output_row;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;

-- default to a space joiner
CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry ( BIGINT ) RETURNS SETOF metabib.field_entry_template AS $func$
	SELECT * FROM biblio.extract_metabib_field_entry($1, ' ');
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( TEXT ) RETURNS SETOF metabib.full_rec AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
    if ($f->is_control_field) {
        return_next({ tag => $f->tag, value => $f->data });
    } else {
        for my $s ($f->subfields) {
            return_next({
                tag      => $f->tag,
                ind1     => $f->indicator(1),
                ind2     => $f->indicator(2),
                subfield => $s->[0],
                value    => $s->[1]
            });

            if ( $f->tag eq '245' and $s->[0] eq 'a' ) {
                my $trim = $f->indicator(2) || 0;
                return_next({
                    tag      => 'tnf',
                    ind1     => $f->indicator(1),
                    ind2     => $f->indicator(2),
                    subfield => 'a',
                    value    => substr( $s->[1], $trim )
                });
            }
        }
    }
}

return undef;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION biblio.flatten_marc ( rid BIGINT ) RETURNS SETOF metabib.full_rec AS $func$
DECLARE
    bib biblio.record_entry%ROWTYPE;
    output  metabib.full_rec%ROWTYPE;
    field   RECORD;
BEGIN
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    FOR field IN SELECT * FROM biblio.flatten_marc( bib.marc ) LOOP
        output.record := rid;
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL AND field.tag NOT IN ('020','022','024') THEN -- exclude standard numbers and control fields
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        CONTINUE WHEN output.value IS NULL;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- functions to create auditor objects

CREATE FUNCTION auditor.create_auditor_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE SEQUENCE auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            LIKE $$ || sch || $$.$$ || tbl || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history
                SELECT	nextval('auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    OLD.*;
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
            AFTER UPDATE OR DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
            EXECUTE PROCEDURE auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE VIEW auditor.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	auditor.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS auditor.create_auditor (TEXT, TEXT);

-- The main event

CREATE FUNCTION auditor.create_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    PERFORM auditor.create_auditor_seq(sch, tbl);
    PERFORM auditor.create_auditor_history(sch, tbl);
    PERFORM auditor.create_auditor_func(sch, tbl);
    PERFORM auditor.create_auditor_update_trigger(sch, tbl);
    PERFORM auditor.create_auditor_lifecycle(sch, tbl);
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

ALTER TABLE action.hold_request ADD COLUMN cut_in_line BOOL;

ALTER TABLE action.hold_request
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE action.hold_request
ADD COLUMN shelf_expire_time TIMESTAMPTZ;

ALTER TABLE action.hold_request DROP CONSTRAINT hold_request_current_copy_fkey;

ALTER TABLE action.hold_request DROP CONSTRAINT hold_request_hold_type_check;

UPDATE config.index_normalizer SET param_count = 0 WHERE func = 'split_date_range';

CREATE INDEX actor_usr_usrgroup_idx ON actor.usr (usrgroup);

-- Add claims_never_checked_out_count to actor.usr, related history

ALTER TABLE actor.usr ADD COLUMN
	claims_never_checked_out_count  INT         NOT NULL DEFAULT 0;

ALTER TABLE AUDITOR.actor_usr_history ADD COLUMN 
	claims_never_checked_out_count INT;

DROP VIEW IF EXISTS auditor.actor_usr_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'actor', 'usr' );

-----------

CREATE OR REPLACE FUNCTION action.circulation_claims_returned () RETURNS TRIGGER AS $$
BEGIN
	IF OLD.stop_fines IS NULL OR OLD.stop_fines <> NEW.stop_fines THEN
		IF NEW.stop_fines = 'CLAIMSRETURNED' THEN
			UPDATE actor.usr SET claims_returned_count = claims_returned_count + 1 WHERE id = NEW.usr;
		END IF;
		IF NEW.stop_fines = 'CLAIMSNEVERCHECKEDOUT' THEN
			UPDATE actor.usr SET claims_never_checked_out_count = claims_never_checked_out_count + 1 WHERE id = NEW.usr;
		END IF;
		IF NEW.stop_fines = 'LOST' THEN
			UPDATE asset.copy SET status = 3 WHERE id = NEW.target_copy;
		END IF;
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- Create new table acq.fund_allocation_percent
-- Populate it from acq.fund_allocation
-- Convert all percentages to amounts in acq.fund_allocation

CREATE TABLE acq.fund_allocation_percent
(
    id                   SERIAL            PRIMARY KEY,
    funding_source       INT               NOT NULL REFERENCES acq.funding_source
                                               DEFERRABLE INITIALLY DEFERRED,
    org                  INT               NOT NULL REFERENCES actor.org_unit
                                               DEFERRABLE INITIALLY DEFERRED,
    fund_code            TEXT,
    percent              NUMERIC           NOT NULL,
    allocator            INTEGER           NOT NULL REFERENCES actor.usr
                                               DEFERRABLE INITIALLY DEFERRED,
    note                 TEXT,
    create_time          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    CONSTRAINT logical_key UNIQUE( funding_source, org, fund_code ),
    CONSTRAINT percentage_range CHECK( percent >= 0 AND percent <= 100 )
);

-- Trigger function to validate combination of org_unit and fund_code

CREATE OR REPLACE FUNCTION acq.fund_alloc_percent_val()
RETURNS TRIGGER AS $$
--
DECLARE
--
dummy int := 0;
--
BEGIN
    SELECT
        1
    INTO
        dummy
    FROM
        acq.fund
    WHERE
        org = NEW.org
        AND code = NEW.fund_code
        LIMIT 1;
    --
    IF dummy = 1 then
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'No fund exists for org % and code %', NEW.org, NEW.fund_code;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acq_fund_alloc_percent_val_trig
    BEFORE INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fund_alloc_percent_val();

CREATE OR REPLACE FUNCTION acq.fap_limit_100()
RETURNS TRIGGER AS $$
DECLARE
--
total_percent numeric;
--
BEGIN
    SELECT
        sum( percent )
    INTO
        total_percent
    FROM
        acq.fund_allocation_percent AS fap
    WHERE
        fap.funding_source = NEW.funding_source;
    --
    IF total_percent > 100 THEN
        RAISE EXCEPTION 'Total percentages exceed 100 for funding_source %',
            NEW.funding_source;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acqfap_limit_100_trig
    AFTER INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fap_limit_100();

-- Populate new table from acq.fund_allocation

INSERT INTO acq.fund_allocation_percent
(
    funding_source,
    org,
    fund_code,
    percent,
    allocator,
    note,
    create_time
)
    SELECT
        fa.funding_source,
        fund.org,
        fund.code,
        fa.percent,
        fa.allocator,
        fa.note,
        fa.create_time
    FROM
        acq.fund_allocation AS fa
            INNER JOIN acq.fund AS fund
                ON ( fa.fund = fund.id )
    WHERE
        fa.percent is not null
    ORDER BY
        fund.org;

-- Temporary function to convert percentages to amounts in acq.fund_allocation

-- Algorithm to apply to each funding source:

-- 1. Add up the credits.
-- 2. Add up the percentages.
-- 3. Multiply the sum of the percentages times the sum of the credits.  Drop any
--    fractional cents from the result.  This is the total amount to be allocated.
-- 4. For each allocation: multiply the percentage by the total allocation.  Drop any
--    fractional cents to get a preliminary amount.
-- 5. Add up the preliminary amounts for all the allocations.
-- 6. Subtract the results of step 5 from the result of step 3.  The difference is the
--    number of residual cents (resulting from having dropped fractional cents) that
--    must be distributed across the funds in order to make the total of the amounts
--    match the total allocation.
-- 7. Make a second pass through the allocations, in decreasing order of the fractional
--    cents that were dropped from their amounts in step 4.  Add one cent to the amount
--    for each successive fund, until all the residual cents have been exhausted.

-- Result: the sum of the individual allocations now equals the total to be allocated,
-- to the penny.  The individual amounts match the percentages as closely as possible,
-- given the constraint that the total must match.

CREATE OR REPLACE FUNCTION acq.apply_percents()
RETURNS VOID AS $$
declare
--
tot              RECORD;
fund             RECORD;
tot_cents        INTEGER;
src              INTEGER;
id               INTEGER[];
curr_id          INTEGER;
pennies          NUMERIC[];
curr_amount      NUMERIC;
i                INTEGER;
total_of_floors  INTEGER;
total_percent    NUMERIC;
total_allocation INTEGER;
residue          INTEGER;
--
begin
	RAISE NOTICE 'Applying percents';
	FOR tot IN
		SELECT
			fsrc.funding_source,
			sum( fsrc.amount ) AS total
		FROM
			acq.funding_source_credit AS fsrc
		WHERE fsrc.funding_source IN
			( SELECT DISTINCT fa.funding_source
			  FROM acq.fund_allocation AS fa
			  WHERE fa.percent IS NOT NULL )
		GROUP BY
			fsrc.funding_source
	LOOP
		tot_cents = floor( tot.total * 100 );
		src = tot.funding_source;
		RAISE NOTICE 'Funding source % total %',
			src, tot_cents;
		i := 0;
		total_of_floors := 0;
		total_percent := 0;
		--
		FOR fund in
			SELECT
				fa.id,
				fa.percent,
				floor( fa.percent * tot_cents / 100 ) as floor_pennies
			FROM
				acq.fund_allocation AS fa
			WHERE
				fa.funding_source = src
				AND fa.percent IS NOT NULL
			ORDER BY
				mod( fa.percent * tot_cents / 100, 1 ),
				fa.fund,
				fa.id
		LOOP
			RAISE NOTICE '   %: %',
				fund.id,
				fund.floor_pennies;
			i := i + 1;
			id[i] = fund.id;
			pennies[i] = fund.floor_pennies;
			total_percent := total_percent + fund.percent;
			total_of_floors := total_of_floors + pennies[i];
		END LOOP;
		total_allocation := floor( total_percent * tot_cents /100 );
		RAISE NOTICE 'Total before distributing residue: %', total_of_floors;
		residue := total_allocation - total_of_floors;
		RAISE NOTICE 'Residue: %', residue;
		--
		-- Post the calculated amounts, revising as needed to
		-- distribute the rounding error
		--
		WHILE i > 0 LOOP
			IF residue > 0 THEN
				pennies[i] = pennies[i] + 1;
				residue := residue - 1;
			END IF;
			--
			-- Post amount
			--
			curr_id     := id[i];
			curr_amount := trunc( pennies[i] / 100, 2 );
			--
			UPDATE
				acq.fund_allocation AS fa
			SET
				amount = curr_amount,
				percent = NULL
			WHERE
				fa.id = curr_id;
			--
			RAISE NOTICE '   ID % and amount %',
				curr_id,
				curr_amount;
			i = i - 1;
		END LOOP;
	END LOOP;
end;
$$ LANGUAGE 'plpgsql';

-- Run the temporary function

select * from acq.apply_percents();

-- Drop the temporary function now that we're done with it

DROP FUNCTION IF EXISTS acq.apply_percents();

-- Eliminate acq.fund_allocation.percent, which has been moved to the acq.fund_allocation_percent table.

-- If the following step fails, it's probably because there are still some non-null percent values in
-- acq.fund_allocation.  They should have all been converted to amounts, and then set to null, by a
-- previous upgrade step based on 0049.schema.acq_funding_allocation_percent.sql.  If there are any
-- non-null values, then either that step didn't run, or it didn't work, or some non-null values
-- slipped in afterwards.

-- To convert any remaining percents to amounts: create, run, and then drop the temporary stored
-- procedure acq.apply_percents() as defined above.

ALTER TABLE acq.fund_allocation
ALTER COLUMN amount SET NOT NULL;

CREATE OR REPLACE VIEW acq.fund_allocation_total AS
    SELECT  fund,
            SUM(a.amount * acq.exchange_ratio(s.currency_type, f.currency_type))::NUMERIC(100,2) AS amount
    FROM acq.fund_allocation a
         JOIN acq.fund f ON (a.fund = f.id)
         JOIN acq.funding_source s ON (a.funding_source = s.id)
    GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_allocation_total AS
    SELECT  funding_source,
            SUM(a.amount)::NUMERIC(100,2) AS amount
    FROM  acq.fund_allocation a
    GROUP BY 1;

ALTER TABLE acq.fund_allocation
DROP COLUMN percent;

CREATE TABLE asset.copy_location_order
(
	id              SERIAL           PRIMARY KEY,
	location        INT              NOT NULL
	                                     REFERENCES asset.copy_location
	                                     ON DELETE CASCADE
	                                     DEFERRABLE INITIALLY DEFERRED,
	org             INT              NOT NULL
	                                     REFERENCES actor.org_unit
	                                     ON DELETE CASCADE
	                                     DEFERRABLE INITIALLY DEFERRED,
	position        INT              NOT NULL DEFAULT 0,
	CONSTRAINT acplo_once_per_org UNIQUE ( location, org )
);

ALTER TABLE money.credit_card_payment ADD COLUMN cc_processor TEXT;

-- If you ran this before its most recent incarnation:
-- delete from config.upgrade_log where version = '0328';
-- alter table money.credit_card_payment drop column cc_name;

ALTER TABLE money.credit_card_payment ADD COLUMN cc_first_name TEXT;
ALTER TABLE money.credit_card_payment ADD COLUMN cc_last_name TEXT;

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS config.circ_matrix_matchpoint AS $func$
DECLARE
    current_group    permission.grp_tree%ROWTYPE;
    user_object    actor.usr%ROWTYPE;
    item_object    asset.copy%ROWTYPE;
    cn_object    asset.call_number%ROWTYPE;
    rec_descriptor    metabib.rec_descriptor%ROWTYPE;
    current_mp    config.circ_matrix_matchpoint%ROWTYPE;
    matchpoint    config.circ_matrix_matchpoint%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
    SELECT INTO cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r JOIN asset.call_number c USING (record) WHERE c.id = item_object.call_number;
    SELECT INTO current_group * FROM permission.grp_tree WHERE id = user_object.profile;

    LOOP 
        -- for each potential matchpoint for this ou and group ...
        FOR current_mp IN
            SELECT  m.*
              FROM  config.circ_matrix_matchpoint m
                    JOIN actor.org_unit_ancestors( context_ou ) d ON (m.org_unit = d.id)
                    LEFT JOIN actor.org_unit_proximity p ON (p.from_org = context_ou AND p.to_org = d.id)
              WHERE m.grp = current_group.id
                    AND m.active
                    AND (m.copy_owning_lib IS NULL OR cn_object.owning_lib IN ( SELECT id FROM actor.org_unit_descendants(m.copy_owning_lib) ))
                    AND (m.copy_circ_lib   IS NULL OR item_object.circ_lib IN ( SELECT id FROM actor.org_unit_descendants(m.copy_circ_lib)   ))
              ORDER BY    CASE WHEN p.prox        IS NULL THEN 999 ELSE p.prox END,
                    CASE WHEN m.copy_owning_lib IS NOT NULL
                        THEN 256 / ( SELECT COALESCE(prox, 255) + 1 FROM actor.org_unit_proximity WHERE to_org = cn_object.owning_lib AND from_org = m.copy_owning_lib LIMIT 1 )
                        ELSE 0
                    END +
                    CASE WHEN m.copy_circ_lib IS NOT NULL
                        THEN 256 / ( SELECT COALESCE(prox, 255) + 1 FROM actor.org_unit_proximity WHERE to_org = item_object.circ_lib AND from_org = m.copy_circ_lib LIMIT 1 )
                        ELSE 0
                    END +
                    CASE WHEN m.is_renewal = renewal        THEN 128 ELSE 0 END +
                    CASE WHEN m.juvenile_flag    IS NOT NULL THEN 64 ELSE 0 END +
                    CASE WHEN m.circ_modifier    IS NOT NULL THEN 32 ELSE 0 END +
                    CASE WHEN m.marc_type        IS NOT NULL THEN 16 ELSE 0 END +
                    CASE WHEN m.marc_form        IS NOT NULL THEN 8 ELSE 0 END +
                    CASE WHEN m.marc_vr_format    IS NOT NULL THEN 4 ELSE 0 END +
                    CASE WHEN m.ref_flag        IS NOT NULL THEN 2 ELSE 0 END +
                    CASE WHEN m.usr_age_lower_bound    IS NOT NULL THEN 0.5 ELSE 0 END +
                    CASE WHEN m.usr_age_upper_bound    IS NOT NULL THEN 0.5 ELSE 0 END DESC LOOP

            IF current_mp.is_renewal IS NOT NULL THEN
                CONTINUE WHEN current_mp.is_renewal <> renewal;
            END IF;

            IF current_mp.circ_modifier IS NOT NULL THEN
                CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier OR item_object.circ_modifier IS NULL;
            END IF;

            IF current_mp.marc_type IS NOT NULL THEN
                IF item_object.circ_as_type IS NOT NULL THEN
                    CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
                ELSE
                    CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
                END IF;
            END IF;

            IF current_mp.marc_form IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
            END IF;

            IF current_mp.marc_vr_format IS NOT NULL THEN
                CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
            END IF;

            IF current_mp.ref_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
            END IF;

            IF current_mp.juvenile_flag IS NOT NULL THEN
                CONTINUE WHEN current_mp.juvenile_flag <> user_object.juvenile;
            END IF;

            IF current_mp.usr_age_lower_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_lower_bound < age(user_object.dob);
            END IF;

            IF current_mp.usr_age_upper_bound IS NOT NULL THEN
                CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_upper_bound > age(user_object.dob);
            END IF;


            -- everything was undefined or matched
            matchpoint = current_mp;

            EXIT WHEN matchpoint.id IS NOT NULL;
        END LOOP;

        EXIT WHEN current_group.parent IS NULL OR matchpoint.id IS NOT NULL;

        SELECT INTO current_group * FROM permission.grp_tree WHERE id = current_group.parent;
    END LOOP;

    RETURN matchpoint;
END;
$func$ LANGUAGE plpgsql;

CREATE TYPE action.hold_stats AS (
    hold_count              INT,
    copy_count              INT,
    available_count         INT,
    total_copy_ratio        FLOAT,
    available_copy_ratio    FLOAT
);

CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id INT) RETURNS action.hold_stats AS $func$
DECLARE
    output          action.hold_stats%ROWTYPE;
    hold_count      INT := 0;
    copy_count      INT := 0;
    available_count INT := 0;
    hold_map_data   RECORD;
BEGIN

    output.hold_count := 0;
    output.copy_count := 0;
    output.available_count := 0;

    SELECT  COUNT( DISTINCT m.hold ) INTO hold_count
      FROM  action.hold_copy_map m
            JOIN action.hold_request h ON (m.hold = h.id)
      WHERE m.target_copy = copy_id
            AND NOT h.frozen;

    output.hold_count := hold_count;

    IF output.hold_count > 0 THEN
        FOR hold_map_data IN
            SELECT  DISTINCT m.target_copy,
                    acp.status
              FROM  action.hold_copy_map m
                    JOIN asset.copy acp ON (m.target_copy = acp.id)
                    JOIN action.hold_request h ON (m.hold = h.id)
              WHERE m.hold IN ( SELECT DISTINCT hold FROM action.hold_copy_map WHERE target_copy = copy_id ) AND NOT h.frozen
        LOOP
            output.copy_count := output.copy_count + 1;
            IF hold_map_data.status IN (0,7,12) THEN
                output.available_count := output.available_count + 1;
            END IF;
        END LOOP;
        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        output.available_copy_ratio = output.available_count::FLOAT / output.hold_count::FLOAT;

    END IF;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN total_copy_hold_ratio FLOAT;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN available_copy_hold_ratio FLOAT;

ALTER TABLE config.circ_matrix_matchpoint DROP CONSTRAINT ep_once_per_grp_loc_mod_marc;

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN copy_circ_lib   INT REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN copy_owning_lib INT REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE config.circ_matrix_matchpoint ADD CONSTRAINT ep_once_per_grp_loc_mod_marc UNIQUE (
    grp, org_unit, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag,
    juvenile_flag, usr_age_lower_bound, usr_age_upper_bound, is_renewal, copy_circ_lib,
    copy_owning_lib
);

-- Return the correct fail_part when the item can't be found
CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    user_object        actor.usr%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_status_object    config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result            action.matrix_test_result;
    circ_test        config.circ_matrix_matchpoint%ROWTYPE;
    out_by_circ_mod        config.circ_matrix_circ_mod_test%ROWTYPE;
    circ_mod_map        config.circ_matrix_circ_mod_test_map%ROWTYPE;
    hold_ratio          action.hold_stats%ROWTYPE;
    penalty_type         TEXT;
    tmp_grp         INT;
    items_out        INT;
    context_org_list        INT[];
    done            BOOL := FALSE;
BEGIN
    result.success := TRUE;

    -- Fail if the user is BARRED
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Fail if we couldn't find the user 
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, match_item, match_user, renewal);
    result.matchpoint := circ_test.id;

    -- Fail if we couldn't find a matchpoint
    IF result.matchpoint IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

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

    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( circ_test.org_unit );

    -- Fail if the test is set to hard non-circulating
    IF circ_test.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_test.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_test.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_test.available_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_test.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

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

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the user has too many items with specific circ_modifiers checked out
    FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = circ_test.id LOOP
        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
            JOIN asset.copy cp ON (cp.id = circ.target_copy)
          WHERE circ.usr = match_user
               AND circ.circ_lib IN ( SELECT * FROM unnest(context_org_list) )
            AND circ.checkin_time IS NULL
            AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
            AND cp.circ_modifier IN (SELECT circ_mod FROM config.circ_matrix_circ_mod_test_map WHERE circ_mod_test = out_by_circ_mod.id);
        IF items_out >= out_by_circ_mod.items_out THEN
            result.fail_part := 'config.circ_matrix_circ_mod_test';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END LOOP;

    -- If we passed everything, return the successful matchpoint id
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE TABLE config.remote_account (
    id          SERIAL  PRIMARY KEY,
    label       TEXT    NOT NULL,
    host        TEXT    NOT NULL,   -- name or IP, :port optional
    username    TEXT,               -- optional, since we could default to $USER
    password    TEXT,               -- optional, since we could use SSH keys, or anonymous login.
    account     TEXT,               -- aka profile or FTP "account" command
    path        TEXT,               -- aka directory
    owner       INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    last_activity TIMESTAMP WITH TIME ZONE
);

CREATE TABLE acq.edi_account (      -- similar tables can extend remote_account for other parts of EG
    provider    INT     NOT NULL REFERENCES acq.provider          (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    in_dir      TEXT,   -- incoming messages dir (probably different than config.remote_account.path, the outgoing dir)
	vendcode    TEXT,
	vendacct    TEXT

) INHERITS (config.remote_account);

ALTER TABLE acq.edi_account ADD PRIMARY KEY (id);

CREATE TABLE acq.claim_type (
	id             SERIAL           PRIMARY KEY,
	org_unit       INT              NOT NULL REFERENCES actor.org_unit(id)
	                                         DEFERRABLE INITIALLY DEFERRED,
	code           TEXT             NOT NULL,
	description    TEXT             NOT NULL,
	CONSTRAINT claim_type_once_per_org UNIQUE ( org_unit, code )
);

CREATE TABLE acq.claim (
	id             SERIAL           PRIMARY KEY,
	type           INT              NOT NULL REFERENCES acq.claim_type
	                                         DEFERRABLE INITIALLY DEFERRED,
	lineitem_detail BIGINT          NOT NULL REFERENCES acq.lineitem_detail
	                                         DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE acq.claim_policy (
	id              SERIAL       PRIMARY KEY,
	org_unit        INT          NOT NULL REFERENCES actor.org_unit
	                             DEFERRABLE INITIALLY DEFERRED,
	name            TEXT         NOT NULL,
	description     TEXT         NOT NULL,
	CONSTRAINT name_once_per_org UNIQUE (org_unit, name)
);

-- Add a san column for EDI. 
-- See: http://isbn.org/standards/home/isbn/us/san/san-qa.asp

ALTER TABLE acq.provider ADD COLUMN san INT;

ALTER TABLE acq.provider ALTER COLUMN san TYPE TEXT USING lpad(text(san), 7, '0');

-- null edi_default is OK... it has to be, since we have no values in acq.edi_account yet
ALTER TABLE acq.provider ADD COLUMN edi_default INT REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.provider
	ADD COLUMN active BOOL NOT NULL DEFAULT TRUE;

ALTER TABLE acq.provider
	ADD COLUMN prepayment_required BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE acq.provider
	ADD COLUMN url TEXT;

ALTER TABLE acq.provider
	ADD COLUMN email TEXT;

ALTER TABLE acq.provider
	ADD COLUMN phone TEXT;

ALTER TABLE acq.provider
	ADD COLUMN fax_phone TEXT;

ALTER TABLE acq.provider
	ADD COLUMN default_claim_policy INT
		REFERENCES acq.claim_policy
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.transit_copy
ADD COLUMN prev_dest INTEGER REFERENCES actor.org_unit( id )
							 DEFERRABLE INITIALLY DEFERRED;

DROP SCHEMA IF EXISTS booking CASCADE;

CREATE SCHEMA booking;

CREATE TABLE booking.resource_type (
	id             SERIAL          PRIMARY KEY,
	name           TEXT            NOT NULL,
	fine_interval  INTERVAL,
	fine_amount    DECIMAL(8,2)    NOT NULL DEFAULT 0,
	owner          INT             NOT NULL
	                               REFERENCES actor.org_unit( id )
	                               DEFERRABLE INITIALLY DEFERRED,
	catalog_item   BOOLEAN         NOT NULL DEFAULT FALSE,
	transferable   BOOLEAN         NOT NULL DEFAULT FALSE,
    record         BIGINT          REFERENCES biblio.record_entry (id)
	                               DEFERRABLE INITIALLY DEFERRED,
    max_fine       NUMERIC(8,2),
    elbow_room     INTERVAL,
    CONSTRAINT brt_name_and_record_once_per_owner UNIQUE(owner, name, record)
);

CREATE TABLE booking.resource (
	id             SERIAL           PRIMARY KEY,
	owner          INT              NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	type           INT              NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	overbook       BOOLEAN          NOT NULL DEFAULT FALSE,
	barcode        TEXT             NOT NULL,
	deposit        BOOLEAN          NOT NULL DEFAULT FALSE,
	deposit_amount DECIMAL(8,2)     NOT NULL DEFAULT 0.00,
	user_fee       DECIMAL(8,2)     NOT NULL DEFAULT 0.00,
	CONSTRAINT br_unique UNIQUE (owner, barcode)
);

-- For non-catalog items: hijack barcode for name/description

CREATE TABLE booking.resource_attr (
	id              SERIAL          PRIMARY KEY,
	owner           INT             NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	name            TEXT            NOT NULL,
	resource_type   INT             NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	required        BOOLEAN         NOT NULL DEFAULT FALSE,
	CONSTRAINT bra_name_once_per_type UNIQUE(resource_type, name)
);

CREATE TABLE booking.resource_attr_value (
	id               SERIAL         PRIMARY KEY,
	owner            INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	attr             INT            NOT NULL
	                                REFERENCES booking.resource_attr(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	valid_value      TEXT           NOT NULL,
	CONSTRAINT brav_logical_key UNIQUE(owner, attr, valid_value)
);

CREATE TABLE booking.resource_attr_map (
	id               SERIAL         PRIMARY KEY,
	resource         INT            NOT NULL
	                                REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	resource_attr    INT            NOT NULL
	                                REFERENCES booking.resource_attr(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	value            INT            NOT NULL
	                                REFERENCES booking.resource_attr_value(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT bram_one_value_per_attr UNIQUE(resource, resource_attr)
);

CREATE TABLE booking.reservation (
	request_time     TIMESTAMPTZ   NOT NULL DEFAULT now(),
	start_time       TIMESTAMPTZ,
	end_time         TIMESTAMPTZ,
	capture_time     TIMESTAMPTZ,
	cancel_time      TIMESTAMPTZ,
	pickup_time      TIMESTAMPTZ,
	return_time      TIMESTAMPTZ,
	booking_interval INTERVAL,
	fine_interval    INTERVAL,
	fine_amount      DECIMAL(8,2),
	target_resource_type  INT       NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	target_resource  INT            REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	current_resource INT            REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	request_lib      INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	pickup_lib       INT            REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	capture_staff    INT            REFERENCES actor.usr(id)
	                                DEFERRABLE INITIALLY DEFERRED,
    max_fine         NUMERIC(8,2)
) INHERITS (money.billable_xact);

ALTER TABLE booking.reservation ADD PRIMARY KEY (id);

ALTER TABLE booking.reservation
	ADD CONSTRAINT booking_reservation_usr_fkey
	FOREIGN KEY (usr) REFERENCES actor.usr (id)
	DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE booking.reservation_attr_value_map (
	id               SERIAL         PRIMARY KEY,
	reservation      INT            NOT NULL
	                                REFERENCES booking.reservation(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	attr_value       INT            NOT NULL
	                                REFERENCES booking.resource_attr_value(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT bravm_logical_key UNIQUE(reservation, attr_value)
);

-- represents a circ chain summary
CREATE TYPE action.circ_chain_summary AS (
    num_circs INTEGER,
    start_time TIMESTAMP WITH TIME ZONE,
    checkout_workstation TEXT,
    last_renewal_time TIMESTAMP WITH TIME ZONE, -- NULL if no renewals
    last_stop_fines TEXT,
    last_stop_fines_time TIMESTAMP WITH TIME ZONE,
    last_renewal_workstation TEXT, -- NULL if no renewals
    last_checkin_workstation TEXT,
    last_checkin_time TIMESTAMP WITH TIME ZONE,
    last_checkin_scan_time TIMESTAMP WITH TIME ZONE
);

CREATE OR REPLACE FUNCTION action.circ_chain ( ctx_circ_id INTEGER ) RETURNS SETOF action.circulation AS $$
DECLARE
    tmp_circ action.circulation%ROWTYPE;
    circ_0 action.circulation%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.circulation WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.circulation WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.circulation WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_circ_chain ( ctx_circ_id INTEGER ) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.circulation%ROWTYPE;

    -- last circ in the chain
    circ_n action.circulation%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.circulation%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('reservation');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();

ALTER TABLE config.standing_penalty
	ADD COLUMN org_depth   INTEGER;

CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row          actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row     actor.usr_standing_penalty%ROWTYPE;
    collections_fines   permission.grp_penalty_threshold%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp             INT;
    items_overdue       INT;
    items_out           INT;
    context_org_list    INT[];
    current_fines        NUMERIC(8,2) := 0.0;
    tmp_fines            NUMERIC(8,2);
    tmp_groc            RECORD;
    tmp_circ            RECORD;
    tmp_org             actor.org_unit%ROWTYPE;
    tmp_penalty         config.standing_penalty%ROWTYPE;
    tmp_depth           INTEGER;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Max fines
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a high fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 1 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 1;

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 1;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max overdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many overdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_overdue FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 2 AND org_unit = tmp_org.id;

            IF max_overdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_overdue.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_overdue.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_overdue.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 2;

        SELECT  INTO items_overdue COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_overdue.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND circ.due_date < NOW()
            AND (circ.stop_fines = 'MAXFINES' OR circ.stop_fines IS NULL);

        IF items_overdue >= max_overdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_overdue.org_unit;
            new_sp_row.standing_penalty := 2;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max out
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many checked out items
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_items_out FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 3 AND org_unit = tmp_org.id;

            IF max_items_out.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_items_out.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;


    -- Fail if the user has too many items checked out
    IF max_items_out.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_items_out.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 3;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL);

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    -- Start over for collections warning
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a collections-level fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 4 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        RETURN QUERY
            SELECT  *
              FROM  actor.usr_standing_penalty
              WHERE usr = match_user
                    AND org_unit = max_fines.org_unit
                    AND (stop_date IS NULL or stop_date > NOW())
                    AND standing_penalty = 4;

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for in collections
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Remove the in-collections penalty if the user has paid down enough
    -- This penalty is different, because this code is not responsible for creating 
    -- new in-collections penalties, only for removing them
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 30 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( max_fines.org_unit );

        -- first, see if the user had paid down to the threshold
        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                      WHERE r.usr = match_user
                            AND r.pickup_lib IN (SELECT * FROM unnest(context_org_list))
                            AND r.xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                      WHERE g.usr = match_user
                            AND g.billing_location IN (SELECT * FROM unnest(context_org_list))
                            AND g.xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                      WHERE circ.usr = match_user
                            AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                            AND circ.xact_finish IS NULL ) l USING (id);

        IF current_fines IS NULL OR current_fines <= max_fines.threshold THEN
            -- patron has paid down enough

            SELECT INTO tmp_penalty * FROM config.standing_penalty WHERE id = 30;

            IF tmp_penalty.org_depth IS NOT NULL THEN

                -- since this code is not responsible for applying the penalty, it can't 
                -- guarantee the current context org will match the org at which the penalty 
                --- was applied.  search up the org tree until we hit the configured penalty depth
                SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;
                SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;

                WHILE tmp_depth >= tmp_penalty.org_depth LOOP

                    RETURN QUERY
                        SELECT  *
                          FROM  actor.usr_standing_penalty
                          WHERE usr = match_user
                                AND org_unit = tmp_org.id
                                AND (stop_date IS NULL or stop_date > NOW())
                                AND standing_penalty = 30;

                    IF tmp_org.parent_ou IS NULL THEN
                        EXIT;
                    END IF;

                    SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;
                    SELECT INTO tmp_depth depth FROM actor.org_unit_type WHERE id = tmp_org.ou_type;
                END LOOP;

            ELSE

                -- no penalty depth is defined, look for exact matches

                RETURN QUERY
                    SELECT  *
                      FROM  actor.usr_standing_penalty
                      WHERE usr = match_user
                            AND org_unit = max_fines.org_unit
                            AND (stop_date IS NULL or stop_date > NOW())
                            AND standing_penalty = 30;
            END IF;
    
        END IF;

    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

-- Create a default row in acq.fiscal_calendar
-- Add a column in actor.org_unit to point to it

INSERT INTO acq.fiscal_calendar ( id, name ) VALUES ( 1, 'Default' );

ALTER TABLE actor.org_unit
ADD COLUMN fiscal_calendar INT NOT NULL
	REFERENCES acq.fiscal_calendar( id )
	DEFERRABLE INITIALLY DEFERRED
	DEFAULT 1;

ALTER TABLE auditor.actor_org_unit_history
	ADD COLUMN fiscal_calendar INT;

DROP VIEW IF EXISTS auditor.actor_org_unit_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'actor', 'org_unit' );

ALTER TABLE acq.funding_source_credit
ADD COLUMN deadline_date TIMESTAMPTZ;

ALTER TABLE acq.funding_source_credit
ADD COLUMN effective_date TIMESTAMPTZ NOT NULL DEFAULT now();

INSERT INTO config.standing_penalty (id,name,label) VALUES (30,'PATRON_IN_COLLECTIONS','Patron has been referred to a collections agency');

CREATE TABLE acq.fund_transfer (
	id               SERIAL         PRIMARY KEY,
	src_fund         INT            NOT NULL REFERENCES acq.fund( id )
	                                DEFERRABLE INITIALLY DEFERRED,
	src_amount       NUMERIC        NOT NULL,
	dest_fund        INT            REFERENCES acq.fund( id )
	                                DEFERRABLE INITIALLY DEFERRED,
	dest_amount      NUMERIC,
	transfer_time    TIMESTAMPTZ    NOT NULL DEFAULT now(),
	transfer_user    INT            NOT NULL REFERENCES actor.usr( id )
	                                DEFERRABLE INITIALLY DEFERRED,
	note             TEXT,
    funding_source_credit INTEGER   NOT NULL
	                                REFERENCES acq.funding_source_credit(id)
	                                DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX acqftr_usr_idx
ON acq.fund_transfer( transfer_user );

COMMENT ON TABLE acq.fund_transfer IS $$
/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
 *
 * Fund Transfer
 *
 * Each row represents the transfer of money from a source fund
 * to a destination fund.  There should be corresponding entries
 * in acq.fund_allocation.  The purpose of acq.fund_transfer is
 * to record how much money moved from which fund to which other
 * fund.
 * 
 * The presence of two amount fields, rather than one, reflects
 * the possibility that the two funds are denominated in different
 * currencies.  If they use the same currency type, the two
 * amounts should be the same.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE TABLE acq.claim_event_type (
	id             SERIAL           PRIMARY KEY,
	org_unit       INT              NOT NULL REFERENCES actor.org_unit(id)
	                                         DEFERRABLE INITIALLY DEFERRED,
	code           TEXT             NOT NULL,
	description    TEXT             NOT NULL,
	library_initiated BOOL          NOT NULL DEFAULT FALSE,
	CONSTRAINT event_type_once_per_org UNIQUE ( org_unit, code )
);

CREATE TABLE acq.claim_event (
	id             BIGSERIAL        PRIMARY KEY,
	type           INT              NOT NULL REFERENCES acq.claim_event_type
	                                         DEFERRABLE INITIALLY DEFERRED,
	claim          SERIAL           NOT NULL REFERENCES acq.claim
	                                         DEFERRABLE INITIALLY DEFERRED,
	event_date     TIMESTAMPTZ      NOT NULL DEFAULT now(),
	creator        INT              NOT NULL REFERENCES actor.usr
	                                         DEFERRABLE INITIALLY DEFERRED,
	note           TEXT
);

CREATE INDEX claim_event_claim_date_idx ON acq.claim_event( claim, event_date );

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
BEGIN

	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
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

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

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

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_purge_data(INT, INT) IS $$
/**
 * Finds rows dependent on a given row in actor.usr and either deletes them
 * or reassigns them to a different user.
 */
$$;

CREATE OR REPLACE FUNCTION actor.usr_delete(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	old_profile actor.usr.profile%type;
	old_home_ou actor.usr.home_ou%type;
	new_profile actor.usr.profile%type;
	new_home_ou actor.usr.home_ou%type;
	new_name    text;
	new_dob     actor.usr.dob%type;
BEGIN
	SELECT
		id || '-PURGED-' || now(),
		profile,
		home_ou,
		dob
	INTO
		new_name,
		old_profile,
		old_home_ou,
		new_dob
	FROM
		actor.usr
	WHERE
		id = src_usr;
	--
	-- Quit if no such user
	--
	IF old_profile IS NULL THEN
		RETURN;
	END IF;
	--
	perform actor.usr_purge_data( src_usr, dest_usr );
	--
	-- Find the root grp_tree and the root org_unit.  This would be simpler if we 
	-- could assume that there is only one root.  Theoretically, someday, maybe,
	-- there could be multiple roots, so we take extra trouble to get the right ones.
	--
	SELECT
		id
	INTO
		new_profile
	FROM
		permission.grp_ancestors( old_profile )
	WHERE
		parent is null;
	--
	SELECT
		id
	INTO
		new_home_ou
	FROM
		actor.org_unit_ancestors( old_home_ou )
	WHERE
		parent_ou is null;
	--
	-- Truncate date of birth
	--
	IF new_dob IS NOT NULL THEN
		new_dob := date_trunc( 'year', new_dob );
	END IF;
	--
	UPDATE
		actor.usr
		SET
			card = NULL,
			profile = new_profile,
			usrname = new_name,
			email = NULL,
			passwd = random()::text,
			standing = DEFAULT,
			ident_type = 
			(
				SELECT MIN( id )
				FROM config.identification_type
			),
			ident_value = NULL,
			ident_type2 = NULL,
			ident_value2 = NULL,
			net_access_level = DEFAULT,
			photo_url = NULL,
			prefix = NULL,
			first_given_name = new_name,
			second_given_name = NULL,
			family_name = new_name,
			suffix = NULL,
			alias = NULL,
			day_phone = NULL,
			evening_phone = NULL,
			other_phone = NULL,
			mailing_address = NULL,
			billing_address = NULL,
			home_ou = new_home_ou,
			dob = new_dob,
			active = FALSE,
			master_account = DEFAULT, 
			super_user = DEFAULT,
			barred = FALSE,
			deleted = TRUE,
			juvenile = DEFAULT,
			usrgroup = 0,
			claims_returned_count = DEFAULT,
			credit_forward_balance = DEFAULT,
			last_xact_id = DEFAULT,
			alert_message = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION actor.usr_delete(INT, INT) IS $$
/**
 * Logically deletes a user.  Removes personally identifiable information,
 * and purges associated data in other tables.
 */
$$;

-- INSERT INTO config.copy_status (id,name) VALUES (15,oils_i18n_gettext(15, 'On reservation shelf', 'ccs', 'name'));

ALTER TABLE acq.fund
ADD COLUMN rollover BOOL NOT NULL DEFAULT FALSE;

ALTER TABLE acq.fund
	ADD COLUMN propagate BOOLEAN NOT NULL DEFAULT TRUE;

-- A fund can't roll over if it doesn't propagate from one year to the next

ALTER TABLE acq.fund
	ADD CONSTRAINT acq_fund_rollover_implies_propagate CHECK
	( propagate OR NOT rollover );

ALTER TABLE acq.fund
	ADD COLUMN active BOOL NOT NULL DEFAULT TRUE;

ALTER TABLE acq.fund
    ADD COLUMN balance_warning_percent INT;

ALTER TABLE acq.fund
    ADD COLUMN balance_stop_percent INT;

CREATE VIEW acq.ordered_funding_source_credit AS
	SELECT
		CASE WHEN deadline_date IS NULL THEN
			2
		ELSE
			1
		END AS sort_priority,
		CASE WHEN deadline_date IS NULL THEN
			effective_date
		ELSE
			deadline_date
		END AS sort_date,
		id,
		funding_source,
		amount,
		note
	FROM
		acq.funding_source_credit;

COMMENT ON VIEW acq.ordered_funding_source_credit IS $$
/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@gmail.com>
 *
 * The acq.ordered_funding_source_credit view is a prioritized
 * ordering of funding source credits.  When ordered by the first
 * three columns, this view defines the order in which the various
 * credits are to be tapped for spending, subject to the allocations
 * in the acq.fund_allocation table.
 *
 * The first column reflects the principle that we should spend
 * money with deadlines before spending money without deadlines.
 *
 * The second column reflects the principle that we should spend the
 * oldest money first.  For money with deadlines, that means that we
 * spend first from the credit with the earliest deadline.  For
 * money without deadlines, we spend first from the credit with the
 * earliest effective date.  
 *
 * The third column is a tie breaker to ensure a consistent
 * ordering.
 *
 * ****
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
$$;

CREATE OR REPLACE VIEW money.billable_xact_summary_location_view AS
    SELECT  m.*, COALESCE(c.circ_lib, g.billing_location, r.pickup_lib) AS billing_location
      FROM  money.materialized_billable_xact_summary m
            LEFT JOIN action.circulation c ON (c.id = m.id)
            LEFT JOIN money.grocery g ON (g.id = m.id)
            LEFT JOIN booking.reservation r ON (r.id = m.id);

CREATE TABLE config.marc21_rec_type_map (
    code        TEXT    PRIMARY KEY,
    type_val    TEXT    NOT NULL,
    blvl_val    TEXT    NOT NULL
);

CREATE TABLE config.marc21_ff_pos_map (
    id          SERIAL  PRIMARY KEY,
    fixed_field TEXT    NOT NULL,
    tag         TEXT    NOT NULL,
    rec_type    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    default_val TEXT    NOT NULL DEFAULT ' '
);

CREATE TABLE config.marc21_physical_characteristic_type_map (
    ptype_key   TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_subfield_map (
    id          SERIAL  PRIMARY KEY,
    ptype_key   TEXT    NOT NULL REFERENCES config.marc21_physical_characteristic_type_map (ptype_key) ON DELETE CASCADE ON UPDATE CASCADE,
    subfield    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_value_map (
    id              SERIAL  PRIMARY KEY,
    value           TEXT    NOT NULL,
    ptype_subfield  INT     NOT NULL REFERENCES config.marc21_physical_characteristic_subfield_map (id),
    label           TEXT    NOT NULL -- I18N
);

----------------------------------
-- MARC21 record structure data --
----------------------------------

-- Record type map
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('BKS','at','acdm');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('SER','a','bsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('VIS','gkro','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('MIX','p','cdi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('MAP','ef','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('SCO','cd','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('REC','ij','abcdmsi');
INSERT INTO config.marc21_rec_type_map (code, type_val, blvl_val) VALUES ('COM','m','abcdmsi');

------ Physical Characteristics

-- Map
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('a','Map');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Atlas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Diagram');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Map');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Profile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Model');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Remote-sensing image');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Section');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'View');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','e','4','1','Physical medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flexible base photographic medium, positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flexible base photographic medium, negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Non-flexible base photographic medium, positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Non-flexible base photographic medium, negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other photographic medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','f','5','1','Type of reproduction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Facsimile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','g','6','1','Production/reproduction details');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photocopy, blueline print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photocopy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Pre-production');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('a','h','7','1','Positive/negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');

-- Electronic Resource
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('c','Electronic Resource');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape Cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Chip cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Computer optical disk cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tape reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magneto-optical disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical disk');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Remote');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Gray scale');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','e','4','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 3/4 in. or 12 cm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 1/8 x 2 3/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 7/8 x 2 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 1/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','f','5','1','Sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES (' ',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'No sound (Silent)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','g','6','3','Image bit depth');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('---',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mmm',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('nnn',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','h','9','1','File formats');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One file format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple file formats');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','i','10','1','Quality assurance target(s)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Absent');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Present');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','j','11','1','Antecedent/Source');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from original');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from microform');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from electronic resource');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'File reproduced from an intermediate (not microform)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','k','12','1','Level of compression');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Uncompressed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Lossless');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Lossy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('c','l','13','1','Reformatting quality');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Access');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Preservation');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Replacement');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');

-- Globe
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('d','Globe');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Celestial globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Planetary or lunar globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Terrestrial globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Earth moon globe');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','e','4','1','Physical medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('d','f','5','1','Type of reproduction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Facsimile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Tactile Material
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('f','Tactile Material');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Moon');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Tactile, with no writing system');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','d','3','2','Class of braille writing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Literary braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Format code braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mathematics and scientific braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Computer braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Music braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multiple braille types');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','e','4','1','Level of contraction');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Uncontracted');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Contracted');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','f','6','3','Braille music format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bar over bar');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bar by bar');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Line over line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paragraph');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Single line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Section by section');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Line by line');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Open score');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Spanner short form scoring');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Short form scoring');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Outline');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vertical score');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('f','g','9','1','Special physical characteristics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Print/braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Jumbo or enlarged braille');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Projected Graphic
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('g','Projected Graphic');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Filmstrip');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film filmstrip type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Filmstrip roll');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Slide');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Transparency');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','e','4','1','Base of emulsion');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film base, other than safety film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super 8 mm./single 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9.5 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'28 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 x 2 in. (5 x 5 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 1/4 x 2 1/4 in. (6 x 6 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 x 5 in. (10 x 13 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 x 7 in. (13 x 18 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 x 10 in. (21 x 26 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('w',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9 x 9 in. (23 x 23 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('x',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10 x 10 in. (26 x 26 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('y',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 x 7 in. (18 x 18 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('g','i','8','1','Secondary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal and glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics and glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Microform
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('h','Microform');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aperture card');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfilm reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfiche');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microfiche cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microopaque');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','d','3','1','Positive/negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Positive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Negative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','e','4','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'105 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 x 5 in. (8 x 13 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 x 6 in. (11 x 15 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'6 x 9 in. (16 x 23 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 1/4 x 7 3/8 in. (9 x 19 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','f','5','4','Reduction ratio range/Reduction ratio');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Low (1-16x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Normal (16-30x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'High (31-60x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Very high (61-90x)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Ultra (90x-)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Reduction ratio varies');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','g','9','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','h','10','1','Emulsion on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Silver halide');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Diazo');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vesicular');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','i','11','1','Quality assurance target(s)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1st gen. master');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Printing master');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Service copy');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed generation');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('h','j','12','1','Base of film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, undetermined');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, acetate undetermined');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, diacetate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Nitrate base');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed base');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, polyester');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Safety base, triacetate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Non-projected Graphic
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('k','Non-projected Graphic');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Collage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Drawing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Painting');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photo-mechanical print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photonegative');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Photoprint');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Picture');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Technical drawing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Chart');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Flash/activity card');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'One color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','e','4','1','Primary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Canvas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bristol board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard/illustration board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Porcelain');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('k','f','5','1','Secondary support material');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Canvas');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bristol board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cardboard/illustration board');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Glass');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetics');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Skins');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Textile');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Metal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed collection');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Paper');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Plaster');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hardboard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Porcelain');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stone');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wood');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Motion Picture
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('m','Motion Picture');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Film reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hand-colored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','e','4','1','Motion picture presentation format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard sound aperture, reduced frame');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Nonanamorphic (wide-screen)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3D');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Anamorphic (wide-screen)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other-wide screen format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard. silent aperture, full frame');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Standard 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super 8 mm./single 8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'9.5 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'28 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'35 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','i','8','1','Configuration of playback channels');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multichannel, surround or quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('m','j','9','1','Production elements');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Work print');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Trims');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Outtakes');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Rushes');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixing tracks');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Title bands/inter-title rolls');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Production rolls');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Remote-sensing Image
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('r','Remote-sensing Image');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','d','3','1','Altitude of sensor');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Surface');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Airborne');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Spaceborne');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','e','4','1','Attitude of sensor');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Low oblique');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'High oblique');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Vertical');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','f','5','1','Cloud cover');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('0',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'0-09%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('1',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10-19%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('2',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'20-29%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('3',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'30-39%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('4',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'40-49%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('5',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'50-59%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('6',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'60-69%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('7',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'70-79%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('8',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'80-89%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('9',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'90-100%');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','g','6','1','Platform construction type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Balloon');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-low altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-medium altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Aircraft-high altitude');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Manned spacecraft');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unmanned spacecraft');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Land-based remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Water surface-based remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Submersible remote-sensing device');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','h','7','1','Platform use category');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Meteorological');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Surface observing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Space observing');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed uses');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','i','8','1','Sensor type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Active');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Passive');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('r','j','9','2','Data type');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('aa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Visible light');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('da',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Near infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('db',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Middle infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Far infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Thermal infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('de',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Shortwave infrared (SWIR)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('df',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Reflective infrared');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dv',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combinations');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('dz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other infrared data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ga',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sidelooking airborne radar (SLAR)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Synthetic aperture radar (SAR-single frequency)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-multi-frequency (multichannel)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-like polarization');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ge',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'SAR-cross polarization');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gf',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Infometric SAR');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gg',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Polarmetric SAR');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gu',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Passive microwave mapping');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('gz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other microwave data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ja',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Far ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Middle ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Near ultraviolet');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jv',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Ultraviolet combinations');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('jz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other ultraviolet data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ma',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multi-spectral, multidata');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multi-temporal');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('mm',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Combination of various data types');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('nn',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-water depth');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography images, sidescan');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography, near-surface');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sonar-bottom topography, near-bottom');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pe',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Seismic surveys');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('pz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other acoustical data');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ra',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Gravity anomales (general)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rb',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Free-air');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rc',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Bouger');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('rd',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Isostatic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('sa',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic field');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('ta',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Radiometric surveys');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('uu',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('zz',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Sound Recording
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('s','Sound Recording');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Cylinder');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound-track film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Roll');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('t',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound-tape reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('w',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Wire recording');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','d','3','1','Speed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'33 1/3 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'45 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'78 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1.4 mps');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'120 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'160 rpm');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'15/16 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 7/8 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 3/4 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 1/2 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'15 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'30 ips');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','e','4','1','Configuration of playback channels');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','f','5','1','Groove width or pitch');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Microgroove/fine');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Coarse/standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','g','6','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'7 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'10 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'4 3/4 in. (12 cm.)');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3 7/8 x 2 1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'5 1/4 x 3 7/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 3/4 x 4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','h','7','1','Tape width');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('l',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/8 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/4in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','i','8','1','Tape configuration ');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Full (1) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Half (2) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quarter (4) track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'12 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'16 track');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','m','12','1','Special playback');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'NAB standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CCIR standard');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-B encoded, standard Dolby');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'dbx encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Digital recording');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-A encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Dolby-C encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CX encoded');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('s','n','13','1','Capture and storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Acoustical capture, direct storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Direct storage, not acoustical');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Digital storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Analog electrical storage');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Videorecording
INSERT INTO config.marc21_physical_characteristic_type_map (ptype_key, label) VALUES ('v','Videorecording');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','b','1','1','SMD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videocartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videocassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videoreel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unspecified');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','d','3','1','Color');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Black-and-white');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multicolored');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','e','4','1','Videorecording format');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Beta');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'VHS');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'U-matic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'EIAJ');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Type C');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Quadruplex');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Laserdisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'CED');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Betacam');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('j',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Betacam SP');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Super-VHS');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'M-II');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'D-2');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Hi-8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('v',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'DVD');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','f','5','1','Sound on medium or separate');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound on medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound separate from medium');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','g','6','1','Medium for sound');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('b',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('c',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cartridge');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('d',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Sound disc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('e',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape on reel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('f',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Magnetic audio tape in cassette');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('g',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Optical and magnetic sound track on motion picture film');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('h',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videotape');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('i',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Videodisc');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','h','7','1','Dimensions');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('a',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'8 mm.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('o',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1/2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('p',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'1 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'2 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('r',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'3/4 in.');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');
INSERT INTO config.marc21_physical_characteristic_subfield_map (ptype_key,subfield,start_pos,length,label) VALUES ('v','i','8','1','Configuration of playback channel');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('k',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Mixed');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('m',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Monaural');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('n',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Not applicable');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('q',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Multichannel, surround or quadraphonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('s',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Stereophonic');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('u',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Unknown');
INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label) VALUES ('z',CURRVAL('config.marc21_physical_characteristic_subfield_map_id_seq'),'Other');

-- Fixed Field position data -- 0-based!
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Alph', '006', 'SER', 16, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Alph', '008', 'SER', 33, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'BKS', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'COM', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'REC', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'SCO', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'SER', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '006', 'VIS', 5, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'BKS', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'COM', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'REC', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'SCO', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'SER', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Audn', '008', 'VIS', 22, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'BKS', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'COM', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'MAP', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'MIX', 7, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'REC', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'SCO', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'SER', 7, 1, 's');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('BLvl', 'ldr', 'VIS', 7, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Biog', '006', 'BKS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Biog', '008', 'BKS', 34, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'BKS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '006', 'SER', 8, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'BKS', 24, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Conf', '008', 'SER', 25, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'BKS', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'COM', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'MAP', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'MIX', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'REC', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'SCO', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'SER', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctrl', 'ldr', 'VIS', 8, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'BKS', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'COM', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'MAP', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'MIX', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'REC', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'SCO', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'SER', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ctry', '008', 'VIS', 15, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'BKS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'COM', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'MAP', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'MIX', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'REC', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'SCO', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'SER', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date1', '008', 'VIS', 7, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'BKS', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'COM', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'MAP', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'MIX', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'REC', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'SCO', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'SER', 11, 4, '9');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Date2', '008', 'VIS', 11, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'BKS', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'COM', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'MAP', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'MIX', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'REC', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'SCO', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'SER', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Desc', 'ldr', 'VIS', 18, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'BKS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'COM', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'MAP', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'MIX', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'REC', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'SCO', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'SER', 6, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('DtSt', '008', 'VIS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'BKS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'COM', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'MAP', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'MIX', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'REC', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'SCO', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'SER', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('ELvl', 'ldr', 'VIS', 17, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Fest', '006', 'BKS', 13, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Fest', '008', 'BKS', 30, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'BKS', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'MAP', 12, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'MIX', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'REC', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'SCO', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'SER', 6, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '006', 'VIS', 12, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'BKS', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'MAP', 29, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'MIX', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'REC', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'SCO', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'SER', 23, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Form', '008', 'VIS', 29, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'BKS', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'COM', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'MAP', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'SER', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '006', 'VIS', 11, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'BKS', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'COM', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'MAP', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'SER', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('GPub', '008', 'VIS', 28, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ills', '006', 'BKS', 1, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Ills', '008', 'BKS', 18, 4, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '006', 'BKS', 14, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '006', 'MAP', 14, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '008', 'BKS', 31, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Indx', '008', 'MAP', 31, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'BKS', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'COM', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'MAP', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'MIX', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'REC', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'SCO', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'SER', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Lang', '008', 'VIS', 35, 3, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('LitF', '006', 'BKS', 16, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('LitF', '008', 'BKS', 33, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'BKS', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'COM', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'MAP', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'MIX', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'REC', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'SCO', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'SER', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('MRec', '008', 'VIS', 38, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('S/L', '006', 'SER', 17, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('S/L', '008', 'SER', 34, 1, '0');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('TMat', '006', 'VIS', 16, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('TMat', '008', 'VIS', 33, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'BKS', 6, 1, 'a');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'COM', 6, 1, 'm');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'MAP', 6, 1, 'e');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'MIX', 6, 1, 'p');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'REC', 6, 1, 'i');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'SCO', 6, 1, 'c');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'SER', 6, 1, 'a');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Type', 'ldr', 'VIS', 6, 1, 'g');

CREATE OR REPLACE FUNCTION biblio.marc21_record_type( rid BIGINT ) RETURNS config.marc21_rec_type_map AS $func$
DECLARE
	ldr         RECORD;
	tval        TEXT;
	tval_rec    RECORD;
	bval        TEXT;
	bval_rec    RECORD;
    retval      config.marc21_rec_type_map%ROWTYPE;
BEGIN
    SELECT * INTO ldr FROM metabib.full_rec WHERE record = rid AND tag = 'LDR' LIMIT 1;

    IF ldr.id IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
        RETURN retval;
    END IF;

    SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
    SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


    tval := SUBSTRING( ldr.value, tval_rec.start_pos + 1, tval_rec.length );
    bval := SUBSTRING( ldr.value, bval_rec.start_pos + 1, bval_rec.length );

    -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr.value;

    SELECT * INTO retval FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';


    IF retval.code IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
    END IF;

    RETURN retval;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field( rid BIGINT, ff TEXT ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (biblio.marc21_record_type( rid )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        FOR tag_data IN SELECT * FROM metabib.full_rec WHERE tag = UPPER(ff_pos.tag) AND record = rid LOOP
            val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
            RETURN val;
        END LOOP;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TYPE biblio.marc21_physical_characteristics AS ( id INT, record BIGINT, ptype TEXT, subfield INT, value INT );
CREATE OR REPLACE FUNCTION biblio.marc21_physical_characteristics( rid BIGINT ) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    RECORD;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    SELECT * INTO _007 FROM metabib.full_rec WHERE record = rid AND tag = '007' LIMIT 1;

    IF _007.id IS NOT NULL THEN
        SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007.value, 1, 1 );

        IF ptype.ptype_key IS NOT NULL THEN
            FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007.value, psf.start_pos + 1, psf.length );

                IF pval.id IS NOT NULL THEN
                    rowid := rowid + 1;
                    retval.id := rowid;
                    retval.record := rid;
                    retval.ptype := ptype.ptype_key;
                    retval.subfield := psf.id;
                    retval.value := pval.id;
                    RETURN NEXT retval;
                END IF;

            END LOOP;
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

DROP VIEW IF EXISTS money.open_usr_circulation_summary;
DROP VIEW IF EXISTS money.open_usr_summary;
DROP VIEW IF EXISTS money.open_billable_xact_summary;

-- The view should supply defaults for numeric (amount) columns
CREATE OR REPLACE VIEW money.billable_xact_summary AS
    SELECT  xact.id,
        xact.usr,
        xact.xact_start,
        xact.xact_finish,
        COALESCE(credit.amount, 0.0::numeric) AS total_paid,
        credit.payment_ts AS last_payment_ts,
        credit.note AS last_payment_note,
        credit.payment_type AS last_payment_type,
        COALESCE(debit.amount, 0.0::numeric) AS total_owed,
        debit.billing_ts AS last_billing_ts,
        debit.note AS last_billing_note,
        debit.billing_type AS last_billing_type,
        COALESCE(debit.amount, 0.0::numeric) - COALESCE(credit.amount, 0.0::numeric) AS balance_owed,
        p.relname AS xact_type
      FROM  money.billable_xact xact
        JOIN pg_class p ON xact.tableoid = p.oid
        LEFT JOIN (
            SELECT  billing.xact,
                sum(billing.amount) AS amount,
                max(billing.billing_ts) AS billing_ts,
                last(billing.note) AS note,
                last(billing.billing_type) AS billing_type
              FROM  money.billing
              WHERE billing.voided IS FALSE
              GROUP BY billing.xact
            ) debit ON xact.id = debit.xact
        LEFT JOIN (
            SELECT  payment_view.xact,
                sum(payment_view.amount) AS amount,
                max(payment_view.payment_ts) AS payment_ts,
                last(payment_view.note) AS note,
                last(payment_view.payment_type) AS payment_type
              FROM  money.payment_view
              WHERE payment_view.voided IS FALSE
              GROUP BY payment_view.xact
            ) credit ON xact.id = credit.xact
      ORDER BY debit.billing_ts, credit.payment_ts;

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS 
    SELECT * FROM money.billable_xact_summary_location_view
    WHERE xact_finish IS NULL;

CREATE OR REPLACE VIEW money.open_usr_circulation_summary AS
    SELECT 
        usr,
        SUM(total_paid) AS total_paid,
        SUM(total_owed) AS total_owed,
        SUM(balance_owed) AS balance_owed
    FROM  money.materialized_billable_xact_summary
    WHERE xact_type = 'circulation' AND xact_finish IS NULL
    GROUP BY usr;

CREATE OR REPLACE VIEW money.usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    GROUP BY usr;

CREATE OR REPLACE VIEW money.open_usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL
    GROUP BY usr;

-- CREATE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id;

CREATE TABLE config.biblio_fingerprint (
	id			SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL, 
	xpath		TEXT	NOT NULL,
    first_word  BOOL    NOT NULL DEFAULT FALSE,
	format		TEXT	NOT NULL DEFAULT 'marcxml'
);

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'Title',
        '//marc:datafield[@tag="700"]/marc:subfield[@code="t"]|' ||
            '//marc:datafield[@tag="240"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="242"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="246"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="245"]/marc:subfield[@code="a"]',
        'marcxml'
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format, first_word)
    VALUES (
        'Author',
        '//marc:datafield[@tag="700" and ./*[@code="t"]]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="100"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="110"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="111"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="260"]/marc:subfield[@code="b"]',
        'marcxml',
        TRUE
    );

CREATE OR REPLACE FUNCTION biblio.extract_quality ( marc TEXT, best_lang TEXT, best_type TEXT ) RETURNS INT AS $func$
DECLARE
    qual        INT;
    ldr         TEXT;
    tval        TEXT;
    tval_rec    RECORD;
    bval        TEXT;
    bval_rec    RECORD;
    type_map    RECORD;
    ff_pos      RECORD;
    ff_tag_data TEXT;
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

    -- First, the count of tags
    qual := ARRAY_UPPER(oils_xpath('*[local-name()="datafield"]', marc), 1);

    -- now go through a bunch of pain to get the record type
    IF best_type IS NOT NULL THEN
        ldr := (oils_xpath('//*[local-name()="leader"]/text()', marc))[1];

        IF ldr IS NOT NULL THEN
            SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
            SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


            tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
            bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

            -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

            SELECT * INTO type_map FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';

            IF type_map.code IS NOT NULL THEN
                IF best_type = type_map.code THEN
                    qual := qual + qual / 2;
                END IF;

                FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = 'Lang' AND rec_type = type_map.code ORDER BY tag DESC LOOP
                    ff_tag_data := SUBSTRING((oils_xpath('//*[@tag="' || ff_pos.tag || '"]/text()',marc))[1], ff_pos.start_pos + 1, ff_pos.length);
                    IF ff_tag_data = best_lang THEN
                            qual := qual + 100;
                    END IF;
                END LOOP;
            END IF;
        END IF;
    END IF;

    -- Now look for some quality metrics
    -- DCL record?
    IF ARRAY_UPPER(oils_xpath('//*[@tag="040"]/*[@code="a" and contains(.,"DLC")]', marc), 1) = 1 THEN
        qual := qual + 10;
    END IF;

    -- From OCLC?
    IF (oils_xpath('//*[@tag="003"]/text()', marc))[1] ~* E'oclo?c' THEN
        qual := qual + 10;
    END IF;

    RETURN qual;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_fingerprint ( marc text ) RETURNS TEXT AS $func$
DECLARE
    idx     config.biblio_fingerprint%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    raw_text    TEXT;
    output_text TEXT := '';
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.biblio_fingerprint ORDER BY format, id LOOP

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(marc,xfrm.xslt);
            ELSE
                transformed_xml := marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        raw_text := COALESCE(
            naco_normalize(
                ARRAY_TO_STRING(
                    oils_xpath(
                        '//text()',
                        (oils_xpath(
                            idx.xpath,
                            transformed_xml,
                            ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                        ))[1]
                    ),
                    ''
                )
            ),
            ''
        );

        raw_text := REGEXP_REPLACE(raw_text, E'\\[.+?\\]', E'');
        raw_text := REGEXP_REPLACE(raw_text, E'\\mthe\\M|\\man?d?d\\M', E'', 'g'); -- arg! the pain!

        IF idx.first_word IS TRUE THEN
            raw_text := REGEXP_REPLACE(raw_text, E'^(\\w+).*?$', E'\\1');
        END IF;

        output_text := output_text || REGEXP_REPLACE(raw_text, E'\\s+', '', 'g');

    END LOOP;

    RETURN output_text;

END;
$func$ LANGUAGE PLPGSQL;

-- BEFORE UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.fingerprint_trigger () RETURNS TRIGGER AS $func$
BEGIN

    -- For TG_ARGV, first param is language (like 'eng'), second is record type (like 'BKS')

    IF NEW.deleted IS TRUE THEN -- we don't much care, then, do we?
        RETURN NEW;
    END IF;

    NEW.fingerprint := biblio.extract_fingerprint(NEW.marc);
    NEW.quality := biblio.extract_quality(NEW.marc, TG_ARGV[0], TG_ARGV[1]);

    RETURN NEW;

END;
$func$ LANGUAGE PLPGSQL;

CREATE TABLE config.internal_flag (
    name    TEXT    PRIMARY KEY,
    value   TEXT,
    enabled BOOL    NOT NULL DEFAULT FALSE
);
INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.skip_on_insert');
INSERT INTO config.internal_flag (name) VALUES ('ingest.reingest.force_on_same_marc');
INSERT INTO config.internal_flag (name) VALUES ('ingest.reingest.skip_located_uri');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_located_uri');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_metabib_full_rec');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_metabib_rec_descriptor');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_metabib_field_entry');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_authority_linking');
INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.skip_on_update');
INSERT INTO config.internal_flag (name) VALUES ('ingest.assume_inserts_only');

CREATE TABLE authority.bib_linking (
    id          BIGSERIAL   PRIMARY KEY,
    bib         BIGINT      NOT NULL REFERENCES biblio.record_entry (id),
    authority   BIGINT      NOT NULL REFERENCES authority.record_entry (id)
);
CREATE INDEX authority_bl_bib_idx ON authority.bib_linking ( bib );
CREATE UNIQUE INDEX authority_bl_bib_authority_once_idx ON authority.bib_linking ( authority, bib );

CREATE OR REPLACE FUNCTION public.remove_paren_substring( TEXT ) RETURNS TEXT AS $func$
    SELECT regexp_replace($1, $$\([^)]+\)$$, '', 'g');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION biblio.map_authority_linking (bibid BIGINT, marc TEXT) RETURNS BIGINT AS $func$
    DELETE FROM authority.bib_linking WHERE bib = $1;
    INSERT INTO authority.bib_linking (bib, authority)
        SELECT  y.bib,
                y.authority
          FROM (    SELECT  DISTINCT $1 AS bib,
                            BTRIM(remove_paren_substring(txt))::BIGINT AS authority
                      FROM  explode_array(oils_xpath('//*[@code="0"]/text()',$2)) x(txt)
                      WHERE BTRIM(remove_paren_substring(txt)) ~ $re$^\d+$$re$
                ) y JOIN authority.record_entry r ON r.id = y.authority;
    SELECT $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_rec_descriptor( bib_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        DELETE FROM metabib.rec_descriptor WHERE record = bib_id;
    END IF;
    INSERT INTO metabib.rec_descriptor (record, item_type, item_form, bib_level, control_type, enc_level, audience, lit_form, type_mat, cat_form, pub_status, item_lang, vr_format, date1, date2)
        SELECT  bib_id,
                biblio.marc21_extract_fixed_field( bib_id, 'Type' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Form' ),
                biblio.marc21_extract_fixed_field( bib_id, 'BLvl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Ctrl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'ELvl' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Audn' ),
                biblio.marc21_extract_fixed_field( bib_id, 'LitF' ),
                biblio.marc21_extract_fixed_field( bib_id, 'TMat' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Desc' ),
                biblio.marc21_extract_fixed_field( bib_id, 'DtSt' ),
                biblio.marc21_extract_fixed_field( bib_id, 'Lang' ),
                (   SELECT  v.value
                      FROM  biblio.marc21_physical_characteristics( bib_id) p
                            JOIN config.marc21_physical_characteristic_subfield_map s ON (s.id = p.subfield)
                            JOIN config.marc21_physical_characteristic_value_map v ON (v.id = p.value)
                      WHERE p.ptype = 'v' AND s.subfield = 'e'    ),
                LPAD(NULLIF(REGEXP_REPLACE(NULLIF(biblio.marc21_extract_fixed_field( bib_id, 'Date1'), ''), E'\\D', '0', 'g')::INT,0)::TEXT,4,'0'),
                LPAD(NULLIF(REGEXP_REPLACE(NULLIF(biblio.marc21_extract_fixed_field( bib_id, 'Date2'), ''), E'\\D', '9', 'g')::INT,9999)::TEXT,4,'0');

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TABLE config.metabib_class (
    name    TEXT    PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE
);

INSERT INTO config.metabib_class ( name, label ) VALUES ( 'keyword', oils_i18n_gettext('keyword', 'Keyword', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'title', oils_i18n_gettext('title', 'Title', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'author', oils_i18n_gettext('author', 'Author', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'subject', oils_i18n_gettext('subject', 'Subject', 'cmc', 'label') );
INSERT INTO config.metabib_class ( name, label ) VALUES ( 'series', oils_i18n_gettext('series', 'Series', 'cmc', 'label') );

CREATE TABLE metabib.facet_entry (
        id              BIGSERIAL       PRIMARY KEY,
        source          BIGINT          NOT NULL,
        field           INT             NOT NULL,
        value           TEXT            NOT NULL
);

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( bib_id BIGINT ) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        FOR fclass IN SELECT * FROM config.metabib_class LOOP
            -- RAISE NOTICE 'Emptying out %', fclass.name;
            EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
        END LOOP;
        DELETE FROM metabib.facet_entry WHERE source = bib_id;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id ) LOOP
        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        ELSE
            EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
        END IF;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.extract_located_uris( bib_id BIGINT, marcxml TEXT, editor_id INT ) RETURNS VOID AS $func$
DECLARE
    uris            TEXT[];
    uri_xml         TEXT;
    uri_label       TEXT;
    uri_href        TEXT;
    uri_use         TEXT;
    uri_owner       TEXT;
    uri_owner_id    INT;
    uri_id          INT;
    uri_cn_id       INT;
    uri_map_id      INT;
BEGIN

    uris := oils_xpath('//*[@tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]',marcxml);
    IF ARRAY_UPPER(uris,1) > 0 THEN
        FOR i IN 1 .. ARRAY_UPPER(uris, 1) LOOP
            -- First we pull info out of the 856
            uri_xml     := uris[i];

            uri_href    := (oils_xpath('//*[@code="u"]/text()',uri_xml))[1];
            CONTINUE WHEN uri_href IS NULL;

            uri_label   := (oils_xpath('//*[@code="y"]/text()|//*[@code="3"]/text()|//*[@code="u"]/text()',uri_xml))[1];
            CONTINUE WHEN uri_label IS NULL;

            uri_owner   := (oils_xpath('//*[@code="9"]/text()|//*[@code="w"]/text()|//*[@code="n"]/text()',uri_xml))[1];
            CONTINUE WHEN uri_owner IS NULL;

            uri_use     := (oils_xpath('//*[@code="z"]/text()|//*[@code="2"]/text()|//*[@code="n"]/text()|//*[@code="u"]/text()',uri_xml))[1];

            uri_owner := REGEXP_REPLACE(uri_owner, $re$^.*?\((\w+)\).*$$re$, E'\\1');

            SELECT id INTO uri_owner_id FROM actor.org_unit WHERE shortname = uri_owner;
            CONTINUE WHEN NOT FOUND;

            -- now we look for a matching uri
            SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
            IF NOT FOUND THEN -- create one
                INSERT INTO asset.uri (label, href, use_restriction) VALUES (uri_label, uri_href, uri_use);
                SELECT id INTO uri_id FROM asset.uri WHERE label = uri_label AND href = uri_href AND use_restriction = uri_use AND active;
            END IF;

            -- we need a call number to link through
            SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
            IF NOT FOUND THEN
                INSERT INTO asset.call_number (owning_lib, record, create_date, edit_date, creator, editor, label)
                    VALUES (uri_owner_id, bib_id, 'now', 'now', editor_id, editor_id, '##URI##');
                SELECT id INTO uri_cn_id FROM asset.call_number WHERE owning_lib = uri_owner_id AND record = bib_id AND label = '##URI##' AND NOT deleted;
            END IF;

            -- now, link them if they're not already
            SELECT id INTO uri_map_id FROM asset.uri_call_number_map WHERE call_number = uri_cn_id AND uri = uri_id;
            IF NOT FOUND THEN
                INSERT INTO asset.uri_call_number_map (call_number, uri) VALUES (uri_cn_id, uri_id);
            END IF;

        END LOOP;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.remap_metarecord_for_bib( bib_id BIGINT, fp TEXT ) RETURNS BIGINT AS $func$
DECLARE
    source_count    INT;
    old_mr          BIGINT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    deleted_mrs     BIGINT[];
BEGIN

    DELETE FROM metabib.metarecord_source_map WHERE source = bib_id; -- Rid ourselves of the search-estimate-killing linkage

    FOR tmp_mr IN SELECT  m.* FROM  metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = bib_id LOOP

        IF old_mr IS NULL AND fp = tmp_mr.fingerprint THEN -- Find the first fingerprint-matching
            old_mr := tmp_mr.id;
        ELSE
            SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
            IF source_count = 0 THEN -- No other records
                deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
            END IF;
        END IF;

    END LOOP;

    IF old_mr IS NULL THEN -- we found no suitable, preexisting MR based on old source maps
        SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp; -- is there one for our current fingerprint?
        IF old_mr IS NULL THEN -- nope, create one and grab its id
            INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( fp, bib_id );
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp;
        ELSE -- indeed there is. update it with a null cache and recalcualated master record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp ORDER BY quality DESC LIMIT 1)
              WHERE id = old_mr;
        END IF;
    ELSE -- there was one we already attached to, update its mods cache and master_record
        UPDATE  metabib.metarecord
          SET   mods = NULL,
                master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp ORDER BY quality DESC LIMIT 1)
          WHERE id = old_mr;
    END IF;

    INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, bib_id); -- new source mapping

    IF ARRAY_UPPER(deleted_mrs,1) > 0 THEN
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT explode_array(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;

    RETURN old_mr;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_full_rec( bib_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        DELETE FROM metabib.real_full_rec WHERE record = bib_id;
    END IF;
    INSERT INTO metabib.real_full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM biblio.flatten_marc( bib_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
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
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_metabib_rec_descriptor(NEW.id);
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

CREATE TRIGGER fingerprint_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.fingerprint_trigger ('eng','BKS');
CREATE TRIGGER aaa_indexing_ingest_or_delete AFTER INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.indexing_ingest_or_delete ();

DROP TRIGGER IF EXISTS zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
DROP TRIGGER IF EXISTS zzz_update_materialized_simple_rec_delete_tgr ON biblio.record_entry;

CREATE OR REPLACE FUNCTION oils_xpath_table ( key TEXT, document_field TEXT, relation_name TEXT, xpaths TEXT, criteria TEXT ) RETURNS SETOF RECORD AS $func$
DECLARE
    xpath_list  TEXT[];
    select_list TEXT[];
    where_list  TEXT[];
    q           TEXT;
    out_record  RECORD;
    empty_test  RECORD;
BEGIN
    xpath_list := STRING_TO_ARRAY( xpaths, '|' );
 
    select_list := ARRAY_APPEND( select_list, key || '::INT AS key' );
 
    FOR i IN 1 .. ARRAY_UPPER(xpath_list,1) LOOP
        IF xpath_list[i] = 'null()' THEN
            select_list := ARRAY_APPEND( select_list, 'NULL::TEXT AS c_' || i );
        ELSE
            select_list := ARRAY_APPEND(
                select_list,
                $sel$
                EXPLODE_ARRAY(
                    COALESCE(
                        NULLIF(
                            oils_xpath(
                                $sel$ ||
                                    quote_literal(
                                        CASE
                                            WHEN xpath_list[i] ~ $re$/[^/[]*@[^/]+$$re$ OR xpath_list[i] ~ $re$text\(\)$$re$ THEN xpath_list[i]
                                            ELSE xpath_list[i] || '//text()'
                                        END
                                    ) ||
                                $sel$,
                                $sel$ || document_field || $sel$
                            ),
                           '{}'::TEXT[]
                        ),
                        '{NULL}'::TEXT[]
                    )
                ) AS c_$sel$ || i
            );
            where_list := ARRAY_APPEND(
                where_list,
                'c_' || i || ' IS NOT NULL'
            );
        END IF;
    END LOOP;
 
    q := $q$
SELECT * FROM (
    SELECT $q$ || ARRAY_TO_STRING( select_list, ', ' ) || $q$ FROM $q$ || relation_name || $q$ WHERE ($q$ || criteria || $q$)
)x WHERE $q$ || ARRAY_TO_STRING( where_list, ' OR ' );
    -- RAISE NOTICE 'query: %', q;
 
    FOR out_record IN EXECUTE q LOOP
        RETURN NEXT out_record;
    END LOOP;
 
    RETURN;
END;
$func$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id; 
    
        -- Build the combined XPath
    
        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;
    
        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;
    
        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;
    
        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;
    
        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;
    
        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;
    
        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;
    
        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;
    
        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;
    
        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;
    
        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;
    
        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;
    
        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;
    
        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;
    
        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;
    
        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;
    
        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;
    
    
        xpath := 
            owning_lib      || '|' || 
            circ_lib        || '|' || 
            call_number     || '|' || 
            copy_number     || '|' || 
            status          || '|' || 
            location        || '|' || 
            circulate       || '|' || 
            deposit         || '|' || 
            deposit_amount  || '|' || 
            ref             || '|' || 
            holdable        || '|' || 
            price           || '|' || 
            barcode         || '|' || 
            circ_modifier   || '|' || 
            circ_as_type    || '|' || 
            alert_message   || '|' || 
            pub_note        || '|' || 
            priv_note       || '|' || 
            opac_visible;

        -- RAISE NOTICE 'XPath: %', xpath;
        
        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id INT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP
    
            tmp_attr_set.pr = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
            tmp_attr_set.dep_amount = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');

            tmp_attr_set.pr := NULLIF( tmp_attr_set.pr, '' );
            tmp_attr_set.dep_amount := NULLIF( tmp_attr_set.dep_amount, '' );
    
            SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
            SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
            SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT
    
            SELECT  id INTO attr_set.location
              FROM  asset.copy_location
              WHERE LOWER(name) = LOWER(tmp_attr_set.cl)
                    AND asset.copy_location.owning_lib = COALESCE(attr_set.owning_lib, attr_set.circ_lib); -- INT
    
            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL
    
            attr_set.copy_number    := tmp_attr_set.cnum::INT; -- INT,
            attr_set.deposit_amount := tmp_attr_set.dep_amount::NUMERIC(6,2); -- NUMERIC(6,2),
            attr_set.price          := tmp_attr_set.pr::NUMERIC(8,2); -- NUMERIC(8,2),
    
            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.circ_modifier  := tmp_attr_set.circ_mod; -- TEXT,
            attr_set.circ_as_type   := tmp_attr_set.circ_as; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
    
            RETURN NEXT attr_set;
    
        END LOOP;
    
    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_items ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr_def    BIGINT;
    item_data   vandelay.import_item%ROWTYPE;
BEGIN

    SELECT item_attr_def INTO attr_def FROM vandelay.bib_queue WHERE id = NEW.queue;

    FOR item_data IN SELECT * FROM vandelay.ingest_items( NEW.id::BIGINT, attr_def ) LOOP
        INSERT INTO vandelay.import_item (
            record,
            definition,
            owning_lib,
            circ_lib,
            call_number,
            copy_number,
            status,
            location,
            circulate,
            deposit,
            deposit_amount,
            ref,
            holdable,
            price,
            barcode,
            circ_modifier,
            circ_as_type,
            alert_message,
            pub_note,
            priv_note,
            opac_visible
        ) VALUES (
            NEW.id,
            item_data.definition,
            item_data.owning_lib,
            item_data.circ_lib,
            item_data.call_number,
            item_data.copy_number,
            item_data.status,
            item_data.location,
            item_data.circulate,
            item_data.deposit,
            item_data.deposit_amount,
            item_data.ref,
            item_data.holdable,
            item_data.price,
            item_data.barcode,
            item_data.circ_modifier,
            item_data.circ_as_type,
            item_data.alert_message,
            item_data.pub_note,
            item_data.priv_note,
            item_data.opac_visible
        );
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION acq.create_acq_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE SEQUENCE acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE acq.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            LIKE $$ || sch || $$.$$ || tbl || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE FUNCTION acq.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO acq.$$ || sch || $$_$$ || tbl || $$_history
                SELECT	nextval('acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    OLD.*;
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
            AFTER UPDATE OR DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
            EXECUTE PROCEDURE acq.audit_$$ || sch || $$_$$ || tbl || $$_func ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE VIEW acq.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	acq.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

-- The main event

CREATE OR REPLACE FUNCTION acq.create_acq_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    PERFORM acq.create_acq_seq(sch, tbl);
    PERFORM acq.create_acq_history(sch, tbl);
    PERFORM acq.create_acq_func(sch, tbl);
    PERFORM acq.create_acq_update_trigger(sch, tbl);
    PERFORM acq.create_acq_lifecycle(sch, tbl);
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

ALTER TABLE acq.lineitem DROP COLUMN item_count;

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  fund.id AS fund,
            fund_debit.encumbrance AS encumbrance,
            SUM( COALESCE( fund_debit.amount, 0 ) ) AS amount
      FROM acq.fund AS fund
			LEFT JOIN acq.fund_debit AS fund_debit
				ON ( fund.id = fund_debit.fund )
      GROUP BY 1,2;

CREATE TABLE acq.debit_attribution (
	id                     INT         NOT NULL PRIMARY KEY,
	fund_debit             INT         NOT NULL
	                                   REFERENCES acq.fund_debit
	                                   DEFERRABLE INITIALLY DEFERRED,
    debit_amount           NUMERIC     NOT NULL,
	funding_source_credit  INT         REFERENCES acq.funding_source_credit
	                                   DEFERRABLE INITIALLY DEFERRED,
    credit_amount          NUMERIC
);

CREATE INDEX acq_attribution_debit_idx
	ON acq.debit_attribution( fund_debit );

CREATE INDEX acq_attribution_credit_idx
	ON acq.debit_attribution( funding_source_credit );

CREATE OR REPLACE FUNCTION acq.attribute_debits() RETURNS VOID AS $$
/*
Function to attribute expenditures and encumbrances to funding source credits,
and thereby to funding sources.

Read the debits in chonological order, attributing each one to one or
more funding source credits.  Constraints:

1. Don't attribute more to a credit than the amount of the credit.

2. For a given fund, don't attribute more to a funding source than the
source has allocated to that fund.

3. Attribute debits to credits with deadlines before attributing them to
credits without deadlines.  Otherwise attribute to the earliest credits
first, based on the deadline date when present, or on the effective date
when there is no deadline.  Use funding_source_credit.id as a tie-breaker.
This ordering is defined by an ORDER BY clause on the view
acq.ordered_funding_source_credit.

Start by truncating the table acq.debit_attribution.  Then insert a row
into that table for each attribution.  If a debit cannot be fully
attributed, insert a row for the unattributable balance, with the 
funding_source_credit and credit_amount columns NULL.
*/
DECLARE
	curr_fund_source_bal RECORD;
	seqno                INT;     -- sequence num for credits applicable to a fund
	fund_credit          RECORD;  -- current row in temp t_fund_credit table
	fc                   RECORD;  -- used for loading t_fund_credit table
	sc                   RECORD;  -- used for loading t_fund_credit table
	--
	-- Used exclusively in the main loop:
	--
	deb                 RECORD;   -- current row from acq.fund_debit table
	curr_credit_bal     RECORD;   -- current row from temp t_credit table
	debit_balance       NUMERIC;  -- amount left to attribute for current debit
	conv_debit_balance  NUMERIC;  -- debit balance in currency of the fund
	attr_amount         NUMERIC;  -- amount being attributed, in currency of debit
	conv_attr_amount    NUMERIC;  -- amount being attributed, in currency of source
	conv_cred_balance   NUMERIC;  -- credit_balance in the currency of the fund
	conv_alloc_balance  NUMERIC;  -- allocated balance in the currency of the fund
	attrib_count        INT;      -- populates id of acq.debit_attribution
BEGIN
	--
	-- Load a temporary table.  For each combination of fund and funding source,
	-- load an entry with the total amount allocated to that fund by that source.
	-- This sum may reflect transfers as well as original allocations.  We will
	-- reduce this balance whenever we attribute debits to it.
	--
	CREATE TEMP TABLE t_fund_source_bal
	ON COMMIT DROP AS
		SELECT
			fund AS fund,
			funding_source AS source,
			sum( amount ) AS balance
		FROM
			acq.fund_allocation
		GROUP BY
			fund,
			funding_source
		HAVING
			sum( amount ) > 0;
	--
	CREATE INDEX t_fund_source_bal_idx
		ON t_fund_source_bal( fund, source );
	-------------------------------------------------------------------------------
	--
	-- Load another temporary table.  For each fund, load zero or more
	-- funding source credits from which that fund can get money.
	--
	CREATE TEMP TABLE t_fund_credit (
		fund        INT,
		seq         INT,
		credit      INT
	) ON COMMIT DROP;
	--
	FOR fc IN
		SELECT DISTINCT fund
		FROM acq.fund_allocation
		ORDER BY fund
	LOOP                  -- Loop over the funds
		seqno := 1;
		FOR sc IN
			SELECT
				ofsc.id
			FROM
				acq.ordered_funding_source_credit AS ofsc
			WHERE
				ofsc.funding_source IN
				(
					SELECT funding_source
					FROM acq.fund_allocation
					WHERE fund = fc.fund
				)
    		ORDER BY
    		    ofsc.sort_priority,
    		    ofsc.sort_date,
    		    ofsc.id
		LOOP                        -- Add each credit to the list
			INSERT INTO t_fund_credit (
				fund,
				seq,
				credit
			) VALUES (
				fc.fund,
				seqno,
				sc.id
			);
			--RAISE NOTICE 'Fund % credit %', fc.fund, sc.id;
			seqno := seqno + 1;
		END LOOP;     -- Loop over credits for a given fund
	END LOOP;         -- Loop over funds
	--
	CREATE INDEX t_fund_credit_idx
		ON t_fund_credit( fund, seq );
	-------------------------------------------------------------------------------
	--
	-- Load yet another temporary table.  This one is a list of funding source
	-- credits, with their balances.  We shall reduce those balances as we
	-- attribute debits to them.
	--
	CREATE TEMP TABLE t_credit
	ON COMMIT DROP AS
        SELECT
            fsc.id AS credit,
            fsc.funding_source AS source,
            fsc.amount AS balance,
            fs.currency_type AS currency_type
        FROM
            acq.funding_source_credit AS fsc,
            acq.funding_source fs
        WHERE
            fsc.funding_source = fs.id
			AND fsc.amount > 0;
	--
	CREATE INDEX t_credit_idx
		ON t_credit( credit );
	--
	-------------------------------------------------------------------------------
	--
	-- Now that we have loaded the lookup tables: loop through the debits,
	-- attributing each one to one or more funding source credits.
	-- 
	truncate table acq.debit_attribution;
	--
	attrib_count := 0;
	FOR deb in
		SELECT
			fd.id,
			fd.fund,
			fd.amount,
			f.currency_type,
			fd.encumbrance
		FROM
			acq.fund_debit fd,
			acq.fund f
		WHERE
			fd.fund = f.id
		ORDER BY
			fd.id
	LOOP
		--RAISE NOTICE 'Debit %, fund %', deb.id, deb.fund;
		--
		debit_balance := deb.amount;
		--
		-- Loop over the funding source credits that are eligible
		-- to pay for this debit
		--
		FOR fund_credit IN
			SELECT
				credit
			FROM
				t_fund_credit
			WHERE
				fund = deb.fund
			ORDER BY
				seq
		LOOP
			--RAISE NOTICE '   Examining credit %', fund_credit.credit;
			--
			-- Look up the balance for this credit.  If it's zero, then
			-- it's not useful, so treat it as if you didn't find it.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_credit_bal
			FROM t_credit
			WHERE
				credit = fund_credit.credit
				AND balance > 0;
			--
			IF curr_credit_bal IS NULL THEN
				--
				-- This credit is exhausted; try the next one.
				--
				CONTINUE;
			END IF;
			--
			--
			-- At this point we have an applicable credit with some money left.
			-- Now see if the relevant funding_source has any money left.
			--
			-- Look up the balance of the allocation for this combination of
			-- fund and source.  If you find such an entry, but it has a zero
			-- balance, then it's not useful, so treat it as unfound.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_fund_source_bal
			FROM t_fund_source_bal
			WHERE
				fund = deb.fund
				AND source = curr_credit_bal.source
				AND balance > 0;
			--
			IF curr_fund_source_bal IS NULL THEN
				--
				-- This fund/source doesn't exist or is already exhausted,
				-- so we can't use this credit.  Go on to the next one.
				--
				CONTINUE;
			END IF;
			--
			-- Convert the available balances to the currency of the fund
			--
			conv_alloc_balance := curr_fund_source_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			conv_cred_balance := curr_credit_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			--
			-- Determine how much we can attribute to this credit: the minimum
			-- of the debit amount, the fund/source balance, and the
			-- credit balance
			--
			--RAISE NOTICE '   deb bal %', debit_balance;
			--RAISE NOTICE '      source % balance %', curr_credit_bal.source, conv_alloc_balance;
			--RAISE NOTICE '      credit % balance %', curr_credit_bal.credit, conv_cred_balance;
			--
			conv_attr_amount := NULL;
			attr_amount := debit_balance;
			--
			IF attr_amount > conv_alloc_balance THEN
				attr_amount := conv_alloc_balance;
				conv_attr_amount := curr_fund_source_bal.balance;
			END IF;
			IF attr_amount > conv_cred_balance THEN
				attr_amount := conv_cred_balance;
				conv_attr_amount := curr_credit_bal.balance;
			END IF;
			--
			-- If we're attributing all of one of the balances, then that's how
			-- much we will deduct from the balances, and we already captured
			-- that amount above.  Otherwise we must convert the amount of the
			-- attribution from the currency of the fund back to the currency of
			-- the funding source.
			--
			IF conv_attr_amount IS NULL THEN
				conv_attr_amount := attr_amount * acq.exchange_ratio(
					deb.currency_type, curr_credit_bal.currency_type );
			END IF;
			--
			-- Insert a row to record the attribution
			--
			attrib_count := attrib_count + 1;
			INSERT INTO acq.debit_attribution (
				id,
				fund_debit,
				debit_amount,
				funding_source_credit,
				credit_amount
			) VALUES (
				attrib_count,
				deb.id,
				attr_amount,
				curr_credit_bal.credit,
				conv_attr_amount
			);
			--
			-- Subtract the attributed amount from the various balances
			--
			debit_balance := debit_balance - attr_amount;
			curr_fund_source_bal.balance := curr_fund_source_bal.balance - conv_attr_amount;
			--
			IF curr_fund_source_bal.balance <= 0 THEN
				--
				-- This allocation is exhausted.  Delete it so
				-- that we don't waste time looking at it again.
				--
				DELETE FROM t_fund_source_bal
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			ELSE
				UPDATE t_fund_source_bal
				SET balance = balance - conv_attr_amount
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			END IF;
			--
			IF curr_credit_bal.balance <= 0 THEN
				--
				-- This funding source credit is exhausted.  Delete it
				-- so that we don't waste time looking at it again.
				--
				--DELETE FROM t_credit
				--WHERE
				--	credit = curr_credit_bal.credit;
				--
				DELETE FROM t_fund_credit
				WHERE
					credit = curr_credit_bal.credit;
			ELSE
				UPDATE t_credit
				SET balance = curr_credit_bal.balance
				WHERE
					credit = curr_credit_bal.credit;
			END IF;
			--
			-- Are we done with this debit yet?
			--
			IF debit_balance <= 0 THEN
				EXIT;       -- We've fully attributed this debit; stop looking at credits.
			END IF;
		END LOOP;       -- End loop over credits
		--
		IF debit_balance <> 0 THEN
			--
			-- We weren't able to attribute this debit, or at least not
			-- all of it.  Insert a row for the unattributed balance.
			--
			attrib_count := attrib_count + 1;
			INSERT INTO acq.debit_attribution (
				id,
				fund_debit,
				debit_amount,
				funding_source_credit,
				credit_amount
			) VALUES (
				attrib_count,
				deb.id,
				debit_balance,
				NULL,
				NULL
			);
		END IF;
	END LOOP;   -- End of loop over debits
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    query := $q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        $q$ || quote_literal($3) || $q$,
                        marc,
                        ' '
                    ),
                    $q$ || quote_literal($4) || $q$,
                    '',
                    'g')
          FROM  $q$ || $1 || $q$
          WHERE id = $q$ || $2;

    EXECUTE query INTO output;

    -- RAISE NOTICE 'query: %, output; %', query, output;

    RETURN output;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN

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
                        array_to_string(
                            array_accum(
                                '<subfield code="' || subfield || '">' ||
                                regexp_replace(
                                    regexp_replace(
                                        regexp_replace(data,'&','&amp;','g'),
                                        '>', '&gt;', 'g'
                                    ),
                                    '<', '&lt;', 'g'
                                ) || '</subfield>'
                            ), ''
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

            uri_text := uri_text || uri_datafield;
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

    -- Find and move metarecords to the target record
    SELECT  INTO metarec *
      FROM  metabib.metarecord
      WHERE master_record = source_record;

    IF FOUND THEN
        UPDATE  metabib.metarecord
          SET   master_record = target_record,
            mods = NULL
          WHERE id = metarec.id;

        moved_objects := moved_objects + 1;
    END IF;

    -- Find call numbers attached to the source ...
    FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

        SELECT  INTO target_cn *
          FROM  asset.call_number
          WHERE label = source_cn.label
            AND owning_lib = source_cn.owning_lib
            AND record = target_record;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copies to that, and ...
            UPDATE  asset.copy
              SET   call_number = target_cn.id
              WHERE call_number = source_cn.id;

            -- ... move V holds to the move-target call number
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP

                UPDATE  action.hold_request
                  SET   target = target_cn.id
                  WHERE id = hold.id;

                moved_objects := moved_objects + 1;
            END LOOP;

        -- ... if not ...
        ELSE
            -- ... just move the call number to the target record
            UPDATE  asset.call_number
              SET   record = target_record
              WHERE id = source_cn.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find T holds targeting the source record ...
    FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

        -- ... and move them to the target record
        UPDATE  action.hold_request
          SET   target = target_record
          WHERE id = hold.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial records targeting the source record ...
    FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE  serial.record_entry
          SET   record = target_record
          WHERE id = ser_rec.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Finally, "delete" the source record
    DELETE FROM biblio.record_entry WHERE id = source_record;

    -- That's all, folks!
    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.transfer_fund(
	old_fund   IN INT,
	old_amount IN NUMERIC,     -- in currency of old fund
	new_fund   IN INT,
	new_amount IN NUMERIC,     -- in currency of new fund
	user_id    IN INT,
	xfer_note  IN TEXT         -- to be recorded in acq.fund_transfer
	-- ,funding_source_in IN INT  -- if user wants to specify a funding source (see notes)
) RETURNS VOID AS $$
/* -------------------------------------------------------------------------------

Function to transfer money from one fund to another.

A transfer is represented as a pair of entries in acq.fund_allocation, with a
negative amount for the old (losing) fund and a positive amount for the new
(gaining) fund.  In some cases there may be more than one such pair of entries
in order to pull the money from different funding sources, or more specifically
from different funding source credits.  For each such pair there is also an
entry in acq.fund_transfer.

Since funding_source is a non-nullable column in acq.fund_allocation, we must
choose a funding source for the transferred money to come from.  This choice
must meet two constraints, so far as possible:

1. The amount transferred from a given funding source must not exceed the
amount allocated to the old fund by the funding source.  To that end we
compare the amount being transferred to the amount allocated.

2. We shouldn't transfer money that has already been spent or encumbered, as
defined by the funding attribution process.  We attribute expenses to the
oldest funding source credits first.  In order to avoid transferring that
attributed money, we reverse the priority, transferring from the newest funding
source credits first.  There can be no guarantee that this approach will
avoid overcommitting a fund, but no other approach can do any better.

In this context the age of a funding source credit is defined by the
deadline_date for credits with deadline_dates, and by the effective_date for
credits without deadline_dates, with the proviso that credits with deadline_dates
are all considered "older" than those without.

----------

In the signature for this function, there is one last parameter commented out,
named "funding_source_in".  Correspondingly, the WHERE clause for the query
driving the main loop has an OR clause commented out, which references the
funding_source_in parameter.

If these lines are uncommented, this function will allow the user optionally to
restrict a fund transfer to a specified funding source.  If the source
parameter is left NULL, then there will be no such restriction.

------------------------------------------------------------------------------- */ 
DECLARE
	same_currency      BOOLEAN;
	currency_ratio     NUMERIC;
	old_fund_currency  TEXT;
	old_remaining      NUMERIC;  -- in currency of old fund
	new_fund_currency  TEXT;
	new_fund_active    BOOLEAN;
	new_remaining      NUMERIC;  -- in currency of new fund
	curr_old_amt       NUMERIC;  -- in currency of old fund
	curr_new_amt       NUMERIC;  -- in currency of new fund
	source_addition    NUMERIC;  -- in currency of funding source
	source_deduction   NUMERIC;  -- in currency of funding source
	orig_allocated_amt NUMERIC;  -- in currency of funding source
	allocated_amt      NUMERIC;  -- in currency of fund
	source             RECORD;
BEGIN
	--
	-- Sanity checks
	--
	IF old_fund IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id is NULL';
	END IF;
	--
	IF old_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer is NULL';
	END IF;
	--
	-- The new fund and its amount must be both NULL or both not NULL.
	--
	IF new_fund IS NOT NULL AND new_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer to receiving fund is NULL';
	END IF;
	--
	IF new_fund IS NULL AND new_amount IS NOT NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: receiving fund is NULL, its amount is not NULL';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: user id is NULL';
	END IF;
	--
	-- Initialize the amounts to be transferred, each denominated
	-- in the currency of its respective fund.  They will be
	-- reduced on each iteration of the loop.
	--
	old_remaining := old_amount;
	new_remaining := new_amount;
	--
	-- RAISE NOTICE 'Transferring % in fund % to % in fund %',
	--	old_amount, old_fund, new_amount, new_fund;
	--
	-- Get the currency types of the old and new funds.
	--
	SELECT
		currency_type
	INTO
		old_fund_currency
	FROM
		acq.fund
	WHERE
		id = old_fund;
	--
	IF old_fund_currency IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id % is not defined', old_fund;
	END IF;
	--
	IF new_fund IS NOT NULL THEN
		SELECT
			currency_type,
			active
		INTO
			new_fund_currency,
			new_fund_active
		FROM
			acq.fund
		WHERE
			id = new_fund;
		--
		IF new_fund_currency IS NULL THEN
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is not defined', new_fund;
		ELSIF NOT new_fund_active THEN
			--
			-- No point in putting money into a fund from whence you can't spend it
			--
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is inactive', new_fund;
		END IF;
		--
		IF new_amount = old_amount THEN
			same_currency := true;
			currency_ratio := 1;
		ELSE
			--
			-- We'll have to translate currency between funds.  We presume that
			-- the calling code has already applied an appropriate exchange rate,
			-- so we'll apply the same conversion to each sub-transfer.
			--
			same_currency := false;
			currency_ratio := new_amount / old_amount;
		END IF;
	END IF;
	--
	-- Identify the funding source(s) from which we want to transfer the money.
	-- The principle is that we want to transfer the newest money first, because
	-- we spend the oldest money first.  The priority for spending is defined
	-- by a sort of the view acq.ordered_funding_source_credit.
	--
	FOR source in
		SELECT
			ofsc.id,
			ofsc.funding_source,
			ofsc.amount,
			ofsc.amount * acq.exchange_ratio( fs.currency_type, old_fund_currency )
				AS converted_amt,
			fs.currency_type
		FROM
			acq.ordered_funding_source_credit AS ofsc,
			acq.funding_source fs
		WHERE
			ofsc.funding_source = fs.id
			and ofsc.funding_source IN
			(
				SELECT funding_source
				FROM acq.fund_allocation
				WHERE fund = old_fund
			)
			-- and
			-- (
			-- 	ofsc.funding_source = funding_source_in
			-- 	OR funding_source_in IS NULL
			-- )
		ORDER BY
			ofsc.sort_priority desc,
			ofsc.sort_date desc,
			ofsc.id desc
	LOOP
		--
		-- Determine how much money the old fund got from this funding source,
		-- denominated in the currency types of the source and of the fund.
		-- This result may reflect transfers from previous iterations.
		--
		SELECT
			COALESCE( sum( amount ), 0 ),
			COALESCE( sum( amount )
				* acq.exchange_ratio( source.currency_type, old_fund_currency ), 0 )
		INTO
			orig_allocated_amt,     -- in currency of the source
			allocated_amt           -- in currency of the old fund
		FROM
			acq.fund_allocation
		WHERE
			fund = old_fund
			and funding_source = source.funding_source;
		--	
		-- Determine how much to transfer from this credit, in the currency
		-- of the fund.   Begin with the amount remaining to be attributed:
		--
		curr_old_amt := old_remaining;
		--
		-- Can't attribute more than was allocated from the fund:
		--
		IF curr_old_amt > allocated_amt THEN
			curr_old_amt := allocated_amt;
		END IF;
		--
		-- Can't attribute more than the amount of the current credit:
		--
		IF curr_old_amt > source.converted_amt THEN
			curr_old_amt := source.converted_amt;
		END IF;
		--
		curr_old_amt := trunc( curr_old_amt, 2 );
		--
		old_remaining := old_remaining - curr_old_amt;
		--
		-- Determine the amount to be deducted, if any,
		-- from the old allocation.
		--
		IF old_remaining > 0 THEN
			--
			-- In this case we're using the whole allocation, so use that
			-- amount directly instead of applying a currency translation
			-- and thereby inviting round-off errors.
			--
			source_deduction := - orig_allocated_amt;
		ELSE 
			source_deduction := trunc(
				( - curr_old_amt ) *
					acq.exchange_ratio( old_fund_currency, source.currency_type ),
				2 );
		END IF;
		--
		IF source_deduction <> 0 THEN
			--
			-- Insert negative allocation for old fund in fund_allocation,
			-- converted into the currency of the funding source
			--
			INSERT INTO acq.fund_allocation (
				funding_source,
				fund,
				amount,
				allocator,
				note
			) VALUES (
				source.funding_source,
				old_fund,
				source_deduction,
				user_id,
				'Transfer to fund ' || new_fund
			);
		END IF;
		--
		IF new_fund IS NOT NULL THEN
			--
			-- Determine how much to add to the new fund, in
			-- its currency, and how much remains to be added:
			--
			IF same_currency THEN
				curr_new_amt := curr_old_amt;
			ELSE
				IF old_remaining = 0 THEN
					--
					-- This is the last iteration, so nothing should be left
					--
					curr_new_amt := new_remaining;
					new_remaining := 0;
				ELSE
					curr_new_amt := trunc( curr_old_amt * currency_ratio, 2 );
					new_remaining := new_remaining - curr_new_amt;
				END IF;
			END IF;
			--
			-- Determine how much to add, if any,
			-- to the new fund's allocation.
			--
			IF old_remaining > 0 THEN
				--
				-- In this case we're using the whole allocation, so use that amount
				-- amount directly instead of applying a currency translation and
				-- thereby inviting round-off errors.
				--
				source_addition := orig_allocated_amt;
			ELSIF source.currency_type = old_fund_currency THEN
				--
				-- In this case we don't need a round trip currency translation,
				-- thereby inviting round-off errors:
				--
				source_addition := curr_old_amt;
			ELSE 
				source_addition := trunc(
					curr_new_amt *
						acq.exchange_ratio( new_fund_currency, source.currency_type ),
					2 );
			END IF;
			--
			IF source_addition <> 0 THEN
				--
				-- Insert positive allocation for new fund in fund_allocation,
				-- converted to the currency of the founding source
				--
				INSERT INTO acq.fund_allocation (
					funding_source,
					fund,
					amount,
					allocator,
					note
				) VALUES (
					source.funding_source,
					new_fund,
					source_addition,
					user_id,
					'Transfer from fund ' || old_fund
				);
			END IF;
		END IF;
		--
		IF trunc( curr_old_amt, 2 ) <> 0
		OR trunc( curr_new_amt, 2 ) <> 0 THEN
			--
			-- Insert row in fund_transfer, using amounts in the currency of the funds
			--
			INSERT INTO acq.fund_transfer (
				src_fund,
				src_amount,
				dest_fund,
				dest_amount,
				transfer_user,
				note,
				funding_source_credit
			) VALUES (
				old_fund,
				trunc( curr_old_amt, 2 ),
				new_fund,
				trunc( curr_new_amt, 2 ),
				user_id,
				xfer_note,
				source.id
			);
		END IF;
		--
		if old_remaining <= 0 THEN
			EXIT;                   -- Nothing more to be transferred
		END IF;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_unit(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER
) RETURNS VOID AS $$
DECLARE
--
new_id      INT;
old_fund    RECORD;
org_found   BOOLEAN;
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
		SELECT TRUE INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id is invalid';
		END IF;
	END IF;
	--
	-- Loop over the applicable funds
	--
	FOR old_fund in SELECT * FROM acq.fund
	WHERE
		year = old_year
		AND propagate
		AND org = org_unit_id
	LOOP
		BEGIN
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
				old_fund.org,
				old_fund.name,
				old_year + 1,
				old_fund.currency_type,
				old_fund.code,
				old_fund.rollover,
				true,
				old_fund.balance_warning_percent,
				old_fund.balance_stop_percent
			)
			RETURNING id INTO new_id;
		EXCEPTION
			WHEN unique_violation THEN
				--RAISE NOTICE 'Fund % already propagated', old_fund.id;
				CONTINUE;
		END;
		--RAISE NOTICE 'Propagating fund % to fund %',
		--	old_fund.code, new_id;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER
) RETURNS VOID AS $$
DECLARE
--
new_id      INT;
old_fund    RECORD;
org_found   BOOLEAN;
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
		SELECT TRUE INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id is invalid';
		END IF;
	END IF;
	--
	-- Loop over the applicable funds
	--
	FOR old_fund in SELECT * FROM acq.fund
	WHERE
		year = old_year
		AND propagate
		AND org in (
			SELECT id FROM actor.org_unit_descendants( org_unit_id )
		)
	LOOP
		BEGIN
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
				old_fund.org,
				old_fund.name,
				old_year + 1,
				old_fund.currency_type,
				old_fund.code,
				old_fund.rollover,
				true,
				old_fund.balance_warning_percent,
				old_fund.balance_stop_percent
			)
			RETURNING id INTO new_id;
		EXCEPTION
			WHEN unique_violation THEN
				--RAISE NOTICE 'Fund % already propagated', old_fund.id;
				CONTINUE;
		END;
		--RAISE NOTICE 'Propagating fund % to fund %',
		--	old_fund.code, new_id;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_unit(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER
) RETURNS VOID AS $$
DECLARE
--
new_fund    INT;
new_year    INT := old_year + 1;
org_found   BOOL;
xfer_amount NUMERIC;
roll_fund   RECORD;
deb         RECORD;
detail      RECORD;
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
		    oldf.org = org_unit_id
 		and oldf.year = old_year
		and oldf.propagate
        and newf.year = new_year
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
			IF roll_fund.rollover THEN
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
					'Rollover'
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
		--
		-- Mark old fund as inactive, now that we've closed it
		--
		UPDATE acq.fund
		SET active = FALSE
		WHERE id = roll_fund.old_fund;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER
) RETURNS VOID AS $$
DECLARE
--
new_fund    INT;
new_year    INT := old_year + 1;
org_found   BOOL;
xfer_amount NUMERIC;
roll_fund   RECORD;
deb         RECORD;
detail      RECORD;
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
		AND oldf.org in (
			SELECT id FROM actor.org_unit_descendants( org_unit_id )
		)
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
			IF roll_fund.rollover THEN
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
					'Rollover'
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
		--
		-- Mark old fund as inactive, now that we've closed it
		--
		UPDATE acq.fund
		SET active = FALSE
		WHERE id = roll_fund.old_fund;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.remove_commas( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace($1, ',', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_whitespace( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(normalize_space($1), E'\\s+', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE TABLE acq.distribution_formula_application (
    id BIGSERIAL PRIMARY KEY,
    creator INT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    formula INT NOT NULL
        REFERENCES acq.distribution_formula(id) DEFERRABLE INITIALLY DEFERRED,
    lineitem INT NOT NULL
        REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX acqdfa_df_idx
    ON acq.distribution_formula_application(formula);
CREATE INDEX acqdfa_li_idx
    ON acq.distribution_formula_application(lineitem);
CREATE INDEX acqdfa_creator_idx
    ON acq.distribution_formula_application(creator);

CREATE TABLE acq.user_request_type (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE -- i18n-ize
);

INSERT INTO acq.user_request_type (id,label) VALUES (1, oils_i18n_gettext('1', 'Books', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (2, oils_i18n_gettext('2', 'Journal/Magazine & Newspaper Articles', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (3, oils_i18n_gettext('3', 'Audiobooks', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (4, oils_i18n_gettext('4', 'Music', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (5, oils_i18n_gettext('5', 'DVDs', 'aurt', 'label'));

SELECT SETVAL('acq.user_request_type_id_seq'::TEXT, 6);

CREATE TABLE acq.cancel_reason (
	id            SERIAL            PRIMARY KEY,
	org_unit      INTEGER           NOT NULL REFERENCES actor.org_unit( id )
	                                DEFERRABLE INITIALLY DEFERRED,
	label         TEXT              NOT NULL,
	description   TEXT              NOT NULL,
	keep_debits   BOOL              NOT NULL DEFAULT FALSE,
	CONSTRAINT acq_cancel_reason_one_per_org_unit UNIQUE( org_unit, label )
);

-- Reserve ids 1-999 for stock reasons
-- Reserve ids 1000-1999 for EDI reasons
-- 2000+ are available for staff to create

SELECT SETVAL('acq.cancel_reason_id_seq'::TEXT, 2000);

CREATE TABLE acq.user_request (
    id                  SERIAL  PRIMARY KEY,
    usr                 INT     NOT NULL REFERENCES actor.usr (id), -- requesting user
    hold                BOOL    NOT NULL DEFAULT TRUE,

    pickup_lib          INT     NOT NULL REFERENCES actor.org_unit (id), -- pickup lib
    holdable_formats    TEXT,           -- nullable, for use in hold creation
    phone_notify        TEXT,
    email_notify        BOOL    NOT NULL DEFAULT TRUE,
    lineitem            INT     REFERENCES acq.lineitem (id) ON DELETE CASCADE,
    eg_bib              BIGINT  REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    request_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- when they requested it
    need_before         TIMESTAMPTZ,    -- don't create holds after this
    max_fee             TEXT,

    request_type        INT     NOT NULL REFERENCES acq.user_request_type (id), 
    isxn                TEXT,
    title               TEXT,
    volume              TEXT,
    author              TEXT,
    article_title       TEXT,
    article_pages       TEXT,
    publisher           TEXT,
    location            TEXT,
    pubdate             TEXT,
    mentioned           TEXT,
    other_info          TEXT,
	cancel_reason       INT              REFERENCES acq.cancel_reason( id )
	                                     DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE acq.lineitem_alert_text (
	id               SERIAL         PRIMARY KEY,
	code             TEXT           NOT NULL,
	description      TEXT,
	owning_lib       INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT alert_one_code_per_org UNIQUE (code, owning_lib)
);

ALTER TABLE acq.lineitem_note
	ADD COLUMN alert_text    INT     REFERENCES acq.lineitem_alert_text(id)
	                                 DEFERRABLE INITIALLY DEFERRED;

-- add ON DELETE CASCADE clause

ALTER TABLE acq.lineitem_note
	DROP CONSTRAINT lineitem_note_lineitem_fkey;

ALTER TABLE acq.lineitem_note
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_note
	ADD COLUMN vendor_public BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE acq.invoice_method (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL -- i18n-ize
);
INSERT INTO acq.invoice_method (code,name) VALUES ('EDI',oils_i18n_gettext('EDI', 'EDI', 'acqim', 'name'));
INSERT INTO acq.invoice_method (code,name) VALUES ('PPR',oils_i18n_gettext('PPR', 'Paper', 'acqit', 'name'));

CREATE TABLE acq.invoice_payment_method (
	code      TEXT     PRIMARY KEY,
	name      TEXT     NOT NULL
);

CREATE TABLE acq.invoice (
    id             SERIAL      PRIMARY KEY,
    receiver       INT         NOT NULL REFERENCES actor.org_unit (id),
    provider       INT         NOT NULL REFERENCES acq.provider (id),
    shipper        INT         NOT NULL REFERENCES acq.provider (id),
    recv_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recv_method    TEXT        NOT NULL REFERENCES acq.invoice_method (code) DEFAULT 'EDI',
    inv_type       TEXT,       -- A "type" field is desired, but no idea what goes here
    inv_ident      TEXT        NOT NULL, -- vendor-supplied invoice id/number
	payment_auth   TEXT,
	payment_method TEXT        REFERENCES acq.invoice_payment_method (code)
	                           DEFERRABLE INITIALLY DEFERRED,
	note           TEXT,
    complete       BOOL        NOT NULL DEFAULT FALSE,
    CONSTRAINT inv_ident_once_per_provider UNIQUE(provider, inv_ident)
);

CREATE TABLE acq.invoice_entry (
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    lineitem        INT         REFERENCES acq.lineitem (id) ON UPDATE CASCADE ON DELETE SET NULL,
    inv_item_count  INT         NOT NULL, -- How many acqlids did they say they sent
    phys_item_count INT, -- and how many did staff count
    note            TEXT,
    billed_per_item BOOL,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2),
	amount_paid     NUMERIC (8,2)
);

CREATE TABLE acq.invoice_item_type (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL, -- i18n-ize
	prorate BOOL    NOT NULL DEFAULT FALSE
);

INSERT INTO acq.invoice_item_type (code,name) VALUES ('TAX',oils_i18n_gettext('TAX', 'Tax', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('PRO',oils_i18n_gettext('PRO', 'Processing Fee', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('SHP',oils_i18n_gettext('SHP', 'Shipping Charge', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('HND',oils_i18n_gettext('HND', 'Handling Charge', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('ITM',oils_i18n_gettext('ITM', 'Non-library Item', 'aiit', 'name'));
INSERT INTO acq.invoice_item_type (code,name) VALUES ('SUB',oils_i18n_gettext('SUB', 'Serial Subscription', 'aiit', 'name'));

CREATE TABLE acq.po_item (
	id              SERIAL      PRIMARY KEY,
	purchase_order  INT         REFERENCES acq.purchase_order (id)
	                            ON UPDATE CASCADE ON DELETE SET NULL
	                            DEFERRABLE INITIALLY DEFERRED,
	fund_debit      INT         REFERENCES acq.fund_debit (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	inv_item_type   TEXT        NOT NULL
	                            REFERENCES acq.invoice_item_type (code)
	                            DEFERRABLE INITIALLY DEFERRED,
	title           TEXT,
	author          TEXT,
	note            TEXT,
	estimated_cost  NUMERIC(8,2),
	fund            INT         REFERENCES acq.fund (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	target          BIGINT
);

CREATE TABLE acq.invoice_item ( -- for invoice-only debits: taxes/fees/non-bib items/etc
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON UPDATE CASCADE ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    fund_debit      INT         REFERENCES acq.fund_debit (id),
    inv_item_type   TEXT        NOT NULL REFERENCES acq.invoice_item_type (code),
    title           TEXT,
    author          TEXT,
    note            TEXT,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2),
    fund            INT         REFERENCES acq.fund (id)
                                DEFERRABLE INITIALLY DEFERRED,
    amount_paid     NUMERIC (8,2),
    po_item         INT         REFERENCES acq.po_item (id)
                                DEFERRABLE INITIALLY DEFERRED,
    target          BIGINT
);

CREATE TABLE acq.edi_message (
    id               SERIAL          PRIMARY KEY,
    account          INTEGER         REFERENCES acq.edi_account(id)
                                     DEFERRABLE INITIALLY DEFERRED,
    remote_file      TEXT,
    create_time      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    translate_time   TIMESTAMPTZ,
    process_time     TIMESTAMPTZ,
    error_time       TIMESTAMPTZ,
    status           TEXT            NOT NULL DEFAULT 'new'
                                     CONSTRAINT status_value CHECK
                                     ( status IN (
                                        'new',          -- needs to be translated
                                        'translated',   -- needs to be processed
                                        'trans_error',  -- error in translation step
                                        'processed',    -- needs to have remote_file deleted
                                        'proc_error',   -- error in processing step
                                        'delete_error', -- error in deletion
                                        'retry',        -- need to retry
                                        'complete'      -- done
                                     )),
    edi              TEXT,
    jedi             TEXT,
    error            TEXT,
    purchase_order   INT             REFERENCES acq.purchase_order
                                     DEFERRABLE INITIALLY DEFERRED,
    message_type     TEXT            NOT NULL CONSTRAINT valid_message_type
                                     CHECK ( message_type IN (
                                        'ORDERS',
                                        'ORDRSP',
                                        'INVOIC',
                                        'OSTENQ',
                                        'OSTRPT'
                                     ))
);

ALTER TABLE actor.org_address ADD COLUMN san TEXT;

ALTER TABLE acq.provider_address
	ADD COLUMN fax_phone TEXT;

ALTER TABLE acq.provider_contact_address
	ADD COLUMN fax_phone TEXT;

CREATE TABLE acq.provider_note (
    id      SERIAL              PRIMARY KEY,
    provider    INT             NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    editor      INT             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    edit_time   TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    value       TEXT            NOT NULL
);
CREATE INDEX acq_pro_note_pro_idx      ON acq.provider_note ( provider );
CREATE INDEX acq_pro_note_creator_idx  ON acq.provider_note ( creator );
CREATE INDEX acq_pro_note_editor_idx   ON acq.provider_note ( editor );

-- For each fund: the total allocation from all sources, in the
-- currency of the fund (or 0 if there are no allocations)

CREATE VIEW acq.all_fund_allocation_total AS
SELECT
    f.id AS fund,
    COALESCE( SUM( a.amount * acq.exchange_ratio(
        s.currency_type, f.currency_type))::numeric(100,2), 0 )
    AS amount
FROM
    acq.fund f
        LEFT JOIN acq.fund_allocation a
            ON a.fund = f.id
        LEFT JOIN acq.funding_source s
            ON a.funding_source = s.id
GROUP BY
    f.id;

-- For every fund: the total encumbrances (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_encumbrance_total AS
SELECT
	f.id AS fund,
	COALESCE( encumb.amount, 0 ) AS amount
FROM
	acq.fund AS f
		LEFT JOIN (
			SELECT
				fund,
				sum( amount ) AS amount
			FROM
				acq.fund_debit
			WHERE
				encumbrance
			GROUP BY fund
		) AS encumb
			ON f.id = encumb.fund;

-- For every fund: the total spent (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_spent_total AS
SELECT
    f.id AS fund,
    COALESCE( spent.amount, 0 ) AS amount
FROM
    acq.fund AS f
        LEFT JOIN (
            SELECT
                fund,
                sum( amount ) AS amount
            FROM
                acq.fund_debit
            WHERE
                NOT encumbrance
            GROUP BY fund
        ) AS spent
            ON f.id = spent.fund;

-- For each fund: the amount not yet spent, in the currency
-- of the fund.  May include encumbrances.

CREATE VIEW acq.all_fund_spent_balance AS
SELECT
	c.fund,
	c.amount - d.amount AS amount
FROM acq.all_fund_allocation_total c
    LEFT JOIN acq.all_fund_spent_total d USING (fund);

-- For each fund: the amount neither spent nor encumbered,
-- in the currency of the fund

CREATE VIEW acq.all_fund_combined_balance AS
SELECT
     a.fund,
     a.amount - COALESCE( c.amount, 0 ) AS amount
FROM
     acq.all_fund_allocation_total a
        LEFT OUTER JOIN (
            SELECT
                fund,
                SUM( amount ) AS amount
            FROM
                acq.fund_debit
            GROUP BY
                fund
        ) AS c USING ( fund );

CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_note SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
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

    -- Finally, delete the source user
    DELETE FROM actor.usr WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

-- The "add" trigger functions should protect against existing NULLed values, just in case
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_add () RETURNS TRIGGER AS $$
BEGIN
    IF NOT NEW.voided THEN
        UPDATE  money.materialized_billable_xact_summary
          SET   total_owed = COALESCE(total_owed, 0.0::numeric) + NEW.amount,
            last_billing_ts = NEW.billing_ts,
            last_billing_note = NEW.note,
            last_billing_type = NEW.billing_type,
            balance_owed = balance_owed + NEW.amount
          WHERE id = NEW.xact;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION money.materialized_summary_payment_add () RETURNS TRIGGER AS $$
BEGIN
    IF NOT NEW.voided THEN
        UPDATE  money.materialized_billable_xact_summary
          SET   total_paid = COALESCE(total_paid, 0.0::numeric) + NEW.amount,
            last_payment_ts = NEW.payment_ts,
            last_payment_note = NEW.note,
            last_payment_type = TG_ARGV[0],
            balance_owed = balance_owed - NEW.amount
          WHERE id = NEW.xact;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- Refresh the mat view with the corrected underlying view
TRUNCATE money.materialized_billable_xact_summary;
INSERT INTO money.materialized_billable_xact_summary SELECT * FROM money.billable_xact_summary;

-- Now redefine the view as a window onto the materialized view
CREATE OR REPLACE VIEW money.billable_xact_summary AS
    SELECT * FROM money.materialized_billable_xact_summary;

CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_nd(
    user_id    IN INTEGER,
    perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted directly (not through inheritance from a parent
-- org unit).
--
-- The permissions apply to a minimum depth of the org unit hierarchy,
-- for the org unit(s) to which the user is assigned.  (They also apply
-- to the subordinates of those org units, but we don't report the
-- subordinates here.)
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- defines which users belong to which org units.  I.e. we ignore the
-- home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
    b_super       BOOLEAN;
    n_perm        INTEGER;
    n_min_depth   INTEGER;
    n_work_ou     INTEGER;
    n_curr_ou     INTEGER;
    n_depth       INTEGER;
    n_curr_depth  INTEGER;
BEGIN
    --
    -- Check for superuser
    --
    SELECT INTO b_super
        super_user
    FROM
        actor.usr
    WHERE
        id = user_id;
    --
    IF NOT FOUND THEN
        return;             -- No user?  No permissions.
    ELSIF b_super THEN
        --
        -- Super user has all permissions everywhere
        --
        FOR n_work_ou IN
            SELECT
                id
            FROM
                actor.org_unit
            WHERE
                parent_ou IS NULL
        LOOP
            RETURN NEXT n_work_ou;
        END LOOP;
        RETURN;
    END IF;
    --
    -- Translate the permission name
    -- to a numeric permission id
    --
    SELECT INTO n_perm
        id
    FROM
        permission.perm_list
    WHERE
        code = perm_code;
    --
    IF NOT FOUND THEN
        RETURN;               -- No such permission
    END IF;
    --
    -- Find the highest-level org unit (i.e. the minimum depth)
    -- to which the permission is applied for this user
    --
    -- This query is modified from the one in permission.usr_perms().
    --
    SELECT INTO n_min_depth
        min( depth )
    FROM    (
        SELECT depth
          FROM permission.usr_perm_map upm
         WHERE upm.usr = user_id
           AND (upm.perm = n_perm OR upm.perm = -1)
                    UNION
        SELECT  gpm.depth
          FROM  permission.grp_perm_map gpm
          WHERE (gpm.perm = n_perm OR gpm.perm = -1)
            AND gpm.grp IN (
               SELECT   (permission.grp_ancestors(
                    (SELECT profile FROM actor.usr WHERE id = user_id)
                )).id
            )
                    UNION
        SELECT  p.depth
          FROM  permission.grp_perm_map p
          WHERE (p.perm = n_perm OR p.perm = -1)
            AND p.grp IN (
                SELECT (permission.grp_ancestors(m.grp)).id
                FROM   permission.usr_grp_map m
                WHERE  m.usr = user_id
            )
    ) AS x;
    --
    IF NOT FOUND THEN
        RETURN;                -- No such permission for this user
    END IF;
    --
    -- Identify the org units to which the user is assigned.  Note that
    -- we pay no attention to the home_ou column in actor.usr.
    --
    FOR n_work_ou IN
        SELECT
            work_ou
        FROM
            permission.usr_work_ou_map
        WHERE
            usr = user_id
    LOOP            -- For each org unit to which the user is assigned
        --
        -- Determine the level of the org unit by a lookup in actor.org_unit_type.
        -- We take it on faith that this depth agrees with the actual hierarchy
        -- defined in actor.org_unit.
        --
        SELECT INTO n_depth
            type.depth
        FROM
            actor.org_unit_type type
                INNER JOIN actor.org_unit ou
                    ON ( ou.ou_type = type.id )
        WHERE
            ou.id = n_work_ou;
        --
        IF NOT FOUND THEN
            CONTINUE;        -- Maybe raise exception?
        END IF;
        --
        -- Compare the depth of the work org unit to the
        -- minimum depth, and branch accordingly
        --
        IF n_depth = n_min_depth THEN
            --
            -- The org unit is at the right depth, so return it.
            --
            RETURN NEXT n_work_ou;
        ELSIF n_depth > n_min_depth THEN
            --
            -- Traverse the org unit tree toward the root,
            -- until you reach the minimum depth determined above
            --
            n_curr_depth := n_depth;
            n_curr_ou := n_work_ou;
            WHILE n_curr_depth > n_min_depth LOOP
                SELECT INTO n_curr_ou
                    parent_ou
                FROM
                    actor.org_unit
                WHERE
                    id = n_curr_ou;
                --
                IF FOUND THEN
                    n_curr_depth := n_curr_depth - 1;
                ELSE
                    --
                    -- This can happen only if the hierarchy defined in
                    -- actor.org_unit is corrupted, or out of sync with
                    -- the depths defined in actor.org_unit_type.
                    -- Maybe we should raise an exception here, instead
                    -- of silently ignoring the problem.
                    --
                    n_curr_ou = NULL;
                    EXIT;
                END IF;
            END LOOP;
            --
            IF n_curr_ou IS NOT NULL THEN
                RETURN NEXT n_curr_ou;
            END IF;
        ELSE
            --
            -- The permission applies only at a depth greater than the work org unit.
            -- Use connectby() to find all dependent org units at the specified depth.
            --
            FOR n_curr_ou IN
                SELECT ou::INTEGER
                FROM connectby(
                        'actor.org_unit',         -- table name
                        'id',                     -- key column
                        'parent_ou',              -- recursive foreign key
                        n_work_ou::TEXT,          -- id of starting point
                        (n_min_depth - n_depth)   -- max depth to search, relative
                    )                             --   to starting point
                    AS t(
                        ou text,            -- dependent org unit
                        parent_ou text,     -- (ignore)
                        level int           -- depth relative to starting point
                    )
                WHERE
                    level = n_min_depth - n_depth
            LOOP
                RETURN NEXT n_curr_ou;
            END LOOP;
        END IF;
        --
    END LOOP;
    --
    RETURN;
    --
END;
$$ LANGUAGE 'plpgsql';

ALTER TABLE acq.purchase_order
	ADD COLUMN cancel_reason INT
		REFERENCES acq.cancel_reason( id )
	    DEFERRABLE INITIALLY DEFERRED,
	ADD COLUMN prepayment_required BOOLEAN NOT NULL DEFAULT FALSE;

-- Build the history table and lifecycle view
-- for acq.purchase_order

SELECT acq.create_acq_auditor ( 'acq', 'purchase_order' );

CREATE INDEX acq_po_hist_id_idx            ON acq.acq_purchase_order_history( id );

ALTER TABLE acq.lineitem
	ADD COLUMN cancel_reason INT
		REFERENCES acq.cancel_reason( id )
	    DEFERRABLE INITIALLY DEFERRED,
	ADD COLUMN estimated_unit_price NUMERIC,
	ADD COLUMN claim_policy INT
		REFERENCES acq.claim_policy
		DEFERRABLE INITIALLY DEFERRED,
	ALTER COLUMN eg_bib_id SET DATA TYPE bigint;

-- Build the history table and lifecycle view
-- for acq.lineitem

SELECT acq.create_acq_auditor ( 'acq', 'lineitem' );
CREATE INDEX acq_lineitem_hist_id_idx            ON acq.acq_lineitem_history( id );

ALTER TABLE acq.lineitem_detail
	ADD COLUMN cancel_reason        INT REFERENCES acq.cancel_reason( id )
	                                    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_detail
	DROP CONSTRAINT lineitem_detail_lineitem_fkey;

ALTER TABLE acq.lineitem_detail
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem_detail DROP CONSTRAINT lineitem_detail_eg_copy_id_fkey;

INSERT INTO acq.cancel_reason ( id, org_unit, label, description ) VALUES (
	1, 1, 'invalid_isbn', oils_i18n_gettext( 1, 'ISBN is unrecognizable', 'acqcr', 'label' ));

INSERT INTO acq.cancel_reason ( id, org_unit, label, description ) VALUES (
	2, 1, 'postpone', oils_i18n_gettext( 2, 'Title has been postponed', 'acqcr', 'label' ));

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use strict;

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    my $force_add = shift || 0;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}{sf}} ) {
            for my $from_field ($source_r->field( $f )) {
                my @tos = $target_r->field( $f );
                if (!@tos) {
                    next if (exists($fields{$f}{match}) and !$force_add);
                    my @new_fields = map { $_->clone } $source_r->field( $f );
                    $target_r->insert_fields_ordered( @new_fields );
                } else {
                    for my $to_field (@tos) {
                        if (exists($fields{$f}{match})) {
                            next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
                        }
                        my @new_sf = map { ($_ => $from_field->subfield($_)) } @{$fields{$f}{sf}};
                        $to_field->add_subfields( @new_sf );
                    }
                }
            }
        } else {
            my @new_fields = map { $_->clone } $source_r->field( $f );
            $target_r->insert_fields_ordered( @new_fields );
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( $1, $2, $3, 0 );
$_$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use strict;

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        for my $to_field ($r->field( $f )) {
            if (exists($fields{$f}{match})) {
                next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
            }

            if ( @{$fields{$f}{sf}} ) {
                $to_field->delete_subfield(code => $fields{$f}{sf});
            } else {
                $r->delete_field( $to_field );
            }
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.replace_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
DECLARE
    xml_output TEXT;
    parsed_target TEXT;
    curr_field TEXT;
BEGIN

    parsed_target := vandelay.strip_field( target_xml, ''); -- this dance normalizes the format of the xml for the IF below

    FOR curr_field IN SELECT UNNEST( STRING_TO_ARRAY(field, ',') ) LOOP -- naive split, but it's the same we use in the perl

        xml_output := vandelay.strip_field( parsed_target, curr_field);

        IF xml_output <> parsed_target  AND curr_field ~ E'~' THEN
            -- we removed something, and there was a regexp restriction in the curr_field definition, so proceed
            xml_output := vandelay.add_field( xml_output, source_xml, curr_field, 1 );
        ELSIF curr_field !~ E'~' THEN
            -- No regexp restriction, add the curr_field
            xml_output := vandelay.add_field( xml_output, source_xml, curr_field, 0 );
        END IF;

        parsed_target := xml_output; -- in prep for any following loop iterations

    END LOOP;

    RETURN xml_output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.preserve_field ( incumbent_xml TEXT, incoming_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( vandelay.strip_field( $2, $3), $1, $3 );
$_$ LANGUAGE SQL;

CREATE VIEW action.unfulfilled_hold_max_loop AS
	SELECT  hold,
	        max(count) AS max
	FROM    action.unfulfilled_hold_loops
	GROUP BY 1;

ALTER TABLE acq.lineitem_attr
	DROP CONSTRAINT lineitem_attr_lineitem_fkey;

ALTER TABLE acq.lineitem_attr
	ADD FOREIGN KEY (lineitem) REFERENCES acq.lineitem( id )
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.po_note
	ADD COLUMN vendor_public BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE vandelay.merge_profile (
    id              BIGSERIAL   PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    add_spec        TEXT,
    replace_spec    TEXT,
    strip_spec      TEXT,
    preserve_spec   TEXT,
    CONSTRAINT vand_merge_prof_owner_name_idx UNIQUE (owner,name),
    CONSTRAINT add_replace_strip_or_preserve CHECK ((preserve_spec IS NOT NULL OR replace_spec IS NOT NULL) OR (preserve_spec IS NULL AND replace_spec IS NULL))
);

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr        RECORD;
    attr_def    RECORD;
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT * INTO attr_def FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr_def IS NOT NULL AND attr_def.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr_def.xpath, attr_def.remove);

        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
            SELECT * INTO attr FROM vandelay.queued_bib_record_attr WHERE record = NEW.id and field = attr_def.id LIMIT 1;
            IF exact_id IS NOT NULL THEN
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, exact_id);
            END IF;
        END IF;
    END IF;

    IF exact_id IS NULL THEN
        FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP

            -- All numbers? check for an id match
            IF (attr.attr_value ~ $r$^\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- Looks like an ISBN? check for an isbn match
            IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
                FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE LOWER('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
                    PERFORM id FROM biblio.record_entry WHERE id = eg_rec.record AND deleted IS FALSE;
                    IF FOUND THEN
                        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('isbn', attr.id, NEW.id, eg_rec.record);
                    END IF;
                END LOOP;

                -- subcheck for isbn-as-tcn
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = 'i' || attr.attr_value AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for an OCLC tcn_value match
            IF (attr.attr_value ~ $r$^o\d+$$r$) THEN
                FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = regexp_replace(attr.attr_value,'^o','ocm') AND deleted IS FALSE LOOP
                    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
                END LOOP;
            END IF;

            -- check for a direct tcn_value match
            FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = attr.attr_value AND deleted IS FALSE LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
            END LOOP;

            -- check for a direct item barcode match
            FOR eg_rec IN
                    SELECT  DISTINCT b.*
                      FROM  biblio.record_entry b
                            JOIN asset.call_number cn ON (cn.record = b.id)
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cp.barcode = attr.attr_value AND cp.deleted IS FALSE
            LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
            END LOOP;

        END LOOP;
    END IF;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_xml TEXT, source_xml TEXT, add_rule TEXT, replace_preserve_rule TEXT, strip_rule TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.replace_field( vandelay.add_field( vandelay.strip_field( $1, $5) , $2, $3 ), $2, $4);
$_$ LANGUAGE SQL;

CREATE TYPE vandelay.compile_profile AS (add_rule TEXT, replace_rule TEXT, preserve_rule TEXT, strip_rule TEXT);
CREATE OR REPLACE FUNCTION vandelay.compile_profile ( incoming_xml TEXT ) RETURNS vandelay.compile_profile AS $_$
DECLARE
    output              vandelay.compile_profile%ROWTYPE;
    profile             vandelay.merge_profile%ROWTYPE;
    profile_tmpl        TEXT;
    profile_tmpl_owner  TEXT;
    add_rule            TEXT := '';
    strip_rule          TEXT := '';
    replace_rule        TEXT := '';
    preserve_rule       TEXT := '';

BEGIN

    profile_tmpl := (oils_xpath('//*[@tag="905"]/*[@code="t"]/text()',incoming_xml))[1];
    profile_tmpl_owner := (oils_xpath('//*[@tag="905"]/*[@code="o"]/text()',incoming_xml))[1];

    IF profile_tmpl IS NOT NULL AND profile_tmpl <> '' AND profile_tmpl_owner IS NOT NULL AND profile_tmpl_owner <> '' THEN
        SELECT  p.* INTO profile
          FROM  vandelay.merge_profile p
                JOIN actor.org_unit u ON (u.id = p.owner)
          WHERE p.name = profile_tmpl
                AND u.shortname = profile_tmpl_owner;

        IF profile.id IS NOT NULL THEN
            add_rule := COALESCE(profile.add_spec,'');
            strip_rule := COALESCE(profile.strip_spec,'');
            replace_rule := COALESCE(profile.replace_spec,'');
            preserve_rule := COALESCE(profile.preserve_spec,'');
        END IF;
    END IF;

    add_rule := add_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="a"]/text()',incoming_xml),','),'');
    strip_rule := strip_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="d"]/text()',incoming_xml),','),'');
    replace_rule := replace_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="r"]/text()',incoming_xml),','),'');
    preserve_rule := preserve_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="p"]/text()',incoming_xml),','),'');

    output.add_rule := BTRIM(add_rule,',');
    output.replace_rule := BTRIM(replace_rule,',');
    output.strip_rule := BTRIM(strip_rule,',');
    output.preserve_rule := BTRIM(preserve_rule,',');

    RETURN output;
END;
$_$ LANGUAGE PLPGSQL;

-- Template-based marc munging functions
CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
      WHERE b.id = eg_id
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for template or bib record';
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF NOT FOUND THEN
        -- RAISE NOTICE 'update of biblio.record_entry failed';
        RETURN FALSE;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT) RETURNS BOOL AS $$
    SELECT vandelay.template_overlay_bib_record( $1, $2, NULL);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;

        editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

        IF editor_string IS NOT NULL AND editor_string <> '' THEN
            SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

            IF editor_id IS NULL THEN
                SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
            END IF;

            IF editor_id IS NOT NULL THEN
                UPDATE biblio.record_entry SET editor = editor_id WHERE id = eg_id;
            END IF;
        END IF;

        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    match_attr      vandelay.bib_attr_definition%ROWTYPE;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO match_count FROM vandelay.bib_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    SELECT  d.* INTO match_attr
      FROM  vandelay.bib_attr_definition d
            JOIN vandelay.queued_bib_record_attr a ON (a.field = d.id)
            JOIN vandelay.bib_match m ON (m.matched_attr = a.id)
      WHERE m.queued_record = import_id;

    IF NOT (match_attr.xpath ~ '@tag="901"' AND match_attr.xpath ~ '@code="c"') THEN
        -- RAISE NOTICE 'not a 901c match: %', match_attr.xpath;
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    IF eg_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_bib_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_bib_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_bib_record( queued_record.id, merge_profile_id ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_bib_queue( $1, NULL );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.overlay_authority_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  authority.record_entry b
            JOIN vandelay.authority_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.authority_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or authority record';
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  authority.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF FOUND THEN
        UPDATE  vandelay.queued_authority_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;
        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of authority.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
BEGIN
    SELECT COUNT(*) INTO match_count FROM vandelay.authority_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    IF eg_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_authority_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_authority_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_authority_record( queued_record.id, merge_profile_id ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_authority_queue( $1, NULL );
$$ LANGUAGE SQL;

CREATE TYPE vandelay.tcn_data AS (tcn TEXT, tcn_source TEXT, used BOOL);
CREATE OR REPLACE FUNCTION vandelay.find_bib_tcn_data ( xml TEXT ) RETURNS SETOF vandelay.tcn_data AS $_$
DECLARE
    eg_tcn          TEXT;
    eg_tcn_source   TEXT;
    output          vandelay.tcn_data%ROWTYPE;
BEGIN

    -- 001/003
    eg_tcn := BTRIM((oils_xpath('//*[@tag="001"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="003"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 901 ab
    eg_tcn := BTRIM((oils_xpath('//*[@tag="901"]/*[@code="a"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="901"]/*[@code="b"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 039 ab
    eg_tcn := BTRIM((oils_xpath('//*[@tag="039"]/*[@code="a"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="039"]/*[@code="b"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 020 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="020"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'ISBN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 022 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="022"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'ISSN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 010 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="010"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'LCCN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 035 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="035"]/*[@code="a"]/text()',xml))[1], $re$^.*?(\w+)$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'System Legacy';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    RETURN;
END;
$_$ LANGUAGE PLPGSQL;

CREATE INDEX claim_lid_idx ON acq.claim( lineitem_detail );

CREATE OR REPLACE RULE protect_bib_rec_delete AS ON DELETE TO biblio.record_entry DO INSTEAD (UPDATE biblio.record_entry SET deleted = TRUE WHERE OLD.id = biblio.record_entry.id; DELETE FROM metabib.metarecord_source_map WHERE source = OLD.id);

-- remove invalid data ... there was no fkey before, boo
DELETE FROM metabib.series_field_entry WHERE source NOT IN (SELECT id FROM biblio.record_entry);
DELETE FROM metabib.series_field_entry WHERE field NOT IN (SELECT id FROM config.metabib_field);

CREATE INDEX metabib_title_field_entry_value_idx ON metabib.title_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_author_field_entry_value_idx ON metabib.author_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_subject_field_entry_value_idx ON metabib.subject_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_keyword_field_entry_value_idx ON metabib.keyword_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_series_field_entry_value_idx ON metabib.series_field_entry (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;

CREATE INDEX metabib_author_field_entry_source_idx ON metabib.author_field_entry (source);
CREATE INDEX metabib_keyword_field_entry_source_idx ON metabib.keyword_field_entry (source);
CREATE INDEX metabib_title_field_entry_source_idx ON metabib.title_field_entry (source);
CREATE INDEX metabib_series_field_entry_source_idx ON metabib.series_field_entry (source);

ALTER TABLE metabib.series_field_entry
	ADD CONSTRAINT metabib_series_field_entry_source_pkey FOREIGN KEY (source)
		REFERENCES biblio.record_entry (id)
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE metabib.series_field_entry
	ADD CONSTRAINT metabib_series_field_entry_field_pkey FOREIGN KEY (field)
		REFERENCES config.metabib_field (id)
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE acq.claim_policy_action (
	id              SERIAL       PRIMARY KEY,
	claim_policy    INT          NOT NULL REFERENCES acq.claim_policy
                                 ON DELETE CASCADE
	                             DEFERRABLE INITIALLY DEFERRED,
	action_interval INTERVAL     NOT NULL,
	action          INT          NOT NULL REFERENCES acq.claim_event_type
	                             DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT action_sequence UNIQUE (claim_policy, action_interval)
);

CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $function$
DECLARE
    value       TEXT; 
    atype       TEXT; 
    prov        INT;
    pos         INT;
    adef        RECORD;
    xpath_string    TEXT;
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
                    SELECT extract_acq_marc_field(id, xpath_string || '[' || pos || ']', adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;
      
                    IF (value IS NOT NULL AND value <> '') THEN
                        INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
                            VALUES (NEW.id, adef.id, atype, adef.code, value);
                    ELSE
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

UPDATE config.metabib_field SET label = name;
ALTER TABLE config.metabib_field ALTER COLUMN label SET NOT NULL;

ALTER TABLE config.metabib_field ADD CONSTRAINT metabib_field_field_class_fkey
	 FOREIGN KEY (field_class) REFERENCES config.metabib_class (name);

ALTER TABLE config.metabib_field DROP CONSTRAINT metabib_field_field_class_check;

ALTER TABLE config.metabib_field ADD CONSTRAINT metabib_field_format_fkey FOREIGN KEY (format) REFERENCES config.xml_transform (name);

CREATE TABLE config.metabib_search_alias (
    alias       TEXT    PRIMARY KEY,
    field_class TEXT    NOT NULL REFERENCES config.metabib_class (name),
    field       INT     REFERENCES config.metabib_field (id)
);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('kw','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.keyword','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.publisher','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.identifier','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.subjecttitle','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.genre','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.edition','keyword');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('srw.serverchoice','keyword');

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('au','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('name','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('creator','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.author','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.name','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.creator','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.contributor','author');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('bib.name','author');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonal','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonalfamily','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namepersonalgiven','author',8);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.namecorporate','author',7);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.nameconference','author',9);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('ti','title');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.title','title');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.title','title');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleabbreviated','title',2);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleuniform','title',5);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titletranslated','title',3);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titlealternative','title',4);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.title','title',2);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('su','subject');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.subject','subject');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.subject','subject');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectplace','subject',11);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectname','subject',12);

INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('se','series');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('eg.series','series');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.titleseries','series',1);

UPDATE config.metabib_field SET facet_field=TRUE WHERE id = 1;
UPDATE config.metabib_field SET xpath=$$//mods32:mods/mods32:name[@type='corporate' and mods32:role/mods32:roleTerm[text()='creator']]$$, facet_field=TRUE, facet_xpath=$$*[local-name()='namePart']$$ WHERE id = 7;
UPDATE config.metabib_field SET xpath=$$//mods32:mods/mods32:name[@type='personal' and mods32:role/mods32:roleTerm[text()='creator']]$$, facet_field=TRUE, facet_xpath=$$*[local-name()='namePart']$$ WHERE id = 8;
UPDATE config.metabib_field SET xpath=$$//mods32:mods/mods32:name[@type='conference' and mods32:role/mods32:roleTerm[text()='creator']]$$, facet_field=TRUE, facet_xpath=$$*[local-name()='namePart']$$ WHERE id = 9;
UPDATE config.metabib_field SET xpath=$$//mods32:mods/mods32:name[@type='personal' and not(mods32:role)]$$, facet_field=TRUE, facet_xpath=$$*[local-name()='namePart']$$ WHERE id = 10;

UPDATE config.metabib_field SET facet_field=TRUE WHERE id = 11;
UPDATE config.metabib_field SET facet_field=TRUE , facet_xpath=$$*[local-name()='namePart']$$ WHERE id = 12;
UPDATE config.metabib_field SET facet_field=TRUE WHERE id = 13;
UPDATE config.metabib_field SET facet_field=TRUE WHERE id = 14;

CREATE INDEX metabib_rec_descriptor_item_type_idx ON metabib.rec_descriptor (item_type);
CREATE INDEX metabib_rec_descriptor_item_form_idx ON metabib.rec_descriptor (item_form);
CREATE INDEX metabib_rec_descriptor_bib_level_idx ON metabib.rec_descriptor (bib_level);
CREATE INDEX metabib_rec_descriptor_control_type_idx ON metabib.rec_descriptor (control_type);
CREATE INDEX metabib_rec_descriptor_char_encoding_idx ON metabib.rec_descriptor (char_encoding);
CREATE INDEX metabib_rec_descriptor_enc_level_idx ON metabib.rec_descriptor (enc_level);
CREATE INDEX metabib_rec_descriptor_audience_idx ON metabib.rec_descriptor (audience);
CREATE INDEX metabib_rec_descriptor_lit_form_idx ON metabib.rec_descriptor (lit_form);
CREATE INDEX metabib_rec_descriptor_cat_form_idx ON metabib.rec_descriptor (cat_form);
CREATE INDEX metabib_rec_descriptor_pub_status_idx ON metabib.rec_descriptor (pub_status);
CREATE INDEX metabib_rec_descriptor_item_lang_idx ON metabib.rec_descriptor (item_lang);
CREATE INDEX metabib_rec_descriptor_vr_format_idx ON metabib.rec_descriptor (vr_format);
CREATE INDEX metabib_rec_descriptor_date1_idx ON metabib.rec_descriptor (date1);
CREATE INDEX metabib_rec_descriptor_dates_idx ON metabib.rec_descriptor (date1,date2);

CREATE TABLE asset.opac_visible_copies (
  id        BIGINT primary key, -- copy id
  record    BIGINT,
  circ_lib  INTEGER
);
COMMENT ON TABLE asset.opac_visible_copies IS $$
Materialized view of copies that are visible in the OPAC, used by
search.query_parser_fts() to speed up OPAC visibility checks on large
databases.  Contents are maintained by a set of triggers.
$$;
CREATE INDEX opac_visible_copies_idx1 on asset.opac_visible_copies (record, circ_lib);

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
    staff           BOOL
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];

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
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

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
                AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
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
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all status-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all copy_location-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  asset.call_number cn
                  WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF FOUND THEN
                    -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
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

ALTER TABLE biblio.record_entry ADD COLUMN owner INT;
ALTER TABLE biblio.record_entry
	 ADD CONSTRAINT biblio_record_entry_owner_fkey FOREIGN KEY (owner)
	 REFERENCES actor.org_unit (id)
	 DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE biblio.record_entry ADD COLUMN share_depth INT;

ALTER TABLE auditor.biblio_record_entry_history ADD COLUMN owner INT;
ALTER TABLE auditor.biblio_record_entry_history ADD COLUMN share_depth INT;

DROP VIEW auditor.biblio_record_entry_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'biblio', 'record_entry' );

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT COALESCE(SUBSTRING( $1 FROM $_$^\S+$_$), '');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.normalize_space( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace($1, E'\\n', ' ', 'g'), E'(?:^\\s+)|(\\s+$)', '', 'g'), E'\\s+', ' ', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_diacritics( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFD(shift);
    $x =~ s/\pM+//go;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.entityize( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFC(shift);
    $x =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
    cur_org := org_id;
    LOOP
        SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
        IF FOUND THEN
            RETURN NEXT setting;
        END IF;
        SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
        EXIT WHEN cur_org IS NULL;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

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
                                    '//*[@tag="' || tag || '"][position()=' || i || ']/*/@code|' ||
                                        '//*[@tag="' || tag || '"][position()=' || i || ']/*[@code]',
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

CREATE OR REPLACE FUNCTION oils_i18n_xlate ( keytable TEXT, keyclass TEXT, keycol TEXT, identcol TEXT, keyvalue TEXT, raw_locale TEXT ) RETURNS TEXT AS $func$
DECLARE
    locale      TEXT := REGEXP_REPLACE( REGEXP_REPLACE( raw_locale, E'[;, ].+$', '' ), E'_', '-', 'g' );
    language    TEXT := REGEXP_REPLACE( locale, E'-.+$', '' );
    result      config.i18n_core%ROWTYPE;
    fallback    TEXT;
    keyfield    TEXT := keyclass || '.' || keycol;
BEGIN

    -- Try the full locale
    SELECT  * INTO result
      FROM  config.i18n_core
      WHERE fq_field = keyfield
            AND identity_value = keyvalue
            AND translation = locale;

    -- Try just the language
    IF NOT FOUND THEN
        SELECT  * INTO result
          FROM  config.i18n_core
          WHERE fq_field = keyfield
                AND identity_value = keyvalue
                AND translation = language;
    END IF;

    -- Fall back to the string we passed in in the first place
    IF NOT FOUND THEN
    EXECUTE
            'SELECT ' ||
                keycol ||
            ' FROM ' || keytable ||
            ' WHERE ' || identcol || ' = ' || quote_literal(keyvalue)
                INTO fallback;
        RETURN fallback;
    END IF;

    RETURN result.string;
END;
$func$ LANGUAGE PLPGSQL STABLE;

SELECT auditor.create_auditor ( 'acq', 'invoice' );

SELECT auditor.create_auditor ( 'acq', 'invoice_item' );

SELECT auditor.create_auditor ( 'acq', 'invoice_entry' );

INSERT INTO acq.cancel_reason ( id, org_unit, label, description, keep_debits ) VALUES (
    3, 1, 'delivered_but_lost',
    oils_i18n_gettext( 2, 'Delivered but not received; presumed lost', 'acqcr', 'label' ), TRUE );

CREATE TABLE config.global_flag (
    label   TEXT    NOT NULL
) INHERITS (config.internal_flag);
ALTER TABLE config.global_flag ADD PRIMARY KEY (name);

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'cat.bib.use_id_for_tcn',
        oils_i18n_gettext(
            'cat.bib.use_id_for_tcn',
            'Cat: Use Internal ID for TCN Value',
            'cgf', 
            'label'
        ),
        TRUE
    );

-- resolves performance issue noted by EG Indiana

CREATE INDEX scecm_owning_copy_idx ON asset.stat_cat_entry_copy_map(owning_copy);

INSERT INTO config.metabib_class ( name, label ) VALUES ( 'identifier', oils_i18n_gettext('identifier', 'Identifier', 'cmc', 'name') );

-- 1.6 included stock indexes from 1 through 15, but didn't increase the
-- sequence value to leave room for additional stock indexes in subsequent
-- releases (hello!), so custom added indexes will conflict with these.

-- The following function changes the ID of an existing custom index
-- (and any references to that index) to the target ID; if no target ID
-- is supplied, then it adds 100 to the source ID. So this could break if a site
-- has custom indexes at both 16 and 116, for example - but if that's the
-- case anywhere, I'm throwing my hands up in surrender:

CREATE OR REPLACE FUNCTION config.modify_metabib_field(source INT, target INT) RETURNS INT AS $func$
DECLARE
    f_class TEXT;
    check_id INT;
    target_id INT;
BEGIN
    SELECT field_class INTO f_class FROM config.metabib_field WHERE id = source;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    IF target IS NULL THEN
        target_id = source + 100;
    ELSE
        target_id = target;
    END IF;
    SELECT id FROM config.metabib_field INTO check_id WHERE id = target_id;
    IF FOUND THEN
        RAISE NOTICE 'Cannot bump config.metabib_field.id from % to %; the target ID already exists.', source, target_id;
        RETURN 0;
    END IF;
    UPDATE config.metabib_field SET id = target_id WHERE id = source;
    EXECUTE ' UPDATE metabib.' || f_class || '_field_entry SET field = ' || target_id || ' WHERE field = ' || source;
    UPDATE config.metabib_field_index_norm_map SET field = target_id WHERE field = source;
    UPDATE search.relevance_adjustment SET field = target_id WHERE field = source;
    RETURN 1;
END;
$func$ LANGUAGE PLPGSQL;

-- To avoid sequential scans against the large metabib.*_field_entry tables
CREATE INDEX metabib_author_field_entry_field ON metabib.author_field_entry(field);
CREATE INDEX metabib_keyword_field_entry_field ON metabib.keyword_field_entry(field);
CREATE INDEX metabib_series_field_entry_field ON metabib.series_field_entry(field);
CREATE INDEX metabib_subject_field_entry_field ON metabib.subject_field_entry(field);
CREATE INDEX metabib_title_field_entry_field ON metabib.title_field_entry(field);

-- Now update those custom indexes
SELECT config.modify_metabib_field(id, NULL)
    FROM config.metabib_field
    WHERE id > 15 AND id < 100 AND field_class || name <> 'subjectcomplete';

-- Ensure "subject|complete" is id = 16, if it exists
SELECT config.modify_metabib_field(id, 16)
    FROM config.metabib_field
    WHERE id <> 16 AND field_class || name = 'subjectcomplete';

-- And bump the config.metabib_field sequence to a minimum of 100 to avoid problems in the future
SELECT setval('config.metabib_field_id_seq', GREATEST(100, (SELECT MAX(id) + 1 FROM config.metabib_field)));

-- And drop the temporary indexes that we just created
DROP INDEX metabib.metabib_author_field_entry_field;
DROP INDEX metabib.metabib_keyword_field_entry_field;
DROP INDEX metabib.metabib_series_field_entry_field;
DROP INDEX metabib.metabib_subject_field_entry_field;
DROP INDEX metabib.metabib_title_field_entry_field;

-- Now we can go ahead and insert the additional stock indexes

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath )
    SELECT  16, 'subject', 'complete', oils_i18n_gettext(16, 'All Subjects', 'cmf', 'label'), 'mods32', $$//mods32:mods/mods32:subject//text()$$
      WHERE NOT EXISTS (select id from config.metabib_field where field_class = 'subject' and name = 'complete'); -- in case it's already there

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (17, 'identifier', 'accession', oils_i18n_gettext(17, 'Accession Number', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="001"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (18, 'identifier', 'isbn', oils_i18n_gettext(18, 'ISBN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="020"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (19, 'identifier', 'issn', oils_i18n_gettext(19, 'ISSN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="022"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (20, 'identifier', 'upc', oils_i18n_gettext(20, 'UPC', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="1"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (21, 'identifier', 'ismn', oils_i18n_gettext(21, 'ISMN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="2"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (22, 'identifier', 'ean', oils_i18n_gettext(22, 'EAN', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="3"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (23, 'identifier', 'isrc', oils_i18n_gettext(23, 'ISRC', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="0"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (24, 'identifier', 'sici', oils_i18n_gettext(24, 'SICI', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="024" and ind1="4"]/marcxml:subfield[code="a" or code="z"]/text()$$, TRUE );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field ) VALUES
    (25, 'identifier', 'bibcn', oils_i18n_gettext(25, 'Local Free-Text Call Number', 'cmf', 'label'), 'marcxml', $$//marcxml:datafield[tag="099"]//text()$$, TRUE );

SELECT SETVAL('config.metabib_field_id_seq'::TEXT, (SELECT MAX(id) FROM config.metabib_field), TRUE);
 

DELETE FROM config.metabib_search_alias WHERE alias = 'dc.identifier';

INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('bib.subjectoccupation','subject',16);
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('id','identifier');
INSERT INTO config.metabib_search_alias (alias,field_class) VALUES ('dc.identifier','identifier');
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.isbn','identifier', 18);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.issn','identifier', 19);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.upc','identifier', 20);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.callnumber','identifier', 25);

CREATE TABLE metabib.identifier_field_entry (
	id		BIGSERIAL	PRIMARY KEY,
	source		BIGINT		NOT NULL,
	field		INT		NOT NULL,
	value		TEXT		NOT NULL,
	index_vector	tsvector	NOT NULL
);
CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
	BEFORE UPDATE OR INSERT ON metabib.identifier_field_entry
	FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('keyword');

CREATE INDEX metabib_identifier_field_entry_index_vector_idx ON metabib.identifier_field_entry USING GIST (index_vector);
CREATE INDEX metabib_identifier_field_entry_value_idx ON metabib.identifier_field_entry
    (SUBSTRING(value,1,1024)) WHERE index_vector = ''::TSVECTOR;
CREATE INDEX metabib_identifier_field_entry_source_idx ON metabib.identifier_field_entry (source);

ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_source_pkey
    FOREIGN KEY (source) REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.identifier_field_entry ADD CONSTRAINT metabib_identifier_field_entry_field_pkey
    FOREIGN KEY (field) REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION public.translate_isbn1013( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # For each ISBN found in a single string containing a set of ISBNs:
    #   * Normalize an incoming ISBN to have the correct checksum and no hyphens
    #   * Convert an incoming ISBN10 or ISBN13 to its counterpart and return

    my $input = shift;
    my $output = '';

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $output .= $isbn->isbn() . " ";
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, convert it to its counterpart ISBN10/ISBN13
        # and add the normalized original ISBN to the output
        if ($isbn && $isbn->is_valid()) {
            my $isbn_xlated = ($isbn->type eq "ISBN13") ? $isbn->as_isbn10 : $isbn->as_isbn13;
            $output .= $isbn->isbn . " ";

            # If we successfully converted the ISBN to its counterpart, add the
            # converted ISBN to the output as well
            $output .= ($isbn_xlated->isbn . " ") if ($isbn_xlated);
        }
    }
    return $output if $output;

    # If there were no valid ISBNs, just return the raw input
    return $input;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.translate_isbn1013(TEXT) IS $$
/*
 * Copyright (C) 2010 Merrimack Valley Library Consortium
 * Jason Stephenson <jstephenson@mvlc.org>
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 *
 * The translate_isbn1013 function takes an input ISBN and returns the
 * following in a single space-delimited string if the input ISBN is valid:
 *   - The normalized input ISBN (hyphens stripped)
 *   - The normalized input ISBN with a fixed checksum if the checksum was bad
 *   - The ISBN converted to its ISBN10 or ISBN13 counterpart, if possible
 */
$$;

UPDATE config.metabib_field SET facet_field = FALSE WHERE id BETWEEN 17 AND 25;
UPDATE config.metabib_field SET xpath = REPLACE(xpath,'marcxml','marc') WHERE id BETWEEN 17 AND 25;
UPDATE config.metabib_field SET xpath = REPLACE(xpath,'tag','@tag') WHERE id BETWEEN 17 AND 25;
UPDATE config.metabib_field SET xpath = REPLACE(xpath,'code','@code') WHERE id BETWEEN 17 AND 25;
UPDATE config.metabib_field SET xpath = REPLACE(xpath,'"',E'\'') WHERE id BETWEEN 17 AND 25;
UPDATE config.metabib_field SET xpath = REPLACE(xpath,'/text()','') WHERE id BETWEEN 17 AND 24;

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'ISBN 10/13 conversion',
	'Translate ISBN10 to ISBN13, and vice versa, for indexing purposes.',
	'translate_isbn1013',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Replace',
	'Replace all occurences of first parameter in the string with the second parameter.',
	'replace',
	2
);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id, i.id, 1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('first_word')
            AND m.id IN (18);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id, i.id, 2
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('translate_isbn1013')
            AND m.id IN (18);

INSERT INTO config.metabib_field_index_norm_map (field,norm,params)
    SELECT  m.id, i.id, $$['-','']$$
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('replace')
            AND m.id IN (19);

INSERT INTO config.metabib_field_index_norm_map (field,norm,params)
    SELECT  m.id, i.id, $$[' ','']$$
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('replace')
            AND m.id IN (19);

DELETE FROM config.metabib_field_index_norm_map WHERE norm IN (1,2) and field > 16;

UPDATE  config.metabib_field_index_norm_map
  SET   params = REPLACE(params,E'\'','"')
  WHERE params IS NOT NULL AND params <> '';

DROP TRIGGER IF EXISTS metabib_identifier_field_entry_fti_trigger ON metabib.identifier_field_entry;

CREATE TEXT SEARCH CONFIGURATION identifier ( COPY = title );

ALTER TABLE config.circ_modifier
	ADD COLUMN avg_wait_time INTERVAL;

--CREATE TABLE actor.usr_password_reset (
--  id SERIAL PRIMARY KEY,
--  uuid TEXT NOT NULL, 
--  usr BIGINT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED, 
--  request_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(), 
--  has_been_reset BOOL NOT NULL DEFAULT false
--);
--COMMENT ON TABLE actor.usr_password_reset IS $$
--/*
-- * Copyright (C) 2010 Laurentian University
-- * Dan Scott <dscott@laurentian.ca>
-- *
-- * Self-serve password reset requests
-- *
-- * ****
-- *
-- * This program is free software; you can redistribute it and/or
-- * modify it under the terms of the GNU General Public License
-- * as published by the Free Software Foundation; either version 2
-- * of the License, or (at your option) any later version.
-- *
-- * This program is distributed in the hope that it will be useful,
-- * but WITHOUT ANY WARRANTY; without even the implied warranty of
-- * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- * GNU General Public License for more details.
-- */
--$$;
--CREATE UNIQUE INDEX actor_usr_password_reset_uuid_idx ON actor.usr_password_reset (uuid);
--CREATE INDEX actor_usr_password_reset_usr_idx ON actor.usr_password_reset (usr);
--CREATE INDEX actor_usr_password_reset_request_time_idx ON actor.usr_password_reset (request_time);
--CREATE INDEX actor_usr_password_reset_has_been_reset_idx ON actor.usr_password_reset (has_been_reset);

-- Use the identifier search class tsconfig
DROP TRIGGER IF EXISTS metabib_identifier_field_entry_fti_trigger ON metabib.identifier_field_entry;
CREATE TRIGGER metabib_identifier_field_entry_fti_trigger
    BEFORE INSERT OR UPDATE ON metabib.identifier_field_entry
    FOR EACH ROW
    EXECUTE PROCEDURE public.oils_tsearch2('identifier');

INSERT INTO config.global_flag (name,label,enabled)
    VALUES ('history.circ.retention_age',oils_i18n_gettext('history.circ.retention_age', 'Historical Circulation Retention Age', 'cgf', 'label'), TRUE);
INSERT INTO config.global_flag (name,label,enabled)
    VALUES ('history.circ.retention_count',oils_i18n_gettext('history.circ.retention_count', 'Historical Circulations per Copy', 'cgf', 'label'), TRUE);

-- turn a JSON scalar into an SQL TEXT value
CREATE OR REPLACE FUNCTION oils_json_to_text( TEXT ) RETURNS TEXT AS $f$
    use JSON::XS;                    
    my $json = shift();
    my $txt;
    eval { $txt = JSON::XS->new->allow_nonref->decode( $json ) };   
    return undef if ($@);
    return $txt
$f$ LANGUAGE PLPERLU;

-- Return the list of circ chain heads in xact_start order that the user has chosen to "retain"
CREATE OR REPLACE FUNCTION action.usr_visible_circs (usr_id INT) RETURNS SETOF action.circulation AS $func$
DECLARE
    c               action.circulation%ROWTYPE;
    view_age        INTERVAL;
    usr_view_age    actor.usr_setting%ROWTYPE;
    usr_view_start  actor.usr_setting%ROWTYPE;
BEGIN
    SELECT * INTO usr_view_age FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.circ.retention_age';
    SELECT * INTO usr_view_start FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.circ.retention_start';

    IF usr_view_age.value IS NOT NULL AND usr_view_start.value IS NOT NULL THEN
        -- User opted in and supplied a retention age
        IF oils_json_to_text(usr_view_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ) THEN
            view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
        ELSE
            view_age := oils_json_to_text(usr_view_age.value)::INTERVAL;
        END IF;
    ELSIF usr_view_start.value IS NOT NULL THEN
        -- User opted in
        view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
    ELSE
        -- User did not opt in
        RETURN;
    END IF;

    FOR c IN
        SELECT  *
          FROM  action.circulation
          WHERE usr = usr_id
                AND parent_circ IS NULL
                AND xact_start > NOW() - view_age
          ORDER BY xact_start
    LOOP
        RETURN NEXT c;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    usr_keep_age    actor.usr_setting%ROWTYPE;
    usr_keep_start  actor.usr_setting%ROWTYPE;
    org_keep_age    INTERVAL;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    purge_position  INT;
    count_purged    INT;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

    -- First, find copies with more than keep_count non-renewal circs
    FOR target_acp IN
        SELECT  target_copy,
                COUNT(*) AS total_real_circs
          FROM  action.circulation
          WHERE parent_circ IS NULL
                AND xact_finish IS NOT NULL
          GROUP BY target_copy
          HAVING COUNT(*) > org_keep_count
    LOOP
        purge_position := 0;
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            SELECT  *
              FROM  action.circulation
              WHERE target_copy = target_acp.target_copy
                    AND parent_circ IS NULL
              ORDER BY xact_start
        LOOP

            -- Stop once we've purged enough circs to hit org_keep_count
            EXIT WHEN target_acp.total_real_circs - purge_position <= org_keep_count;

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            EXIT WHEN circ_chain_tail.xact_finish IS NULL;

            -- Now get the user settings, if any, to block purging if the user wants to keep more circs
            usr_keep_age.value := NULL;
            SELECT * INTO usr_keep_age FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_age';

            usr_keep_start.value := NULL;
            SELECT * INTO usr_keep_start FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_start';

            IF usr_keep_age.value IS NOT NULL AND usr_keep_start.value IS NOT NULL THEN
                IF oils_json_to_text(usr_keep_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ) THEN
                    keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
                ELSE
                    keep_age := oils_json_to_text(usr_keep_age.value)::INTERVAL;
                END IF;
            ELSIF usr_keep_start.value IS NOT NULL THEN
                keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
            ELSE
                keep_age := COALESCE( org_keep_age::INTERVAL, '2000 years'::INTERVAL );
            END IF;

            EXIT WHEN AGE(NOW(), circ_chain_tail.xact_finish) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            WHILE circ_chain_tail.parent_circ IS NOT NULL LOOP
                SELECT * INTO circ_chain_tail FROM action.circulation WHERE id = circ_chain_tail.parent_circ;
                DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            END LOOP;

            count_purged := count_purged + 1;
            purge_position := purge_position + 1;

        END LOOP;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.usr_visible_holds (usr_id INT) RETURNS SETOF action.hold_request AS $func$
DECLARE
    h               action.hold_request%ROWTYPE;
    view_age        INTERVAL;
    view_count      INT;
    usr_view_count  actor.usr_setting%ROWTYPE;
    usr_view_age    actor.usr_setting%ROWTYPE;
    usr_view_start  actor.usr_setting%ROWTYPE;
BEGIN
    SELECT * INTO usr_view_count FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_count';
    SELECT * INTO usr_view_age FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_age';
    SELECT * INTO usr_view_start FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_start';

    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND fulfillment_time IS NULL
                AND cancel_time IS NULL
          ORDER BY request_time DESC
    LOOP
        RETURN NEXT h;
    END LOOP;

    IF usr_view_start.value IS NULL THEN
        RETURN;
    END IF;

    IF usr_view_age.value IS NOT NULL THEN
        -- User opted in and supplied a retention age
        IF oils_json_to_string(usr_view_age.value)::INTERVAL > AGE(NOW(), oils_json_to_string(usr_view_start.value)::TIMESTAMPTZ) THEN
            view_age := AGE(NOW(), oils_json_to_string(usr_view_start.value)::TIMESTAMPTZ);
        ELSE
            view_age := oils_json_to_string(usr_view_age.value)::INTERVAL;
        END IF;
    ELSE
        -- User opted in
        view_age := AGE(NOW(), oils_json_to_string(usr_view_start.value)::TIMESTAMPTZ);
    END IF;

    IF usr_view_count.value IS NOT NULL THEN
        view_count := oils_json_to_text(usr_view_count.value)::INT;
    ELSE
        view_count := 1000;
    END IF;

    -- show some fulfilled/canceled holds
    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND ( fulfillment_time IS NOT NULL OR cancel_time IS NOT NULL )
                AND request_time > NOW() - view_age
          ORDER BY request_time DESC
          LIMIT view_count
    LOOP
        RETURN NEXT h;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

DROP TABLE IF EXISTS serial.bib_summary CASCADE;

DROP TABLE IF EXISTS serial.index_summary CASCADE;

DROP TABLE IF EXISTS serial.sup_summary CASCADE;

DROP TABLE IF EXISTS serial.issuance CASCADE;

DROP TABLE IF EXISTS serial.binding_unit CASCADE;

DROP TABLE IF EXISTS serial.subscription CASCADE;

CREATE TABLE asset.copy_template (
	id             SERIAL   PRIMARY KEY,
	owning_lib     INT      NOT NULL
	                        REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	creator        BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	editor         BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	create_date    TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	edit_date      TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	name           TEXT     NOT NULL,
	-- columns above this point are attributes of the template itself
	-- columns after this point are attributes of the copy this template modifies/creates
	circ_lib       INT      REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	status         INT      REFERENCES config.copy_status (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	location       INT      REFERENCES asset.copy_location (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	loan_duration  INT      CONSTRAINT valid_loan_duration CHECK (
	                            loan_duration IS NULL OR loan_duration IN (1,2,3)),
	fine_level     INT      CONSTRAINT valid_fine_level CHECK (
	                            fine_level IS NULL OR loan_duration IN (1,2,3)),
	age_protect    INT,
	circulate      BOOL,
	deposit        BOOL,
	ref            BOOL,
	holdable       BOOL,
	deposit_amount NUMERIC(6,2),
	price          NUMERIC(8,2),
	circ_modifier  TEXT,
	circ_as_type   TEXT,
	alert_message  TEXT,
	opac_visible   BOOL,
	floating       BOOL,
	mint_condition BOOL
);

CREATE TABLE serial.subscription (
	id                     SERIAL       PRIMARY KEY,
	owning_lib             INT          NOT NULL DEFAULT 1
	                                    REFERENCES actor.org_unit (id)
	                                    ON DELETE SET NULL
	                                    DEFERRABLE INITIALLY DEFERRED,
	start_date             TIMESTAMP WITH TIME ZONE     NOT NULL,
	end_date               TIMESTAMP WITH TIME ZONE,    -- interpret NULL as current subscription
	record_entry           BIGINT       REFERENCES biblio.record_entry (id)
	                                    ON DELETE SET NULL
	                                    DEFERRABLE INITIALLY DEFERRED,
	expected_date_offset   INTERVAL
	-- acquisitions/business-side tables link to here
);
CREATE INDEX serial_subscription_record_idx ON serial.subscription (record_entry);
CREATE INDEX serial_subscription_owner_idx ON serial.subscription (owning_lib);

--at least one distribution per org_unit holding issues
CREATE TABLE serial.distribution (
	id                    SERIAL  PRIMARY KEY,
	record_entry          BIGINT  REFERENCES serial.record_entry (id)
	                              ON DELETE SET NULL
	                              DEFERRABLE INITIALLY DEFERRED,
	summary_method        TEXT    CONSTRAINT sdist_summary_method_check CHECK (
	                                  summary_method IS NULL
	                                  OR summary_method IN ( 'add_to_sre',
	                                  'merge_with_sre', 'use_sre_only',
	                                  'use_sdist_only')),
	subscription          INT     NOT NULL
	                              REFERENCES serial.subscription (id)
								  ON DELETE CASCADE
								  DEFERRABLE INITIALLY DEFERRED,
	holding_lib           INT     NOT NULL
	                              REFERENCES actor.org_unit (id)
								  DEFERRABLE INITIALLY DEFERRED,
	label                 TEXT    NOT NULL,
	receive_call_number   BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	receive_unit_template INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_call_number      BIGINT  REFERENCES asset.call_number (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	bind_unit_template    INT     REFERENCES asset.copy_template (id)
	                              DEFERRABLE INITIALLY DEFERRED,
	unit_label_prefix     TEXT,
	unit_label_suffix     TEXT
);
CREATE INDEX serial_distribution_sub_idx ON serial.distribution (subscription);
CREATE INDEX serial_distribution_holding_lib_idx ON serial.distribution (holding_lib);

CREATE UNIQUE INDEX one_dist_per_sre_idx ON serial.distribution (record_entry);

CREATE TABLE serial.stream (
	id              SERIAL  PRIMARY KEY,
	distribution    INT     NOT NULL
	                        REFERENCES serial.distribution (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	routing_label   TEXT
);
CREATE INDEX serial_stream_dist_idx ON serial.stream (distribution);

CREATE UNIQUE INDEX label_once_per_dist
	ON serial.stream (distribution, routing_label)
	WHERE routing_label IS NOT NULL;

CREATE TABLE serial.routing_list_user (
	id             SERIAL       PRIMARY KEY,
	stream         INT          NOT NULL
	                            REFERENCES serial.stream
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	pos            INT          NOT NULL DEFAULT 1,
	reader         INT          REFERENCES actor.usr
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	department     TEXT,
	note           TEXT,
	CONSTRAINT one_pos_per_routing_list UNIQUE ( stream, pos ),
	CONSTRAINT reader_or_dept CHECK
	(
	    -- Recipient is a person or a department, but not both
		(reader IS NOT NULL AND department IS NULL) OR
		(reader IS NULL AND department IS NOT NULL)
	)
);
CREATE INDEX serial_routing_list_user_stream_idx ON serial.routing_list_user (stream);
CREATE INDEX serial_routing_list_user_reader_idx ON serial.routing_list_user (reader);

CREATE TABLE serial.caption_and_pattern (
	id           SERIAL       PRIMARY KEY,
	subscription INT          NOT NULL REFERENCES serial.subscription (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	type         TEXT         NOT NULL
	                          CONSTRAINT cap_type CHECK ( type in
	                          ( 'basic', 'supplement', 'index' )),
	create_date  TIMESTAMPTZ  NOT NULL DEFAULT now(),
	start_date   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
	end_date     TIMESTAMP WITH TIME ZONE,
	active       BOOL         NOT NULL DEFAULT FALSE,
	pattern_code TEXT         NOT NULL,       -- must contain JSON
	enum_1       TEXT,
	enum_2       TEXT,
	enum_3       TEXT,
	enum_4       TEXT,
	enum_5       TEXT,
	enum_6       TEXT,
	chron_1      TEXT,
	chron_2      TEXT,
	chron_3      TEXT,
	chron_4      TEXT,
	chron_5      TEXT
);
CREATE INDEX serial_caption_and_pattern_sub_idx ON serial.caption_and_pattern (subscription);

CREATE TABLE serial.issuance (
	id              SERIAL    PRIMARY KEY,
	creator         INT       NOT NULL
	                          REFERENCES actor.usr (id)
							  DEFERRABLE INITIALLY DEFERRED,
	editor          INT       NOT NULL
	                          REFERENCES actor.usr (id)
	                          DEFERRABLE INITIALLY DEFERRED,
	create_date     TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	edit_date       TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	subscription    INT       NOT NULL
	                          REFERENCES serial.subscription (id)
	                          ON DELETE CASCADE
	                          DEFERRABLE INITIALLY DEFERRED,
	label           TEXT,
	date_published  TIMESTAMP WITH TIME ZONE,
	caption_and_pattern  INT  REFERENCES serial.caption_and_pattern (id)
                              DEFERRABLE INITIALLY DEFERRED,
	holding_code    TEXT,
	holding_type    TEXT      CONSTRAINT valid_holding_type CHECK
	                          (
	                              holding_type IS NULL
	                              OR holding_type IN ('basic','supplement','index')
	                          ),
	holding_link_id INT
	-- TODO: add columns for separate enumeration/chronology values
);
CREATE INDEX serial_issuance_sub_idx ON serial.issuance (subscription);
CREATE INDEX serial_issuance_caption_and_pattern_idx ON serial.issuance (caption_and_pattern);
CREATE INDEX serial_issuance_date_published_idx ON serial.issuance (date_published);

CREATE TABLE serial.unit (
	label           TEXT,
	label_sort_key  TEXT,
	contents        TEXT    NOT NULL
) INHERITS (asset.copy);
CREATE UNIQUE INDEX unit_barcode_key ON serial.unit (barcode) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE INDEX unit_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_avail_cn_idx ON serial.unit (call_number);
CREATE INDEX unit_creator_idx  ON serial.unit ( creator );
CREATE INDEX unit_editor_idx   ON serial.unit ( editor );

ALTER TABLE serial.unit ADD PRIMARY KEY (id);

ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_call_number_fkey FOREIGN KEY (call_number) REFERENCES asset.call_number (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_creator_fkey FOREIGN KEY (creator) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE serial.unit ADD CONSTRAINT serial_unit_editor_fkey FOREIGN KEY (editor) REFERENCES actor.usr (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE serial.item (
	id              SERIAL  PRIMARY KEY,
	creator         INT     NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	editor          INT     NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	create_date     TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	edit_date       TIMESTAMP WITH TIME ZONE        NOT NULL DEFAULT now(),
	issuance        INT     NOT NULL
	                        REFERENCES serial.issuance (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	stream          INT     NOT NULL
	                        REFERENCES serial.stream (id)
	                        ON DELETE CASCADE
	                        DEFERRABLE INITIALLY DEFERRED,
	unit            INT     REFERENCES serial.unit (id)
	                        ON DELETE SET NULL
	                        DEFERRABLE INITIALLY DEFERRED,
	uri             INT     REFERENCES asset.uri (id)
	                        ON DELETE SET NULL
	                        DEFERRABLE INITIALLY DEFERRED,
	date_expected   TIMESTAMP WITH TIME ZONE,
	date_received   TIMESTAMP WITH TIME ZONE,
	status          TEXT    CONSTRAINT valid_status CHECK (
                               status IN ( 'Bindery', 'Bound', 'Claimed', 'Discarded',
                               'Expected', 'Not Held', 'Not Published', 'Received'))
                            DEFAULT 'Expected',
	shadowed        BOOL    NOT NULL DEFAULT FALSE
);
CREATE INDEX serial_item_stream_idx ON serial.item (stream);
CREATE INDEX serial_item_issuance_idx ON serial.item (issuance);
CREATE INDEX serial_item_unit_idx ON serial.item (unit);
CREATE INDEX serial_item_uri_idx ON serial.item (uri);
CREATE INDEX serial_item_date_received_idx ON serial.item (date_received);
CREATE INDEX serial_item_status_idx ON serial.item (status);

CREATE TABLE serial.item_note (
	id          SERIAL  PRIMARY KEY,
	item        INT     NOT NULL
	                    REFERENCES serial.item (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator     INT     NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	pub         BOOL    NOT NULL    DEFAULT FALSE,
	title       TEXT    NOT NULL,
	value       TEXT    NOT NULL
);
CREATE INDEX serial_item_note_item_idx ON serial.item_note (item);

CREATE TABLE serial.basic_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_basic_summary_dist_idx ON serial.basic_summary (distribution);

CREATE TABLE serial.supplement_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_supplement_summary_dist_idx ON serial.supplement_summary (distribution);

CREATE TABLE serial.index_summary (
	id                  SERIAL  PRIMARY KEY,
	distribution        INT     NOT NULL
	                            REFERENCES serial.distribution (id)
	                            ON DELETE CASCADE
	                            DEFERRABLE INITIALLY DEFERRED,
	generated_coverage  TEXT    NOT NULL,
	textual_holdings    TEXT,
	show_generated      BOOL    NOT NULL DEFAULT TRUE
);
CREATE INDEX serial_index_summary_dist_idx ON serial.index_summary (distribution);

-- DELETE FROM action_trigger.environment WHERE event_def IN (29,30); DELETE FROM action_trigger.event where event_def IN (29,30); DELETE FROM action_trigger.event_definition WHERE id IN (29,30); DELETE FROM action_trigger.hook WHERE key IN ('money.format.payment_receipt.email','money.format.payment_receipt.print'); DELETE FROM config.upgrade_log WHERE version = '0289'; -- from testing, this sql will remove these events, etc.

DROP INDEX IF EXISTS authority.authority_record_unique_tcn;
CREATE UNIQUE INDEX authority_record_unique_tcn ON authority.record_entry (arn_source,arn_value) WHERE deleted = FALSE OR deleted IS FALSE;

DROP INDEX IF EXISTS asset.asset_call_number_label_once_per_lib;
CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label) WHERE deleted = FALSE OR deleted IS FALSE;

DROP INDEX IF EXISTS biblio.biblio_record_unique_tcn;
CREATE UNIQUE INDEX biblio_record_unique_tcn ON biblio.record_entry (tcn_value) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_val INTERVAL )
RETURNS INTEGER AS $$
BEGIN
	RETURN EXTRACT( EPOCH FROM interval_val );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION config.interval_to_seconds( interval_string TEXT )
RETURNS INTEGER AS $$
BEGIN
	RETURN config.interval_to_seconds( interval_string::INTERVAL );
END;
$$ LANGUAGE plpgsql;

INSERT INTO container.biblio_record_entry_bucket_type( code, label ) VALUES (
    'temp',
    oils_i18n_gettext(
        'temp',
        'Temporary bucket which gets deleted after use.',
        'cbrebt',
        'label'
    )
);

-- DELETE FROM action_trigger.environment WHERE event_def IN (31,32); DELETE FROM action_trigger.event where event_def IN (31,32); DELETE FROM action_trigger.event_definition WHERE id IN (31,32); DELETE FROM action_trigger.hook WHERE key IN ('biblio.format.record_entry.email','biblio.format.record_entry.print'); DELETE FROM action_trigger.cleanup WHERE module = 'DeleteTempBiblioBucket'; DELETE FROM container.biblio_record_entry_bucket_item WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'temp'); DELETE FROM container.biblio_record_entry_bucket WHERE btype = 'temp'; DELETE FROM container.biblio_record_entry_bucket_type WHERE code = 'temp'; DELETE FROM config.upgrade_log WHERE version = '0294'; -- from testing, this sql will remove these events, etc.

CREATE OR REPLACE FUNCTION biblio.check_marcxml_well_formed () RETURNS TRIGGER AS $func$
BEGIN

    IF xml_is_well_formed(NEW.marc) THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Attempted to % MARCXML that is not well formed', TG_OP;
    END IF;
    
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();

CREATE TRIGGER a_marcxml_is_well_formed BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE biblio.check_marcxml_well_formed();

ALTER TABLE serial.record_entry
	ALTER COLUMN marc DROP NOT NULL;

insert INTO CONFIG.xml_transform(name, namespace_uri, prefix, xslt)
VALUES ('marc21expand880', 'http://www.loc.gov/MARC21/slim', 'marc', $$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    xmlns:marc="http://www.loc.gov/MARC21/slim"
    version="1.0">
<!--
Copyright (C) 2010  Equinox Software, Inc.
Galen Charlton <gmc@esilibrary.cOM.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

marc21_expand_880.xsl - stylesheet used during indexing to
                        map alternative graphical representations
                        of MARC fields stored in 880 fields
                        to the corresponding tag name and value.

For example, if a MARC record for a Chinese book has

245.00 $6 880-01 $a Ba shi san nian duan pian xiao shuo xuan
880.00 $6 245-01/$1 $a八十三年短篇小說選

this stylesheet will transform it to the equivalent of

245.00 $6 880-01 $a Ba shi san nian duan pian xiao shuo xuan
245.00 $6 245-01/$1 $a八十三年短篇小說選

-->
    <xsl:output encoding="UTF-8" indent="yes" method="xml"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="//marc:datafield[@tag='880']">
        <xsl:if test="./marc:subfield[@code='6'] and string-length(./marc:subfield[@code='6']) &gt;= 6">
            <marc:datafield>
                <xsl:attribute name="tag">
                    <xsl:value-of select="substring(./marc:subfield[@code='6'], 1, 3)" />
                </xsl:attribute>
                <xsl:attribute name="ind1">
                    <xsl:value-of select="@ind1" />
                </xsl:attribute>
                <xsl:attribute name="ind2">
                    <xsl:value-of select="@ind2" />
                </xsl:attribute>
                <xsl:apply-templates />
            </marc:datafield>
        </xsl:if>
    </xsl:template>
    
</xsl:stylesheet>$$);

-- fix broken prefix and namespace URI for the
-- mods32 transform found in some databases
-- that started out at version 1.2 or earlier
UPDATE config.xml_transform
SET namespace_uri = 'http://www.loc.gov/mods/v3'
WHERE name = 'mods32'
AND namespace_uri = 'http://www.loc.gov/mods/'
AND xslt LIKE '%xmlns="http://www.loc.gov/mods/v3"%';

UPDATE config.xml_transform
SET prefix = 'mods32'
WHERE name = 'mods32'
AND prefix = 'mods'
AND EXISTS (SELECT xpath FROM config.metabib_field WHERE xpath ~ 'mods32:');

-- Splitting the ingest trigger up into little bits

CREATE TEMPORARY TABLE eg_0301_check_if_has_contents (
    flag INTEGER PRIMARY KEY
) ON COMMIT DROP;
INSERT INTO eg_0301_check_if_has_contents VALUES (1);

-- cause failure if either of the tables we want to drop have rows
INSERT INTO eg_0301_check_if_has_contents SELECT 1 FROM asset.copy_transparency LIMIT 1;
INSERT INTO eg_0301_check_if_has_contents SELECT 1 FROM asset.copy_transparency_map LIMIT 1;

DROP TABLE IF EXISTS asset.copy_transparency_map;
DROP TABLE IF EXISTS asset.copy_transparency;

UPDATE config.metabib_field SET facet_xpath = '//' || facet_xpath WHERE facet_xpath IS NOT NULL;

-- We won't necessarily use all of these, but they are here for completeness.
-- Source is the EDI spec 1229 codelist, eg: http://www.stylusstudio.com/edifact/D04B/1229.htm
-- Values are the EDI code value + 1000

INSERT INTO acq.cancel_reason (keep_debits, id, org_unit, label, description) VALUES 
('t',(  1+1000), 1, 'Added',     'The information is to be or has been added.'),
('f',(  2+1000), 1, 'Deleted',   'The information is to be or has been deleted.'),
('t',(  3+1000), 1, 'Changed',   'The information is to be or has been changed.'),
('t',(  4+1000), 1, 'No action',                  'This line item is not affected by the actual message.'),
('t',(  5+1000), 1, 'Accepted without amendment', 'This line item is entirely accepted by the seller.'),
('t',(  6+1000), 1, 'Accepted with amendment',    'This line item is accepted but amended by the seller.'),
('f',(  7+1000), 1, 'Not accepted',               'This line item is not accepted by the seller.'),
('t',(  8+1000), 1, 'Schedule only', 'Code specifying that the message is a schedule only.'),
('t',(  9+1000), 1, 'Amendments',    'Code specifying that amendments are requested/notified.'),
('f',( 10+1000), 1, 'Not found',   'This line item is not found in the referenced message.'),
('t',( 11+1000), 1, 'Not amended', 'This line is not amended by the buyer.'),
('t',( 12+1000), 1, 'Line item numbers changed', 'Code specifying that the line item numbers have changed.'),
('t',( 13+1000), 1, 'Buyer has deducted amount', 'Buyer has deducted amount from payment.'),
('t',( 14+1000), 1, 'Buyer claims against invoice', 'Buyer has a claim against an outstanding invoice.'),
('t',( 15+1000), 1, 'Charge back by seller', 'Factor has been requested to charge back the outstanding item.'),
('t',( 16+1000), 1, 'Seller will issue credit note', 'Seller agrees to issue a credit note.'),
('t',( 17+1000), 1, 'Terms changed for new terms', 'New settlement terms have been agreed.'),
('t',( 18+1000), 1, 'Abide outcome of negotiations', 'Factor agrees to abide by the outcome of negotiations between seller and buyer.'),
('t',( 19+1000), 1, 'Seller rejects dispute', 'Seller does not accept validity of dispute.'),
('t',( 20+1000), 1, 'Settlement', 'The reported situation is settled.'),
('t',( 21+1000), 1, 'No delivery', 'Code indicating that no delivery will be required.'),
('t',( 22+1000), 1, 'Call-off delivery', 'A request for delivery of a particular quantity of goods to be delivered on a particular date (or within a particular period).'),
('t',( 23+1000), 1, 'Proposed amendment', 'A code used to indicate an amendment suggested by the sender.'),
('t',( 24+1000), 1, 'Accepted with amendment, no confirmation required', 'Accepted with changes which require no confirmation.'),
('t',( 25+1000), 1, 'Equipment provisionally repaired', 'The equipment or component has been provisionally repaired.'),
('t',( 26+1000), 1, 'Included', 'Code indicating that the entity is included.'),
('t',( 27+1000), 1, 'Verified documents for coverage', 'Upon receipt and verification of documents we shall cover you when due as per your instructions.'),
('t',( 28+1000), 1, 'Verified documents for debit',    'Upon receipt and verification of documents we shall authorize you to debit our account with you when due.'),
('t',( 29+1000), 1, 'Authenticated advice for coverage',      'On receipt of your authenticated advice we shall cover you when due as per your instructions.'),
('t',( 30+1000), 1, 'Authenticated advice for authorization', 'On receipt of your authenticated advice we shall authorize you to debit our account with you when due.'),
('t',( 31+1000), 1, 'Authenticated advice for credit',        'On receipt of your authenticated advice we shall credit your account with us when due.'),
('t',( 32+1000), 1, 'Credit advice requested for direct debit',           'A credit advice is requested for the direct debit.'),
('t',( 33+1000), 1, 'Credit advice and acknowledgement for direct debit', 'A credit advice and acknowledgement are requested for the direct debit.'),
('t',( 34+1000), 1, 'Inquiry',     'Request for information.'),
('t',( 35+1000), 1, 'Checked',     'Checked.'),
('t',( 36+1000), 1, 'Not checked', 'Not checked.'),
('f',( 37+1000), 1, 'Cancelled',   'Discontinued.'),
('t',( 38+1000), 1, 'Replaced',    'Provide a replacement.'),
('t',( 39+1000), 1, 'New',         'Not existing before.'),
('t',( 40+1000), 1, 'Agreed',      'Consent.'),
('t',( 41+1000), 1, 'Proposed',    'Put forward for consideration.'),
('t',( 42+1000), 1, 'Already delivered', 'Delivery has taken place.'),
('t',( 43+1000), 1, 'Additional subordinate structures will follow', 'Additional subordinate structures will follow the current hierarchy level.'),
('t',( 44+1000), 1, 'Additional subordinate structures will not follow', 'No additional subordinate structures will follow the current hierarchy level.'),
('t',( 45+1000), 1, 'Result opposed',         'A notification that the result is opposed.'),
('t',( 46+1000), 1, 'Auction held',           'A notification that an auction was held.'),
('t',( 47+1000), 1, 'Legal action pursued',   'A notification that legal action has been pursued.'),
('t',( 48+1000), 1, 'Meeting held',           'A notification that a meeting was held.'),
('t',( 49+1000), 1, 'Result set aside',       'A notification that the result has been set aside.'),
('t',( 50+1000), 1, 'Result disputed',        'A notification that the result has been disputed.'),
('t',( 51+1000), 1, 'Countersued',            'A notification that a countersuit has been filed.'),
('t',( 52+1000), 1, 'Pending',                'A notification that an action is awaiting settlement.'),
('f',( 53+1000), 1, 'Court action dismissed', 'A notification that a court action will no longer be heard.'),
('t',( 54+1000), 1, 'Referred item, accepted', 'The item being referred to has been accepted.'),
('f',( 55+1000), 1, 'Referred item, rejected', 'The item being referred to has been rejected.'),
('t',( 56+1000), 1, 'Debit advice statement line',  'Notification that the statement line is a debit advice.'),
('t',( 57+1000), 1, 'Credit advice statement line', 'Notification that the statement line is a credit advice.'),
('t',( 58+1000), 1, 'Grouped credit advices',       'Notification that the credit advices are grouped.'),
('t',( 59+1000), 1, 'Grouped debit advices',        'Notification that the debit advices are grouped.'),
('t',( 60+1000), 1, 'Registered', 'The name is registered.'),
('f',( 61+1000), 1, 'Payment denied', 'The payment has been denied.'),
('t',( 62+1000), 1, 'Approved as amended', 'Approved with modifications.'),
('t',( 63+1000), 1, 'Approved as submitted', 'The request has been approved as submitted.'),
('f',( 64+1000), 1, 'Cancelled, no activity', 'Cancelled due to the lack of activity.'),
('t',( 65+1000), 1, 'Under investigation', 'Investigation is being done.'),
('t',( 66+1000), 1, 'Initial claim received', 'Notification that the initial claim was received.'),
('f',( 67+1000), 1, 'Not in process', 'Not in process.'),
('f',( 68+1000), 1, 'Rejected, duplicate', 'Rejected because it is a duplicate.'),
('f',( 69+1000), 1, 'Rejected, resubmit with corrections', 'Rejected but may be resubmitted when corrected.'),
('t',( 70+1000), 1, 'Pending, incomplete', 'Pending because of incomplete information.'),
('t',( 71+1000), 1, 'Under field office investigation', 'Investigation by the field is being done.'),
('t',( 72+1000), 1, 'Pending, awaiting additional material', 'Pending awaiting receipt of additional material.'),
('t',( 73+1000), 1, 'Pending, awaiting review', 'Pending while awaiting review.'),
('t',( 74+1000), 1, 'Reopened', 'Opened again.'),
('t',( 75+1000), 1, 'Processed by primary, forwarded to additional payer(s)',   'This request has been processed by the primary payer and sent to additional payer(s).'),
('t',( 76+1000), 1, 'Processed by secondary, forwarded to additional payer(s)', 'This request has been processed by the secondary payer and sent to additional payer(s).'),
('t',( 77+1000), 1, 'Processed by tertiary, forwarded to additional payer(s)',  'This request has been processed by the tertiary payer and sent to additional payer(s).'),
('t',( 78+1000), 1, 'Previous payment decision reversed', 'A previous payment decision has been reversed.'),
('t',( 79+1000), 1, 'Not our claim, forwarded to another payer(s)', 'A request does not belong to this payer but has been forwarded to another payer(s).'),
('t',( 80+1000), 1, 'Transferred to correct insurance carrier', 'The request has been transferred to the correct insurance carrier for processing.'),
('t',( 81+1000), 1, 'Not paid, predetermination pricing only', 'Payment has not been made and the enclosed response is predetermination pricing only.'),
('t',( 82+1000), 1, 'Documentation claim', 'The claim is for documentation purposes only, no payment required.'),
('t',( 83+1000), 1, 'Reviewed', 'Assessed.'),
('f',( 84+1000), 1, 'Repriced', 'This price was changed.'),
('t',( 85+1000), 1, 'Audited', 'An official examination has occurred.'),
('t',( 86+1000), 1, 'Conditionally paid', 'Payment has been conditionally made.'),
('t',( 87+1000), 1, 'On appeal', 'Reconsideration of the decision has been applied for.'),
('t',( 88+1000), 1, 'Closed', 'Shut.'),
('t',( 89+1000), 1, 'Reaudited', 'A subsequent official examination has occurred.'),
('t',( 90+1000), 1, 'Reissued', 'Issued again.'),
('t',( 91+1000), 1, 'Closed after reopening', 'Reopened and then closed.'),
('t',( 92+1000), 1, 'Redetermined', 'Determined again or differently.'),
('t',( 93+1000), 1, 'Processed as primary',   'Processed as the first.'),
('t',( 94+1000), 1, 'Processed as secondary', 'Processed as the second.'),
('t',( 95+1000), 1, 'Processed as tertiary',  'Processed as the third.'),
('t',( 96+1000), 1, 'Correction of error', 'A correction to information previously communicated which contained an error.'),
('t',( 97+1000), 1, 'Single credit item of a group', 'Notification that the credit item is a single credit item of a group of credit items.'),
('t',( 98+1000), 1, 'Single debit item of a group',  'Notification that the debit item is a single debit item of a group of debit items.'),
('t',( 99+1000), 1, 'Interim response', 'The response is an interim one.'),
('t',(100+1000), 1, 'Final response',   'The response is an final one.'),
('t',(101+1000), 1, 'Debit advice requested', 'A debit advice is requested for the transaction.'),
('t',(102+1000), 1, 'Transaction not impacted', 'Advice that the transaction is not impacted.'),
('t',(103+1000), 1, 'Patient to be notified',                    'The action to take is to notify the patient.'),
('t',(104+1000), 1, 'Healthcare provider to be notified',        'The action to take is to notify the healthcare provider.'),
('t',(105+1000), 1, 'Usual general practitioner to be notified', 'The action to take is to notify the usual general practitioner.'),
('t',(106+1000), 1, 'Advice without details', 'An advice without details is requested or notified.'),
('t',(107+1000), 1, 'Advice with details', 'An advice with details is requested or notified.'),
('t',(108+1000), 1, 'Amendment requested', 'An amendment is requested.'),
('t',(109+1000), 1, 'For information', 'Included for information only.'),
('f',(110+1000), 1, 'Withdraw', 'A code indicating discontinuance or retraction.'),
('t',(111+1000), 1, 'Delivery date change', 'The action / notiification is a change of the delivery date.'),
('f',(112+1000), 1, 'Quantity change',      'The action / notification is a change of quantity.'),
('t',(113+1000), 1, 'Resale and claim', 'The identified items have been sold by the distributor to the end customer, and compensation for the loss of inventory value is claimed.'),
('t',(114+1000), 1, 'Resale',           'The identified items have been sold by the distributor to the end customer.'),
('t',(115+1000), 1, 'Prior addition', 'This existing line item becomes available at an earlier date.');

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath, facet_field, search_field ) VALUES
    (26, 'identifier', 'arcn', oils_i18n_gettext(26, 'Authority record control number', 'cmf', 'label'), 'marcxml', $$//marc:subfield[@code='0']$$, TRUE, FALSE );
 
SELECT SETVAL('config.metabib_field_id_seq'::TEXT, (SELECT MAX(id) FROM config.metabib_field), TRUE);
 
INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Remove Parenthesized Substring',
	'Remove any parenthesized substrings from the extracted text, such as the agency code preceding authority record control numbers in subfield 0.',
	'remove_paren_substring',
	0
);

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Trim Surrounding Space',
	'Trim leading and trailing spaces from extracted text.',
	'btrim',
	0
);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -2
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('remove_paren_substring')
            AND m.id IN (26);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func IN ('btrim')
            AND m.id IN (26);

-- Function that takes, and returns, marcxml and compiles an embedded ruleset for you, and they applys it
CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_marc TEXT, template_marc TEXT ) RETURNS TEXT AS $$
DECLARE
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    replace_rule    TEXT;
    tmp_marc        TEXT;
    trgt_marc        TEXT;
    tmpl_marc        TEXT;
    match_count     INT;
BEGIN

    IF target_marc IS NULL OR template_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for target or template record';
        RETURN NULL;
    END IF;

    dyn_profile := vandelay.compile_profile( template_marc );

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        trgt_marc = target_marc;
        tmpl_marc = template_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        tmp_marc = target_marc;
        trgt_marc = template_marc;
        tmpl_marc = tmp_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    RETURN vandelay.merge_record_xml( trgt_marc, tmpl_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule );

END;
$$ LANGUAGE PLPGSQL;

-- Function to generate an ephemeral overlay template from an authority record
CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT, BIGINT ) RETURNS TEXT AS $func$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return undef unless ($r);

    my $id = shift() || $r->subfield( '901' => 'c' );
    $id =~ s/^\s*(?:\([^)]+\))?\s*(.+)\s*?$/$1/;
    return undef unless ($id); # We need an ID!

    my $tmpl = MARC::Record->new();
    $tmpl->encoding( 'UTF-8' );

    my @rule_fields;
    for my $field ( $r->field( '1..' ) ) { # Get main entry fields from the authority record

        my $tag = $field->tag;
        my $i1 = $field->indicator(1);
        my $i2 = $field->indicator(2);
        my $sf = join '', map { $_->[0] } $field->subfields;
        my @data = map { @$_ } $field->subfields;

        my @replace_them;

        # Map the authority field to bib fields it can control.
        if ($tag >= 100 and $tag <= 111) {       # names
            @replace_them = map { $tag + $_ } (0, 300, 500, 600, 700);
        } elsif ($tag eq '130') {                # uniform title
            @replace_them = qw/130 240 440 730 830/;
        } elsif ($tag >= 150 and $tag <= 155) {  # subjects
            @replace_them = ($tag + 500);
        } elsif ($tag >= 180 and $tag <= 185) {  # floating subdivisions
            @replace_them = qw/100 400 600 700 800 110 410 610 710 810 111 411 611 711 811 130 240 440 730 830 650 651 655/;
        } else {
            next;
        }

        # Dummy up the bib-side data
        $tmpl->append_fields(
            map {
                MARC::Field->new( $_, $i1, $i2, @data )
            } @replace_them
        );

        # Construct some 'replace' rules
        push @rule_fields, map { $_ . $sf . '[0~\)' .$id . '$]' } @replace_them;
    }

    # Insert the replace rules into the template
    $tmpl->append_fields(
        MARC::Field->new( '905' => ' ' => ' ' => 'r' => join(',', @rule_fields ) )
    );

    $xml = $tmpl->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( BIGINT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( marc, id ) FROM authority.record_entry WHERE id = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.generate_overlay_template ( TEXT ) RETURNS TEXT AS $func$
    SELECT authority.generate_overlay_template( $1, NULL );
$func$ LANGUAGE SQL;

DELETE FROM config.metabib_field_index_norm_map WHERE field = 26;
DELETE FROM config.metabib_field WHERE id = 26;

-- Making this a global_flag (UI accessible) instead of an internal_flag
INSERT INTO config.global_flag (name, label) -- defaults to enabled=FALSE
    VALUES (
        'ingest.disable_authority_linking',
        oils_i18n_gettext(
            'ingest.disable_authority_linking',
            'Authority Automation: Disable bib-authority link tracking',
            'cgf', 
            'label'
        )
    );
UPDATE config.global_flag SET enabled = (SELECT enabled FROM ONLY config.internal_flag WHERE name = 'ingest.disable_authority_linking');
DELETE FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking';

INSERT INTO config.global_flag (name, label) -- defaults to enabled=FALSE
    VALUES (
        'ingest.disable_authority_auto_update',
        oils_i18n_gettext(
            'ingest.disable_authority_auto_update',
            'Authority Automation: Disable automatic authority updating (requires link tracking)',
            'cgf', 
            'label'
        )
    );

-- Enable automated ingest of authority records; just insert the row into
-- authority.record_entry and authority.full_rec will automatically be populated

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( marc, authority.generate_overlay_template( $1 ) )
      WHERE id = $2;
    SELECT $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT) RETURNS SETOF BIGINT AS $func$
    SELECT authority.propagate_changes( authority, bib ) FROM authority.bib_linking WHERE authority = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( TEXT ) RETURNS SETOF authority.full_rec AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
    if ($f->is_control_field) {
        return_next({ tag => $f->tag, value => $f->data });
    } else {
        for my $s ($f->subfields) {
            return_next({
                tag      => $f->tag,
                ind1     => $f->indicator(1),
                ind2     => $f->indicator(2),
                subfield => $s->[0],
                value    => $s->[1]
            });

        }
    }
}

return undef;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION authority.flatten_marc ( rid BIGINT ) RETURNS SETOF authority.full_rec AS $func$
DECLARE
    auth    authority.record_entry%ROWTYPE;
    output    authority.full_rec%ROWTYPE;
    field    RECORD;
BEGIN
    SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

    FOR field IN SELECT * FROM authority.flatten_marc( auth.marc ) LOOP
        output.record := rid;
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL THEN
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        CONTINUE WHEN output.value IS NULL;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

-- authority.rec_descriptor appears to be unused currently
CREATE OR REPLACE FUNCTION authority.reingest_authority_rec_descriptor( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.rec_descriptor WHERE record = auth_id;
--    INSERT INTO authority.rec_descriptor (record, record_status, char_encoding)
--        SELECT  auth_id, ;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.reingest_authority_full_rec( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.full_rec WHERE record = auth_id;
    INSERT INTO authority.full_rec (record, tag, ind1, ind2, subfield, value)
        SELECT record, tag, ind1, ind2, subfield, value FROM authority.flatten_marc( auth_id );

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for authority.record_entry
CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
          -- Should remove matching $0 from controlled fields at the same time?
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
-- authority.rec_descriptor is not currently used
--        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
--        IF NOT FOUND THEN
--            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
--        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER aaa_auth_ingest_or_delete AFTER INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.indexing_ingest_or_delete ();

-- Some records manage to get XML namespace declarations into each element,
-- like <datafield xmlns:marc="http://www.loc.gov/MARC21/slim"
-- This broke the old maintain_901(), so we'll make the regex more robust

CREATE OR REPLACE FUNCTION maintain_901 () RETURNS TRIGGER AS $func$
BEGIN
    -- Remove any existing 901 fields before we insert the authoritative one
    NEW.marc := REGEXP_REPLACE(NEW.marc, E'<datafield\s*[^<>]*?\s*tag="901".+?</datafield>', '', 'g');
    IF TG_TABLE_SCHEMA = 'biblio' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="a">' || NEW.tcn_value || E'</subfield>' ||
                '<subfield code="b">' || NEW.tcn_source || E'</subfield>' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                CASE WHEN NEW.owner IS NOT NULL THEN '<subfield code="o">' || NEW.owner || E'</subfield>' ELSE '' END ||
                CASE WHEN NEW.share_depth IS NOT NULL THEN '<subfield code="d">' || NEW.share_depth || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'authority' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'serial' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                '<subfield code="o">' || NEW.owning_lib || E'</subfield>' ||
                CASE WHEN NEW.record IS NOT NULL THEN '<subfield code="r">' || NEW.record || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSE
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_901();
CREATE TRIGGER b_maintain_901 BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_901();
 
-- In booking, elbow room defines:
--  a) how far in the future you must make a reservation on a given item if
--      that item will have to transit somewhere to fulfill the reservation.
--  b) how soon a reservation must be starting for the reserved item to
--      be op-captured by the checkin interface.

-- We don't want to clobber any default_elbow room at any level:

CREATE OR REPLACE FUNCTION pg_temp.default_elbow() RETURNS INTEGER AS $$
DECLARE
    existing    actor.org_unit_setting%ROWTYPE;
BEGIN
    SELECT INTO existing id FROM actor.org_unit_setting WHERE name = 'circ.booking_reservation.default_elbow_room';
    IF NOT FOUND THEN
        INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES (
            (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
            'circ.booking_reservation.default_elbow_room',
            '"1 day"'
        );
        RETURN 1;
    END IF;
    RETURN 0;
END;
$$ LANGUAGE plpgsql;

SELECT pg_temp.default_elbow();

DROP FUNCTION IF EXISTS action.usr_visible_circ_copies( INTEGER );

-- returns the distinct set of target copy IDs from a user's visible circulation history
CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( INTEGER ) RETURNS SETOF BIGINT AS $$
    SELECT DISTINCT(target_copy) FROM action.usr_visible_circs($1)
$$ LANGUAGE SQL;

ALTER TABLE action.in_house_use DROP CONSTRAINT in_house_use_item_fkey;
ALTER TABLE action.transit_copy DROP CONSTRAINT transit_copy_target_copy_fkey;
ALTER TABLE action.hold_transit_copy DROP CONSTRAINT ahtc_tc_fkey;
ALTER TABLE action.hold_copy_map DROP CONSTRAINT hold_copy_map_target_copy_fkey;

ALTER TABLE asset.stat_cat_entry_copy_map DROP CONSTRAINT a_sc_oc_fkey;

ALTER TABLE authority.record_entry ADD COLUMN owner INT;
ALTER TABLE serial.record_entry ADD COLUMN owner INT;

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'cat.maintain_control_numbers',
        oils_i18n_gettext(
            'cat.maintain_control_numbers',
            'Cat: Maintain 001/003/035 according to the MARC21 specification',
            'cgf', 
            'label'
        ),
        TRUE
    );

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.holds.empty_issuance_ok',
        oils_i18n_gettext(
            'circ.holds.empty_issuance_ok',
            'Holds: Allow holds on empty issuances',
            'cgf',
            'label'
        ),
        TRUE
    );

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.holds.usr_not_requestor',
        oils_i18n_gettext(
            'circ.holds.usr_not_requestor',
            'Holds: When testing hold matrix matchpoints, use the profile group of the receiving user instead of that of the requestor (affects staff-placed holds)',
            'cgf',
            'label'
        ),
        TRUE
    );

CREATE OR REPLACE FUNCTION maintain_control_numbers() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use Encode;
use Unicode::Normalize;

my $record = MARC::Record->new_from_xml($_TD->{new}{marc});
my $schema = $_TD->{table_schema};
my $rec_id = $_TD->{new}{id};

# Short-circuit if maintaining control numbers per MARC21 spec is not enabled
my $enable = spi_exec_query("SELECT enabled FROM config.global_flag WHERE name = 'cat.maintain_control_numbers'");
if (!($enable->{processed}) or $enable->{rows}[0]->{enabled} eq 'f') {
    return;
}

# Get the control number identifier from an OU setting based on $_TD->{new}{owner}
my $ou_cni = 'EVRGRN';

my $owner;
if ($schema eq 'serial') {
    $owner = $_TD->{new}{owning_lib};
} else {
    # are.owner and bre.owner can be null, so fall back to the consortial setting
    $owner = $_TD->{new}{owner} || 1;
}

my $ous_rv = spi_exec_query("SELECT value FROM actor.org_unit_ancestor_setting('cat.marc_control_number_identifier', $owner)");
if ($ous_rv->{processed}) {
    $ou_cni = $ous_rv->{rows}[0]->{value};
    $ou_cni =~ s/"//g; # Stupid VIM syntax highlighting"
} else {
    # Fall back to the shortname of the OU if there was no OU setting
    $ous_rv = spi_exec_query("SELECT shortname FROM actor.org_unit WHERE id = $owner");
    if ($ous_rv->{processed}) {
        $ou_cni = $ous_rv->{rows}[0]->{shortname};
    }
}

my ($create, $munge) = (0, 0);

my @scns = $record->field('035');

foreach my $id_field ('001', '003') {
    my $spec_value;
    my @controls = $record->field($id_field);

    if ($id_field eq '001') {
        $spec_value = $rec_id;
    } else {
        $spec_value = $ou_cni;
    }

    # Create the 001/003 if none exist
    if (scalar(@controls) == 1) {
        # Only one field; check to see if we need to munge it
        unless (grep $_->data() eq $spec_value, @controls) {
            $munge = 1;
        }
    } else {
        # Delete the other fields, as with more than 1 001/003 we do not know which 003/001 to match
        foreach my $control (@controls) {
            unless ($control->data() eq $spec_value) {
                $record->delete_field($control);
            }
        }
        $record->insert_fields_ordered(MARC::Field->new($id_field, $spec_value));
        $create = 1;
    }
}

# Now, if we need to munge the 001, we will first push the existing 001/003
# into the 035; but if the record did not have one (and one only) 001 and 003
# to begin with, skip this process
if ($munge and not $create) {
    my $scn = "(" . $record->field('003')->data() . ")" . $record->field('001')->data();

    # Do not create duplicate 035 fields
    unless (grep $_->subfield('a') eq $scn, @scns) {
        $record->insert_fields_ordered(MARC::Field->new('035', '', '', 'a' => $scn));
    }
}

# Set the 001/003 and update the MARC
if ($create or $munge) {
    $record->field('001')->data($rec_id);
    $record->field('003')->data($ou_cni);

    my $xml = $record->as_xml_record();
    $xml =~ s/\n//sgo;
    $xml =~ s/^<\?xml.+\?\s*>//go;
    $xml =~ s/>\s+</></go;
    $xml =~ s/\p{Cc}//go;

    # Embed a version of OpenILS::Application::AppUtils->entityize()
    # to avoid having to set PERL5LIB for PostgreSQL as well

    # If we are going to convert non-ASCII characters to XML entities,
    # we had better be dealing with a UTF8 string to begin with
    $xml = decode_utf8($xml);

    $xml = NFC($xml);

    # Convert raw ampersands to entities
    $xml =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    $xml =~ s/[\x00-\x1f]//go;
    $_TD->{new}{marc} = $xml;

    return "MODIFY";
}

return;
$func$ LANGUAGE PLPERLU;

CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_control_numbers();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_control_numbers();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE maintain_control_numbers();

INSERT INTO metabib.facet_entry (source, field, value)
    SELECT source, field, value FROM (
        SELECT * FROM metabib.author_field_entry
            UNION ALL
        SELECT * FROM metabib.keyword_field_entry
            UNION ALL
        SELECT * FROM metabib.identifier_field_entry
            UNION ALL
        SELECT * FROM metabib.title_field_entry
            UNION ALL
        SELECT * FROM metabib.subject_field_entry
            UNION ALL
        SELECT * FROM metabib.series_field_entry
        )x
    WHERE x.index_vector = '';
        
DELETE FROM metabib.author_field_entry WHERE index_vector = '';
DELETE FROM metabib.keyword_field_entry WHERE index_vector = '';
DELETE FROM metabib.identifier_field_entry WHERE index_vector = '';
DELETE FROM metabib.title_field_entry WHERE index_vector = '';
DELETE FROM metabib.subject_field_entry WHERE index_vector = '';
DELETE FROM metabib.series_field_entry WHERE index_vector = '';

CREATE INDEX metabib_facet_entry_field_idx ON metabib.facet_entry (field);
CREATE INDEX metabib_facet_entry_value_idx ON metabib.facet_entry (SUBSTRING(value,1,1024));
CREATE INDEX metabib_facet_entry_source_idx ON metabib.facet_entry (source);

-- copy OPAC visibility materialized view
CREATE OR REPLACE FUNCTION asset.refresh_opac_visible_copies_mat_view () RETURNS VOID AS $$

    TRUNCATE TABLE asset.opac_visible_copies;

    INSERT INTO asset.opac_visible_copies (id, circ_lib, record)
    SELECT  cp.id, cp.circ_lib, cn.record
    FROM  asset.copy cp
        JOIN asset.call_number cn ON (cn.id = cp.call_number)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
        JOIN biblio.record_entry b ON (cn.record = b.id)
    WHERE NOT cp.deleted
        AND NOT cn.deleted
        AND NOT b.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible;

$$ LANGUAGE SQL;
COMMENT ON FUNCTION asset.refresh_opac_visible_copies_mat_view() IS $$
Rebuild the copy OPAC visibility cache.  Useful during migrations.
$$;

-- and actually populate the table
SELECT asset.refresh_opac_visible_copies_mat_view();

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_query       TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_query := $$
            INSERT INTO asset.opac_visible_copies (id, circ_lib, record)
                SELECT  cp.id, cp.circ_lib, cn.record
                  FROM  asset.copy cp
                        JOIN asset.call_number cn ON (cn.id = cp.call_number)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                        JOIN biblio.record_entry b ON (cn.record = b.id)
                  WHERE NOT cp.deleted
                        AND NOT cn.deleted
                        AND NOT b.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN

        IF OLD.location    <> NEW.location OR
           OLD.call_number <> NEW.call_number OR
           OLD.status      <> NEW.status OR
           OLD.circ_lib    <> NEW.circ_lib THEN
            -- any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly
            do_remove := true;
            do_add := true;
        ELSE

            IF OLD.deleted <> NEW.deleted THEN
                IF NEW.deleted THEN
                    do_remove := true;
                ELSE
                    do_add := true;
                END IF;
            END IF;

            IF OLD.opac_visible <> NEW.opac_visible THEN
                IF OLD.opac_visible THEN
                    do_remove := true;
                ELSIF NOT do_remove THEN -- handle edge case where deleted item
                                        -- is also marked opac_visible
                    do_add := true;
                END IF;
            END IF;

        END IF;

        IF do_remove THEN
            DELETE FROM asset.opac_visible_copies WHERE id = NEW.id;
        END IF;
        IF do_add THEN
            add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME IN ('copy','unit') THEN
                add_query := add_query || 'AND cp.id = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'call_number' THEN
                add_query := add_query || 'AND cp.call_number = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_query := add_query || 'AND cn.record = ' || NEW.id || ';';
            END IF;
 
            EXECUTE add_query;
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_query := add_query || 'AND cp.call_number = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('record_entry') THEN
        RETURN NEW; -- don't have 'opac_visible'
    END IF;

    -- actor.org_unit, asset.copy_location, asset.copy_status
    IF NEW.opac_visible = OLD.opac_visible THEN -- do nothing

        RETURN NEW;

    ELSIF NEW.opac_visible THEN -- add rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            add_query := add_query || 'AND cp.circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_query := add_query || 'AND cp.location = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_query := add_query || 'AND cp.status = ' || NEW.id || ';';
        END IF;
 
        EXECUTE add_query;
 
    ELSE -- delete rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            remove_query := remove_query || 'location = ' || NEW.id || ');';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            remove_query := remove_query || 'status = ' || NEW.id || ');';
        END IF;
 
        EXECUTE remove_query;
 
    END IF;
 
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
COMMENT ON FUNCTION asset.cache_copy_visibility() IS $$
Trigger function to update the copy OPAC visiblity cache.
$$;
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy_location FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON config.copy_status FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON actor.org_unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

-- must create this rule explicitly; it is not inherited from asset.copy
CREATE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id;

CREATE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id);

CREATE OR REPLACE FUNCTION authority.merge_records ( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    bib_id        INT := 0;
    bib_rec       biblio.record_entry%ROWTYPE;
    auth_link     authority.bib_linking%ROWTYPE;
    ingest_same   boolean;
BEGIN

    -- Defining our terms:
    -- "target record" = the record that will survive the merge
    -- "source record" = the record that is sacrifing its existence and being
    --   replaced by the target record

    -- 1. Update all bib records with the ID from target_record in their $0
    FOR bib_rec IN SELECT bre.* FROM biblio.record_entry bre
      INNER JOIN authority.bib_linking abl ON abl.bib = bre.id
      WHERE abl.authority = source_record LOOP

        UPDATE biblio.record_entry
          SET marc = REGEXP_REPLACE(marc,
            E'(<subfield\\s+code="0"\\s*>[^<]*?\\))' || source_record || '<',
            E'\\1' || target_record || '<', 'g')
          WHERE id = bib_rec.id;

          moved_objects := moved_objects + 1;
    END LOOP;

    -- 2. Grab the current value of reingest on same MARC flag
    SELECT enabled INTO ingest_same
      FROM config.internal_flag
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 3. Temporarily set reingest on same to TRUE
    UPDATE config.internal_flag
      SET enabled = TRUE
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    -- 4. Make a harmless update to target_record to trigger auto-update
    --    in linked bibliographic records
    UPDATE authority.record_entry
      SET deleted = FALSE
      WHERE id = target_record;

    -- 5. "Delete" source_record
    DELETE FROM authority.record_entry
      WHERE id = source_record;

    -- 6. Set "reingest on same MARC" flag back to initial value
    UPDATE config.internal_flag
      SET enabled = ingest_same
      WHERE name = 'ingest.reingest.force_on_same_marc'
    ;

    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;

-- serial.record_entry already had an owner column spelled "owning_lib"
-- Adjust the table and affected functions accordingly

ALTER TABLE serial.record_entry DROP COLUMN owner;

CREATE TABLE actor.usr_saved_search (
    id              SERIAL          PRIMARY KEY,
	owner           INT             NOT NULL REFERENCES actor.usr (id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	name            TEXT            NOT NULL,
	create_date     TIMESTAMPTZ     NOT NULL DEFAULT now(),
	query_text      TEXT            NOT NULL,
	query_type      TEXT            NOT NULL
	                                CONSTRAINT valid_query_text CHECK (
	                                query_type IN ( 'URL' )) DEFAULT 'URL',
	                                -- we may add other types someday
	target          TEXT            NOT NULL
	                                CONSTRAINT valid_target CHECK (
	                                target IN ( 'record', 'metarecord', 'callnumber' )),
	CONSTRAINT name_once_per_user UNIQUE (owner, name)
);

-- Apply Dan Wells' changes to the serial schema, from the
-- seials-integration branch

CREATE TABLE serial.subscription_note (
	id           SERIAL PRIMARY KEY,
	subscription INT    NOT NULL
	                    REFERENCES serial.subscription (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);
CREATE INDEX serial_subscription_note_sub_idx ON serial.subscription_note (subscription);

CREATE TABLE serial.distribution_note (
	id           SERIAL PRIMARY KEY,
	distribution INT    NOT NULL
	                    REFERENCES serial.distribution (id)
	                    ON DELETE CASCADE
	                    DEFERRABLE INITIALLY DEFERRED,
	creator      INT    NOT NULL
	                    REFERENCES actor.usr (id)
	                    DEFERRABLE INITIALLY DEFERRED,
	create_date  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
	pub          BOOL   NOT NULL DEFAULT FALSE,
	title        TEXT   NOT NULL,
	value        TEXT   NOT NULL
);
CREATE INDEX serial_distribution_note_dist_idx ON serial.distribution_note (distribution);

------- Begin surgery on serial.unit

ALTER TABLE serial.unit
	DROP COLUMN label;

ALTER TABLE serial.unit
	RENAME COLUMN label_sort_key TO sort_key;

ALTER TABLE serial.unit
	RENAME COLUMN contents TO detailed_contents;

ALTER TABLE serial.unit
	ADD COLUMN summary_contents TEXT;

UPDATE serial.unit
SET summary_contents = detailed_contents;

ALTER TABLE serial.unit
	ALTER column summary_contents SET NOT NULL;

------- End surgery on serial.unit

-- DELETE FROM config.upgrade_log WHERE version = 'temp'; DELETE FROM action_trigger.event WHERE event_def IN (33,34); DELETE FROM action_trigger.environment WHERE event_def IN (33,34); DELETE FROM action_trigger.event_definition WHERE id IN (33,34); DELETE FROM action_trigger.hook WHERE key IN ( 'circ.format.missing_pieces.slip.print', 'circ.format.missing_pieces.letter.print' );

-- Now rebuild the constraints dropped via cascade.
-- ALTER TABLE acq.provider    ADD CONSTRAINT provider_edi_default_fkey FOREIGN KEY (edi_default) REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;
DROP INDEX IF EXISTS money.money_mat_summary_id_idx;
ALTER TABLE money.materialized_billable_xact_summary ADD PRIMARY KEY (id);

-- ALTER TABLE staging.billing_address_stage ADD PRIMARY KEY (row_id);

DELETE FROM config.metabib_field_index_norm_map
    WHERE norm IN (
        SELECT id 
            FROM config.index_normalizer
            WHERE func IN ('first_word', 'naco_normalize', 'split_date_range')
    )
    AND field = 18
;

-- We won't necessarily use all of these, but they are here for completeness.
-- Source is the EDI spec 6063 codelist, eg: http://www.stylusstudio.com/edifact/D04B/6063.htm
-- Values are the EDI code value + 1200

INSERT INTO acq.cancel_reason (org_unit, keep_debits, id, label, description) VALUES 
(1, 't', 1201, 'Discrete quantity', 'Individually separated and distinct quantity.'),
(1, 't', 1202, 'Charge', 'Quantity relevant for charge.'),
(1, 't', 1203, 'Cumulative quantity', 'Quantity accumulated.'),
(1, 't', 1204, 'Interest for overdrawn account', 'Interest for overdrawing the account.'),
(1, 't', 1205, 'Active ingredient dose per unit', 'The dosage of active ingredient per unit.'),
(1, 't', 1206, 'Auditor', 'The number of entities that audit accounts.'),
(1, 't', 1207, 'Branch locations, leased', 'The number of branch locations being leased by an entity.'),
(1, 't', 1208, 'Inventory quantity at supplier''s subject to inspection by', 'customer Quantity of goods which the customer requires the supplier to have in inventory and which may be inspected by the customer if desired.'),
(1, 't', 1209, 'Branch locations, owned', 'The number of branch locations owned by an entity.'),
(1, 't', 1210, 'Judgements registered', 'The number of judgements registered against an entity.'),
(1, 't', 1211, 'Split quantity', 'Part of the whole quantity.'),
(1, 't', 1212, 'Despatch quantity', 'Quantity despatched by the seller.'),
(1, 't', 1213, 'Liens registered', 'The number of liens registered against an entity.'),
(1, 't', 1214, 'Livestock', 'The number of animals kept for use or profit.'),
(1, 't', 1215, 'Insufficient funds returned cheques', 'The number of cheques returned due to insufficient funds.'),
(1, 't', 1216, 'Stolen cheques', 'The number of stolen cheques.'),
(1, 't', 1217, 'Quantity on hand', 'The total quantity of a product on hand at a location. This includes as well units awaiting return to manufacturer, units unavailable due to inspection procedures and undamaged stock available for despatch, resale or use.'),
(1, 't', 1218, 'Previous quantity', 'Quantity previously referenced.'),
(1, 't', 1219, 'Paid-in security shares', 'The number of security shares issued and for which full payment has been made.'),
(1, 't', 1220, 'Unusable quantity', 'Quantity not usable.'),
(1, 't', 1221, 'Ordered quantity', '[6024] The quantity which has been ordered.'),
(1, 't', 1222, 'Quantity at 100%', 'Equivalent quantity at 100% purity.'),
(1, 't', 1223, 'Active ingredient', 'Quantity at 100% active agent content.'),
(1, 't', 1224, 'Inventory quantity at supplier''s not subject to inspection', 'by customer Quantity of goods which the customer requires the supplier to have in inventory but which will not be checked by the customer.'),
(1, 't', 1225, 'Retail sales', 'Quantity of retail point of sale activity.'),
(1, 't', 1226, 'Promotion quantity', 'A quantity associated with a promotional event.'),
(1, 't', 1227, 'On hold for shipment', 'Article received which cannot be shipped in its present form.'),
(1, 't', 1228, 'Military sales quantity', 'Quantity of goods or services sold to a military organization.'),
(1, 't', 1229, 'On premises sales',  'Sale of product in restaurants or bars.'),
(1, 't', 1230, 'Off premises sales', 'Sale of product directly to a store.'),
(1, 't', 1231, 'Estimated annual volume', 'Volume estimated for a year.'),
(1, 't', 1232, 'Minimum delivery batch', 'Minimum quantity of goods delivered at one time.'),
(1, 't', 1233, 'Maximum delivery batch', 'Maximum quantity of goods delivered at one time.'),
(1, 't', 1234, 'Pipes', 'The number of tubes used to convey a substance.'),
(1, 't', 1235, 'Price break from', 'The minimum quantity of a quantity range for a specified (unit) price.'),
(1, 't', 1236, 'Price break to', 'Maximum quantity to which the price break applies.'),
(1, 't', 1237, 'Poultry', 'The number of domestic fowl.'),
(1, 't', 1238, 'Secured charges registered', 'The number of secured charges registered against an entity.'),
(1, 't', 1239, 'Total properties owned', 'The total number of properties owned by an entity.'),
(1, 't', 1240, 'Normal delivery', 'Quantity normally delivered by the seller.'),
(1, 't', 1241, 'Sales quantity not included in the replenishment', 'calculation Sales which will not be included in the calculation of replenishment requirements.'),
(1, 't', 1242, 'Maximum supply quantity, supplier endorsed', 'Maximum supply quantity endorsed by a supplier.'),
(1, 't', 1243, 'Buyer', 'The number of buyers.'),
(1, 't', 1244, 'Debenture bond', 'The number of fixed-interest bonds of an entity backed by general credit rather than specified assets.'),
(1, 't', 1245, 'Debentures filed against directors', 'The number of notices of indebtedness filed against an entity''s directors.'),
(1, 't', 1246, 'Pieces delivered', 'Number of pieces actually received at the final destination.'),
(1, 't', 1247, 'Invoiced quantity', 'The quantity as per invoice.'),
(1, 't', 1248, 'Received quantity', 'The quantity which has been received.'),
(1, 't', 1249, 'Chargeable distance', '[6110] The distance between two points for which a specific tariff applies.'),
(1, 't', 1250, 'Disposition undetermined quantity', 'Product quantity that has not yet had its disposition determined.'),
(1, 't', 1251, 'Inventory category transfer', 'Inventory that has been moved from one inventory category to another.'),
(1, 't', 1252, 'Quantity per pack', 'Quantity for each pack.'),
(1, 't', 1253, 'Minimum order quantity', 'Minimum quantity of goods for an order.'),
(1, 't', 1254, 'Maximum order quantity', 'Maximum quantity of goods for an order.'),
(1, 't', 1255, 'Total sales', 'The summation of total quantity sales.'),
(1, 't', 1256, 'Wholesaler to wholesaler sales', 'Sale of product to other wholesalers by a wholesaler.'),
(1, 't', 1257, 'In transit quantity', 'A quantity that is en route.'),
(1, 't', 1258, 'Quantity withdrawn', 'Quantity withdrawn from a location.'),
(1, 't', 1259, 'Numbers of consumer units in the traded unit', 'Number of units for consumer sales in a unit for trading.'),
(1, 't', 1260, 'Current inventory quantity available for shipment', 'Current inventory quantity available for shipment.'),
(1, 't', 1261, 'Return quantity', 'Quantity of goods returned.'),
(1, 't', 1262, 'Sorted quantity', 'The quantity that is sorted.'),
(1, 'f', 1263, 'Sorted quantity rejected', 'The sorted quantity that is rejected.'),
(1, 't', 1264, 'Scrap quantity', 'Remainder of the total quantity after split deliveries.'),
(1, 'f', 1265, 'Destroyed quantity', 'Quantity of goods destroyed.'),
(1, 't', 1266, 'Committed quantity', 'Quantity a party is committed to.'),
(1, 't', 1267, 'Estimated reading quantity', 'The value that is estimated to be the reading of a measuring device (e.g. meter).'),
(1, 't', 1268, 'End quantity', 'The quantity recorded at the end of an agreement or period.'),
(1, 't', 1269, 'Start quantity', 'The quantity recorded at the start of an agreement or period.'),
(1, 't', 1270, 'Cumulative quantity received', 'Cumulative quantity of all deliveries of this article received by the buyer.'),
(1, 't', 1271, 'Cumulative quantity ordered', 'Cumulative quantity of all deliveries, outstanding and scheduled orders.'),
(1, 't', 1272, 'Cumulative quantity received end of prior year', 'Cumulative quantity of all deliveries of the product received by the buyer till end of prior year.'),
(1, 't', 1273, 'Outstanding quantity', 'Difference between quantity ordered and quantity received.'),
(1, 't', 1274, 'Latest cumulative quantity', 'Cumulative quantity after complete delivery of all scheduled quantities of the product.'),
(1, 't', 1275, 'Previous highest cumulative quantity', 'Cumulative quantity after complete delivery of all scheduled quantities of the product from a prior schedule period.'),
(1, 't', 1276, 'Adjusted corrector reading', 'A corrector reading after it has been adjusted.'),
(1, 't', 1277, 'Work days', 'Number of work days, e.g. per respective period.'),
(1, 't', 1278, 'Cumulative quantity scheduled', 'Adding the quantity actually scheduled to previous cumulative quantity.'),
(1, 't', 1279, 'Previous cumulative quantity', 'Cumulative quantity prior the actual order.'),
(1, 't', 1280, 'Unadjusted corrector reading', 'A corrector reading before it has been adjusted.'),
(1, 't', 1281, 'Extra unplanned delivery', 'Non scheduled additional quantity.'),
(1, 't', 1282, 'Quantity requirement for sample inspection', 'Required quantity for sample inspection.'),
(1, 't', 1283, 'Backorder quantity', 'The quantity of goods that is on back-order.'),
(1, 't', 1284, 'Urgent delivery quantity', 'Quantity for urgent delivery.'),
(1, 'f', 1285, 'Previous order quantity to be cancelled', 'Quantity ordered previously to be cancelled.'),
(1, 't', 1286, 'Normal reading quantity', 'The value recorded or read from a measuring device (e.g. meter) in the normal conditions.'),
(1, 't', 1287, 'Customer reading quantity', 'The value recorded or read from a measuring device (e.g. meter) by the customer.'),
(1, 't', 1288, 'Information reading quantity', 'The value recorded or read from a measuring device (e.g. meter) for information purposes.'),
(1, 't', 1289, 'Quality control held', 'Quantity of goods held pending completion of a quality control assessment.'),
(1, 't', 1290, 'As is quantity', 'Quantity as it is in the existing circumstances.'),
(1, 't', 1291, 'Open quantity', 'Quantity remaining after partial delivery.'),
(1, 't', 1292, 'Final delivery quantity', 'Quantity of final delivery to a respective order.'),
(1, 't', 1293, 'Subsequent delivery quantity', 'Quantity delivered to a respective order after it''s final delivery.'),
(1, 't', 1294, 'Substitutional quantity', 'Quantity delivered replacing previous deliveries.'),
(1, 't', 1295, 'Redelivery after post processing', 'Quantity redelivered after post processing.'),
(1, 'f', 1296, 'Quality control failed', 'Quantity of goods which have failed quality control.'),
(1, 't', 1297, 'Minimum inventory', 'Minimum stock quantity on which replenishment is based.'),
(1, 't', 1298, 'Maximum inventory', 'Maximum stock quantity on which replenishment is based.'),
(1, 't', 1299, 'Estimated quantity', 'Quantity estimated.'),
(1, 't', 1300, 'Chargeable weight', 'The weight on which charges are based.'),
(1, 't', 1301, 'Chargeable gross weight', 'The gross weight on which charges are based.'),
(1, 't', 1302, 'Chargeable tare weight', 'The tare weight on which charges are based.'),
(1, 't', 1303, 'Chargeable number of axles', 'The number of axles on which charges are based.'),
(1, 't', 1304, 'Chargeable number of containers', 'The number of containers on which charges are based.'),
(1, 't', 1305, 'Chargeable number of rail wagons', 'The number of rail wagons on which charges are based.'),
(1, 't', 1306, 'Chargeable number of packages', 'The number of packages on which charges are based.'),
(1, 't', 1307, 'Chargeable number of units', 'The number of units on which charges are based.'),
(1, 't', 1308, 'Chargeable period', 'The period of time on which charges are based.'),
(1, 't', 1309, 'Chargeable volume', 'The volume on which charges are based.'),
(1, 't', 1310, 'Chargeable cubic measurements', 'The cubic measurements on which charges are based.'),
(1, 't', 1311, 'Chargeable surface', 'The surface area on which charges are based.'),
(1, 't', 1312, 'Chargeable length', 'The length on which charges are based.'),
(1, 't', 1313, 'Quantity to be delivered', 'The quantity to be delivered.'),
(1, 't', 1314, 'Number of passengers', 'Total number of passengers on the conveyance.'),
(1, 't', 1315, 'Number of crew', 'Total number of crew members on the conveyance.'),
(1, 't', 1316, 'Number of transport documents', 'Total number of air waybills, bills of lading, etc. being reported for a specific conveyance.'),
(1, 't', 1317, 'Quantity landed', 'Quantity of goods actually arrived.'),
(1, 't', 1318, 'Quantity manifested', 'Quantity of goods contracted for delivery by the carrier.'),
(1, 't', 1319, 'Short shipped', 'Indication that part of the consignment was not shipped.'),
(1, 't', 1320, 'Split shipment', 'Indication that the consignment has been split into two or more shipments.'),
(1, 't', 1321, 'Over shipped', 'The quantity of goods shipped that exceeds the quantity contracted.'),
(1, 't', 1322, 'Short-landed goods', 'If quantity of goods actually landed is less than the quantity which appears in the documentation. This quantity is the difference between these quantities.'),
(1, 't', 1323, 'Surplus goods', 'If quantity of goods actually landed is more than the quantity which appears in the documentation. This quantity is the difference between these quantities.'),
(1, 'f', 1324, 'Damaged goods', 'Quantity of goods which have deteriorated in transport such that they cannot be used for the purpose for which they were originally intended.'),
(1, 'f', 1325, 'Pilferage goods', 'Quantity of goods stolen during transport.'),
(1, 'f', 1326, 'Lost goods', 'Quantity of goods that disappeared in transport.'),
(1, 't', 1327, 'Report difference', 'The quantity concerning the same transaction differs between two documents/messages and the source of this difference is a typing error.'),
(1, 't', 1328, 'Quantity loaded', 'Quantity of goods loaded onto a means of transport.'),
(1, 't', 1329, 'Units per unit price', 'Number of units per unit price.'),
(1, 't', 1330, 'Allowance', 'Quantity relevant for allowance.'),
(1, 't', 1331, 'Delivery quantity', 'Quantity required by buyer to be delivered.'),
(1, 't', 1332, 'Cumulative quantity, preceding period, planned', 'Cumulative quantity originally planned for the preceding period.'),
(1, 't', 1333, 'Cumulative quantity, preceding period, reached', 'Cumulative quantity reached in the preceding period.'),
(1, 't', 1334, 'Cumulative quantity, actual planned',            'Cumulative quantity planned for now.'),
(1, 't', 1335, 'Period quantity, planned', 'Quantity planned for this period.'),
(1, 't', 1336, 'Period quantity, reached', 'Quantity reached during this period.'),
(1, 't', 1337, 'Cumulative quantity, preceding period, estimated', 'Estimated cumulative quantity reached in the preceding period.'),
(1, 't', 1338, 'Cumulative quantity, actual estimated',            'Estimated cumulative quantity reached now.'),
(1, 't', 1339, 'Cumulative quantity, preceding period, measured', 'Surveyed cumulative quantity reached in the preceding period.'),
(1, 't', 1340, 'Cumulative quantity, actual measured', 'Surveyed cumulative quantity reached now.'),
(1, 't', 1341, 'Period quantity, measured',            'Surveyed quantity reached during this period.'),
(1, 't', 1342, 'Total quantity, planned', 'Total quantity planned.'),
(1, 't', 1343, 'Quantity, remaining', 'Quantity remaining.'),
(1, 't', 1344, 'Tolerance', 'Plus or minus tolerance expressed as a monetary amount.'),
(1, 't', 1345, 'Actual stock',          'The stock on hand, undamaged, and available for despatch, sale or use.'),
(1, 't', 1346, 'Model or target stock', 'The stock quantity required or planned to have on hand, undamaged and available for use.'),
(1, 't', 1347, 'Direct shipment quantity', 'Quantity to be shipped directly to a customer from a manufacturing site.'),
(1, 't', 1348, 'Amortization total quantity',     'Indication of final quantity for amortization.'),
(1, 't', 1349, 'Amortization order quantity',     'Indication of actual share of the order quantity for amortization.'),
(1, 't', 1350, 'Amortization cumulated quantity', 'Indication of actual cumulated quantity of previous and actual amortization order quantity.'),
(1, 't', 1351, 'Quantity advised',  'Quantity advised by supplier or shipper, in contrast to quantity actually received.'),
(1, 't', 1352, 'Consignment stock', 'Quantity of goods with an external customer which is still the property of the supplier. Payment for these goods is only made to the supplier when the ownership has been transferred between the trading partners.'),
(1, 't', 1353, 'Statistical sales quantity', 'Quantity of goods sold in a specified period.'),
(1, 't', 1354, 'Sales quantity planned',     'Quantity of goods required to meet future demands. - Market intelligence quantity.'),
(1, 't', 1355, 'Replenishment quantity',     'Quantity required to maintain the requisite on-hand stock of goods.'),
(1, 't', 1356, 'Inventory movement quantity', 'To specify the quantity of an inventory movement.'),
(1, 't', 1357, 'Opening stock balance quantity', 'To specify the quantity of an opening stock balance.'),
(1, 't', 1358, 'Closing stock balance quantity', 'To specify the quantity of a closing stock balance.'),
(1, 't', 1359, 'Number of stops', 'Number of times a means of transport stops before arriving at destination.'),
(1, 't', 1360, 'Minimum production batch', 'The quantity specified is the minimum output from a single production run.'),
(1, 't', 1361, 'Dimensional sample quantity', 'The quantity defined is a sample for the purpose of validating dimensions.'),
(1, 't', 1362, 'Functional sample quantity', 'The quantity defined is a sample for the purpose of validating function and performance.'),
(1, 't', 1363, 'Pre-production quantity', 'Quantity of the referenced item required prior to full production.'),
(1, 't', 1364, 'Delivery batch', 'Quantity of the referenced item which constitutes a standard batch for deliver purposes.'),
(1, 't', 1365, 'Delivery batch multiple', 'The multiples in which delivery batches can be supplied.'),
(1, 't', 1366, 'All time buy',             'The total quantity of the referenced covering all future needs. Further orders of the referenced item are not expected.'),
(1, 't', 1367, 'Total delivery quantity',  'The total quantity required by the buyer to be delivered.'),
(1, 't', 1368, 'Single delivery quantity', 'The quantity required by the buyer to be delivered in a single shipment.'),
(1, 't', 1369, 'Supplied quantity',  'Quantity of the referenced item actually shipped.'),
(1, 't', 1370, 'Allocated quantity', 'Quantity of the referenced item allocated from available stock for delivery.'),
(1, 't', 1371, 'Maximum stackability', 'The number of pallets/handling units which can be safely stacked one on top of another.'),
(1, 't', 1372, 'Amortisation quantity', 'The quantity of the referenced item which has a cost for tooling amortisation included in the item price.'),
(1, 't', 1373, 'Previously amortised quantity', 'The cumulative quantity of the referenced item which had a cost for tooling amortisation included in the item price.'),
(1, 't', 1374, 'Total amortisation quantity', 'The total quantity of the referenced item which has a cost for tooling amortisation included in the item price.'),
(1, 't', 1375, 'Number of moulds', 'The number of pressing moulds contained within a single piece of the referenced tooling.'),
(1, 't', 1376, 'Concurrent item output of tooling', 'The number of related items which can be produced simultaneously with a single piece of the referenced tooling.'),
(1, 't', 1377, 'Periodic capacity of tooling', 'Maximum production output of the referenced tool over a period of time.'),
(1, 't', 1378, 'Lifetime capacity of tooling', 'Maximum production output of the referenced tool over its productive lifetime.'),
(1, 't', 1379, 'Number of deliveries per despatch period', 'The number of deliveries normally expected to be despatched within each despatch period.'),
(1, 't', 1380, 'Provided quantity', 'The quantity of a referenced component supplied by the buyer for manufacturing of an ordered item.'),
(1, 't', 1381, 'Maximum production batch', 'The quantity specified is the maximum output from a single production run.'),
(1, 'f', 1382, 'Cancelled quantity', 'Quantity of the referenced item which has previously been ordered and is now cancelled.'),
(1, 't', 1383, 'No delivery requirement in this instruction', 'This delivery instruction does not contain any delivery requirements.'),
(1, 't', 1384, 'Quantity of material in ordered time', 'Quantity of the referenced material within the ordered time.'),
(1, 'f', 1385, 'Rejected quantity', 'The quantity of received goods rejected for quantity reasons.'),
(1, 't', 1386, 'Cumulative quantity scheduled up to accumulation start date', 'The cumulative quantity scheduled up to the accumulation start date.'),
(1, 't', 1387, 'Quantity scheduled', 'The quantity scheduled for delivery.'),
(1, 't', 1388, 'Number of identical handling units', 'Number of identical handling units in terms of type and contents.'),
(1, 't', 1389, 'Number of packages in handling unit', 'The number of packages contained in one handling unit.'),
(1, 't', 1390, 'Despatch note quantity', 'The item quantity specified on the despatch note.'),
(1, 't', 1391, 'Adjustment to inventory quantity', 'An adjustment to inventory quantity.'),
(1, 't', 1392, 'Free goods quantity',    'Quantity of goods which are free of charge.'),
(1, 't', 1393, 'Free quantity included', 'Quantity included to which no charge is applicable.'),
(1, 't', 1394, 'Received and accepted',  'Quantity which has been received and accepted at a given location.'),
(1, 'f', 1395, 'Received, not accepted, to be returned',  'Quantity which has been received but not accepted at a given location and which will consequently be returned to the relevant party.'),
(1, 'f', 1396, 'Received, not accepted, to be destroyed', 'Quantity which has been received but not accepted at a given location and which will consequently be destroyed.'),
(1, 't', 1397, 'Reordering level', 'Quantity at which an order may be triggered to replenish.'),
(1, 't', 1399, 'Inventory withdrawal quantity', 'Quantity which has been withdrawn from inventory since the last inventory report.'),
(1, 't', 1400, 'Free quantity not included', 'Free quantity not included in ordered quantity.'),
(1, 't', 1401, 'Recommended overhaul and repair quantity', 'To indicate the recommended quantity of an article required to support overhaul and repair activities.'),
(1, 't', 1402, 'Quantity per next higher assembly', 'To indicate the quantity required for the next higher assembly.'),
(1, 't', 1403, 'Quantity per unit of issue', 'Provides the standard quantity of an article in which one unit can be issued.'),
(1, 't', 1404, 'Cumulative scrap quantity',  'Provides the cumulative quantity of an item which has been identified as scrapped.'),
(1, 't', 1405, 'Publication turn size', 'The quantity of magazines or newspapers grouped together with the spine facing alternate directions in a bundle.'),
(1, 't', 1406, 'Recommended maintenance quantity', 'Recommended quantity of an article which is required to meet an agreed level of maintenance.'),
(1, 't', 1407, 'Labour hours', 'Number of labour hours.'),
(1, 't', 1408, 'Quantity requirement for maintenance and repair of', 'equipment Quantity of the material needed to maintain and repair equipment.'),
(1, 't', 1409, 'Additional replenishment demand quantity', 'Incremental needs over and above normal replenishment calculations, but not intended to permanently change the model parameters.'),
(1, 't', 1410, 'Returned by consumer quantity', 'Quantity returned by a consumer.'),
(1, 't', 1411, 'Replenishment override quantity', 'Quantity to override the normal replenishment model calculations, but not intended to permanently change the model parameters.'),
(1, 't', 1412, 'Quantity sold, net', 'Net quantity sold which includes returns of saleable inventory and other adjustments.'),
(1, 't', 1413, 'Transferred out quantity',   'Quantity which was transferred out of this location.'),
(1, 't', 1414, 'Transferred in quantity',    'Quantity which was transferred into this location.'),
(1, 't', 1415, 'Unsaleable quantity',        'Quantity of inventory received which cannot be sold in its present condition.'),
(1, 't', 1416, 'Consumer reserved quantity', 'Quantity reserved for consumer delivery or pickup and not yet withdrawn from inventory.'),
(1, 't', 1417, 'Out of inventory quantity',  'Quantity of inventory which was requested but was not available.'),
(1, 't', 1418, 'Quantity returned, defective or damaged', 'Quantity returned in a damaged or defective condition.'),
(1, 't', 1419, 'Taxable quantity',           'Quantity subject to taxation.'),
(1, 't', 1420, 'Meter reading', 'The numeric value of measure units counted by a meter.'),
(1, 't', 1421, 'Maximum requestable quantity', 'The maximum quantity which may be requested.'),
(1, 't', 1422, 'Minimum requestable quantity', 'The minimum quantity which may be requested.'),
(1, 't', 1423, 'Daily average quantity', 'The quantity for a defined period divided by the number of days of the period.'),
(1, 't', 1424, 'Budgeted hours',     'The number of budgeted hours.'),
(1, 't', 1425, 'Actual hours',       'The number of actual hours.'),
(1, 't', 1426, 'Earned value hours', 'The number of earned value hours.'),
(1, 't', 1427, 'Estimated hours',    'The number of estimated hours.'),
(1, 't', 1428, 'Level resource task quantity', 'Quantity of a resource that is level for the duration of the task.'),
(1, 't', 1429, 'Available resource task quantity', 'Quantity of a resource available to complete a task.'),
(1, 't', 1430, 'Work time units',   'Quantity of work units of time.'),
(1, 't', 1431, 'Daily work shifts', 'Quantity of work shifts per day.'),
(1, 't', 1432, 'Work time units per shift', 'Work units of time per work shift.'),
(1, 't', 1433, 'Work calendar units',       'Work calendar units of time.'),
(1, 't', 1434, 'Elapsed duration',   'Quantity representing the elapsed duration.'),
(1, 't', 1435, 'Remaining duration', 'Quantity representing the remaining duration.'),
(1, 't', 1436, 'Original duration',  'Quantity representing the original duration.'),
(1, 't', 1437, 'Current duration',   'Quantity representing the current duration.'),
(1, 't', 1438, 'Total float time',   'Quantity representing the total float time.'),
(1, 't', 1439, 'Free float time',    'Quantity representing the free float time.'),
(1, 't', 1440, 'Lag time',           'Quantity representing lag time.'),
(1, 't', 1441, 'Lead time',          'Quantity representing lead time.'),
(1, 't', 1442, 'Number of months', 'The number of months.'),
(1, 't', 1443, 'Reserved quantity customer direct delivery sales', 'Quantity of products reserved for sales delivered direct to the customer.'),
(1, 't', 1444, 'Reserved quantity retail sales', 'Quantity of products reserved for retail sales.'),
(1, 't', 1445, 'Consolidated discount inventory', 'A quantity of inventory supplied at consolidated discount terms.'),
(1, 't', 1446, 'Returns replacement quantity',    'A quantity of goods issued as a replacement for a returned quantity.'),
(1, 't', 1447, 'Additional promotion sales forecast quantity', 'A forecast of additional quantity which will be sold during a period of promotional activity.'),
(1, 't', 1448, 'Reserved quantity', 'Quantity reserved for specific purposes.'),
(1, 't', 1449, 'Quantity displayed not available for sale', 'Quantity displayed within a retail outlet but not available for sale.'),
(1, 't', 1450, 'Inventory discrepancy', 'The difference recorded between theoretical and physical inventory.'),
(1, 't', 1451, 'Incremental order quantity', 'The incremental quantity by which ordering is carried out.'),
(1, 't', 1452, 'Quantity requiring manipulation before despatch', 'A quantity of goods which needs manipulation before despatch.'),
(1, 't', 1453, 'Quantity in quarantine',              'A quantity of goods which are held in a restricted area for quarantine purposes.'),
(1, 't', 1454, 'Quantity withheld by owner of goods', 'A quantity of goods which has been withheld by the owner of the goods.'),
(1, 't', 1455, 'Quantity not available for despatch', 'A quantity of goods not available for despatch.'),
(1, 't', 1456, 'Quantity awaiting delivery', 'Quantity of goods which are awaiting delivery.'),
(1, 't', 1457, 'Quantity in physical inventory',      'A quantity of goods held in physical inventory.'),
(1, 't', 1458, 'Quantity held by logistic service provider', 'Quantity of goods under the control of a logistic service provider.'),
(1, 't', 1459, 'Optimal quantity', 'The optimal quantity for a given purpose.'),
(1, 't', 1460, 'Delivery quantity balance', 'The difference between the scheduled quantity and the quantity delivered to the consignee at a given date.'),
(1, 't', 1461, 'Cumulative quantity shipped', 'Cumulative quantity of all shipments.'),
(1, 't', 1462, 'Quantity suspended', 'The quantity of something which is suspended.'),
(1, 't', 1463, 'Control quantity', 'The quantity designated for control purposes.'),
(1, 't', 1464, 'Equipment quantity', 'A count of a quantity of equipment.'),
(1, 't', 1465, 'Factor', 'Number by which the measured unit has to be multiplied to calculate the units used.'),
(1, 't', 1466, 'Unsold quantity held by wholesaler', 'Unsold quantity held by the wholesaler.'),
(1, 't', 1467, 'Quantity held by delivery vehicle', 'Quantity of goods held by the delivery vehicle.'),
(1, 't', 1468, 'Quantity held by retail outlet', 'Quantity held by the retail outlet.'),
(1, 'f', 1469, 'Rejected return quantity', 'A quantity for return which has been rejected.'),
(1, 't', 1470, 'Accounts', 'The number of accounts.'),
(1, 't', 1471, 'Accounts placed for collection', 'The number of accounts placed for collection.'),
(1, 't', 1472, 'Activity codes', 'The number of activity codes.'),
(1, 't', 1473, 'Agents', 'The number of agents.'),
(1, 't', 1474, 'Airline attendants', 'The number of airline attendants.'),
(1, 't', 1475, 'Authorised shares',  'The number of shares authorised for issue.'),
(1, 't', 1476, 'Employee average',   'The average number of employees.'),
(1, 't', 1477, 'Branch locations',   'The number of branch locations.'),
(1, 't', 1478, 'Capital changes',    'The number of capital changes made.'),
(1, 't', 1479, 'Clerks', 'The number of clerks.'),
(1, 't', 1480, 'Companies in same activity', 'The number of companies doing business in the same activity category.'),
(1, 't', 1481, 'Companies included in consolidated financial statement', 'The number of companies included in a consolidated financial statement.'),
(1, 't', 1482, 'Cooperative shares', 'The number of cooperative shares.'),
(1, 't', 1483, 'Creditors',   'The number of creditors.'),
(1, 't', 1484, 'Departments', 'The number of departments.'),
(1, 't', 1485, 'Design employees', 'The number of employees involved in the design process.'),
(1, 't', 1486, 'Physicians', 'The number of medical doctors.'),
(1, 't', 1487, 'Domestic affiliated companies', 'The number of affiliated companies located within the country.'),
(1, 't', 1488, 'Drivers', 'The number of drivers.'),
(1, 't', 1489, 'Employed at location',     'The number of employees at the specified location.'),
(1, 't', 1490, 'Employed by this company', 'The number of employees at the specified company.'),
(1, 't', 1491, 'Total employees',    'The total number of employees.'),
(1, 't', 1492, 'Employees shared',   'The number of employees shared among entities.'),
(1, 't', 1493, 'Engineers',          'The number of engineers.'),
(1, 't', 1494, 'Estimated accounts', 'The estimated number of accounts.'),
(1, 't', 1495, 'Estimated employees at location', 'The estimated number of employees at the specified location.'),
(1, 't', 1496, 'Estimated total employees',       'The total estimated number of employees.'),
(1, 't', 1497, 'Executives', 'The number of executives.'),
(1, 't', 1498, 'Agricultural workers',   'The number of agricultural workers.'),
(1, 't', 1499, 'Financial institutions', 'The number of financial institutions.'),
(1, 't', 1500, 'Floors occupied', 'The number of floors occupied.'),
(1, 't', 1501, 'Foreign related entities', 'The number of related entities located outside the country.'),
(1, 't', 1502, 'Group employees',    'The number of employees within the group.'),
(1, 't', 1503, 'Indirect employees', 'The number of employees not associated with direct production.'),
(1, 't', 1504, 'Installers',    'The number of employees involved with the installation process.'),
(1, 't', 1505, 'Invoices',      'The number of invoices.'),
(1, 't', 1506, 'Issued shares', 'The number of shares actually issued.'),
(1, 't', 1507, 'Labourers',     'The number of labourers.'),
(1, 't', 1508, 'Manufactured units', 'The number of units manufactured.'),
(1, 't', 1509, 'Maximum number of employees', 'The maximum number of people employed.'),
(1, 't', 1510, 'Maximum number of employees at location', 'The maximum number of people employed at a location.'),
(1, 't', 1511, 'Members in group', 'The number of members within a group.'),
(1, 't', 1512, 'Minimum number of employees at location', 'The minimum number of people employed at a location.'),
(1, 't', 1513, 'Minimum number of employees', 'The minimum number of people employed.'),
(1, 't', 1514, 'Non-union employees', 'The number of employees not belonging to a labour union.'),
(1, 't', 1515, 'Floors', 'The number of floors in a building.'),
(1, 't', 1516, 'Nurses', 'The number of nurses.'),
(1, 't', 1517, 'Office workers', 'The number of workers in an office.'),
(1, 't', 1518, 'Other employees', 'The number of employees otherwise categorised.'),
(1, 't', 1519, 'Part time employees', 'The number of employees working on a part time basis.'),
(1, 't', 1520, 'Accounts payable average overdue days', 'The average number of days accounts payable are overdue.'),
(1, 't', 1521, 'Pilots', 'The number of pilots.'),
(1, 't', 1522, 'Plant workers', 'The number of workers within a plant.'),
(1, 't', 1523, 'Previous number of accounts', 'The number of accounts which preceded the current count.'),
(1, 't', 1524, 'Previous number of branch locations', 'The number of branch locations which preceded the current count.'),
(1, 't', 1525, 'Principals included as employees', 'The number of principals which are included in the count of employees.'),
(1, 't', 1526, 'Protested bills', 'The number of bills which are protested.'),
(1, 't', 1527, 'Registered brands distributed', 'The number of registered brands which are being distributed.'),
(1, 't', 1528, 'Registered brands manufactured', 'The number of registered brands which are being manufactured.'),
(1, 't', 1529, 'Related business entities', 'The number of related business entities.'),
(1, 't', 1530, 'Relatives employed', 'The number of relatives which are counted as employees.'),
(1, 't', 1531, 'Rooms',        'The number of rooms.'),
(1, 't', 1532, 'Salespersons', 'The number of salespersons.'),
(1, 't', 1533, 'Seats',        'The number of seats.'),
(1, 't', 1534, 'Shareholders', 'The number of shareholders.'),
(1, 't', 1535, 'Shares of common stock', 'The number of shares of common stock.'),
(1, 't', 1536, 'Shares of preferred stock', 'The number of shares of preferred stock.'),
(1, 't', 1537, 'Silent partners', 'The number of silent partners.'),
(1, 't', 1538, 'Subcontractors',  'The number of subcontractors.'),
(1, 't', 1539, 'Subsidiaries',    'The number of subsidiaries.'),
(1, 't', 1540, 'Law suits',       'The number of law suits.'),
(1, 't', 1541, 'Suppliers',       'The number of suppliers.'),
(1, 't', 1542, 'Teachers',        'The number of teachers.'),
(1, 't', 1543, 'Technicians',     'The number of technicians.'),
(1, 't', 1544, 'Trainees',        'The number of trainees.'),
(1, 't', 1545, 'Union employees', 'The number of employees who are members of a labour union.'),
(1, 't', 1546, 'Number of units', 'The quantity of units.'),
(1, 't', 1547, 'Warehouse employees', 'The number of employees who work in a warehouse setting.'),
(1, 't', 1548, 'Shareholders holding remainder of shares', 'Number of shareholders owning the remainder of shares.'),
(1, 't', 1549, 'Payment orders filed', 'Number of payment orders filed.'),
(1, 't', 1550, 'Uncovered cheques', 'Number of uncovered cheques.'),
(1, 't', 1551, 'Auctions', 'Number of auctions.'),
(1, 't', 1552, 'Units produced', 'The number of units produced.'),
(1, 't', 1553, 'Added employees', 'Number of employees that were added to the workforce.'),
(1, 't', 1554, 'Number of added locations', 'Number of locations that were added.'),
(1, 't', 1555, 'Total number of foreign subsidiaries not included in', 'financial statement The total number of foreign subsidiaries not included in the financial statement.'),
(1, 't', 1556, 'Number of closed locations', 'Number of locations that were closed.'),
(1, 't', 1557, 'Counter clerks', 'The number of clerks that work behind a flat-topped fitment.'),
(1, 't', 1558, 'Payment experiences in the last 3 months', 'The number of payment experiences received for an entity over the last 3 months.'),
(1, 't', 1559, 'Payment experiences in the last 12 months', 'The number of payment experiences received for an entity over the last 12 months.'),
(1, 't', 1560, 'Total number of subsidiaries not included in the financial', 'statement The total number of subsidiaries not included in the financial statement.'),
(1, 't', 1561, 'Paid-in common shares', 'The number of paid-in common shares.'),
(1, 't', 1562, 'Total number of domestic subsidiaries not included in', 'financial statement The total number of domestic subsidiaries not included in the financial statement.'),
(1, 't', 1563, 'Total number of foreign subsidiaries included in financial statement', 'The total number of foreign subsidiaries included in the financial statement.'),
(1, 't', 1564, 'Total number of domestic subsidiaries included in financial statement', 'The total number of domestic subsidiaries included in the financial statement.'),
(1, 't', 1565, 'Total transactions', 'The total number of transactions.'),
(1, 't', 1566, 'Paid-in preferred shares', 'The number of paid-in preferred shares.'),
(1, 't', 1567, 'Employees', 'Code specifying the quantity of persons working for a company, whose services are used for pay.'),
(1, 't', 1568, 'Active ingredient dose per unit, dispensed', 'The dosage of active ingredient per dispensed unit.'),
(1, 't', 1569, 'Budget', 'Budget quantity.'),
(1, 't', 1570, 'Budget, cumulative to date', 'Budget quantity, cumulative to date.'),
(1, 't', 1571, 'Actual units', 'The number of actual units.'),
(1, 't', 1572, 'Actual units, cumulative to date', 'The number of cumulative to date actual units.'),
(1, 't', 1573, 'Earned value', 'Earned value quantity.'),
(1, 't', 1574, 'Earned value, cumulative to date', 'Earned value quantity accumulated to date.'),
(1, 't', 1575, 'At completion quantity, estimated', 'The estimated quantity when a project is complete.'),
(1, 't', 1576, 'To complete quantity, estimated', 'The estimated quantity required to complete a project.'),
(1, 't', 1577, 'Adjusted units', 'The number of adjusted units.'),
(1, 't', 1578, 'Number of limited partnership shares', 'Number of shares held in a limited partnership.'),
(1, 't', 1579, 'National business failure incidences', 'Number of firms in a country that discontinued with a loss to creditors.'),
(1, 't', 1580, 'Industry business failure incidences', 'Number of firms in a specific industry that discontinued with a loss to creditors.'),
(1, 't', 1581, 'Business class failure incidences', 'Number of firms in a specific class that discontinued with a loss to creditors.'),
(1, 't', 1582, 'Mechanics', 'Number of mechanics.'),
(1, 't', 1583, 'Messengers', 'Number of messengers.'),
(1, 't', 1584, 'Primary managers', 'Number of primary managers.'),
(1, 't', 1585, 'Secretaries', 'Number of secretaries.'),
(1, 't', 1586, 'Detrimental legal filings', 'Number of detrimental legal filings.'),
(1, 't', 1587, 'Branch office locations, estimated', 'Estimated number of branch office locations.'),
(1, 't', 1588, 'Previous number of employees', 'The number of employees for a previous period.'),
(1, 't', 1589, 'Asset seizers', 'Number of entities that seize assets of another entity.'),
(1, 't', 1590, 'Out-turned quantity', 'The quantity discharged.'),
(1, 't', 1591, 'Material on-board quantity, prior to loading', 'The material in vessel tanks, void spaces, and pipelines prior to loading.'),
(1, 't', 1592, 'Supplier estimated previous meter reading', 'Previous meter reading estimated by the supplier.'),
(1, 't', 1593, 'Supplier estimated latest meter reading',   'Latest meter reading estimated by the supplier.'),
(1, 't', 1594, 'Customer estimated previous meter reading', 'Previous meter reading estimated by the customer.'),
(1, 't', 1595, 'Customer estimated latest meter reading',   'Latest meter reading estimated by the customer.'),
(1, 't', 1596, 'Supplier previous meter reading',           'Previous meter reading done by the supplier.'),
(1, 't', 1597, 'Supplier latest meter reading',             'Latest meter reading recorded by the supplier.'),
(1, 't', 1598, 'Maximum number of purchase orders allowed', 'Maximum number of purchase orders that are allowed.'),
(1, 't', 1599, 'File size before compression', 'The size of a file before compression.'),
(1, 't', 1600, 'File size after compression', 'The size of a file after compression.'),
(1, 't', 1601, 'Securities shares', 'Number of shares of securities.'),
(1, 't', 1602, 'Patients',         'Number of patients.'),
(1, 't', 1603, 'Completed projects', 'Number of completed projects.'),
(1, 't', 1604, 'Promoters',        'Number of entities who finance or organize an event or a production.'),
(1, 't', 1605, 'Administrators',   'Number of administrators.'),
(1, 't', 1606, 'Supervisors',      'Number of supervisors.'),
(1, 't', 1607, 'Professionals',    'Number of professionals.'),
(1, 't', 1608, 'Debt collectors',  'Number of debt collectors.'),
(1, 't', 1609, 'Inspectors',       'Number of individuals who perform inspections.'),
(1, 't', 1610, 'Operators',        'Number of operators.'),
(1, 't', 1611, 'Trainers',         'Number of trainers.'),
(1, 't', 1612, 'Active accounts',  'Number of accounts in a current or active status.'),
(1, 't', 1613, 'Trademarks used',  'Number of trademarks used.'),
(1, 't', 1614, 'Machines',         'Number of machines.'),
(1, 't', 1615, 'Fuel pumps',       'Number of fuel pumps.'),
(1, 't', 1616, 'Tables available', 'Number of tables available for use.'),
(1, 't', 1617, 'Directors',        'Number of directors.'),
(1, 't', 1618, 'Freelance debt collectors', 'Number of debt collectors who work on a freelance basis.'),
(1, 't', 1619, 'Freelance salespersons',    'Number of salespersons who work on a freelance basis.'),
(1, 't', 1620, 'Travelling employees',      'Number of travelling employees.'),
(1, 't', 1621, 'Foremen', 'Number of workers with limited supervisory responsibilities.'),
(1, 't', 1622, 'Production workers', 'Number of employees engaged in production.'),
(1, 't', 1623, 'Employees not including owners', 'Number of employees excluding business owners.'),
(1, 't', 1624, 'Beds', 'Number of beds.'),
(1, 't', 1625, 'Resting quantity', 'A quantity of product that is at rest before it can be used.'),
(1, 't', 1626, 'Production requirements', 'Quantity needed to meet production requirements.'),
(1, 't', 1627, 'Corrected quantity', 'The quantity has been corrected.'),
(1, 't', 1628, 'Operating divisions', 'Number of divisions operating.'),
(1, 't', 1629, 'Quantitative incentive scheme base', 'Quantity constituting the base for the quantitative incentive scheme.'),
(1, 't', 1630, 'Petitions filed', 'Number of petitions that have been filed.'),
(1, 't', 1631, 'Bankruptcy petitions filed', 'Number of bankruptcy petitions that have been filed.'),
(1, 't', 1632, 'Projects in process', 'Number of projects in process.'),
(1, 't', 1633, 'Changes in capital structure', 'Number of modifications made to the capital structure of an entity.'),
(1, 't', 1634, 'Detrimental legal filings against directors', 'The number of legal filings that are of a detrimental nature that have been filed against the directors.'),
(1, 't', 1635, 'Number of failed businesses of directors', 'The number of failed businesses with which the directors have been associated.'),
(1, 't', 1636, 'Professor', 'The number of professors.'),
(1, 't', 1637, 'Seller',    'The number of sellers.'),
(1, 't', 1638, 'Skilled worker', 'The number of skilled workers.'),
(1, 't', 1639, 'Trademark represented', 'The number of trademarks represented.'),
(1, 't', 1640, 'Number of quantitative incentive scheme units', 'Number of units allocated to a quantitative incentive scheme.'),
(1, 't', 1641, 'Quantity in manufacturing process', 'Quantity currently in the manufacturing process.'),
(1, 't', 1642, 'Number of units in the width of a layer', 'Number of units which make up the width of a layer.'),
(1, 't', 1643, 'Number of units in the depth of a layer', 'Number of units which make up the depth of a layer.'),
(1, 't', 1644, 'Return to warehouse', 'A quantity of products sent back to the warehouse.'),
(1, 't', 1645, 'Return to the manufacturer', 'A quantity of products sent back from the manufacturer.'),
(1, 't', 1646, 'Delta quantity', 'An increment or decrement to a quantity.'),
(1, 't', 1647, 'Quantity moved between outlets', 'A quantity of products moved between outlets.'),
(1, 't', 1648, 'Pre-paid invoice annual consumption, estimated', 'The estimated annual consumption used for a prepayment invoice.'),
(1, 't', 1649, 'Total quoted quantity', 'The sum of quoted quantities.'),
(1, 't', 1650, 'Requests pertaining to entity in last 12 months', 'Number of requests received in last 12 months pertaining to the entity.'),
(1, 't', 1651, 'Total inquiry matches', 'Number of instances which correspond with the inquiry.'),
(1, 't', 1652, 'En route to warehouse quantity',   'A quantity of products that is en route to a warehouse.'),
(1, 't', 1653, 'En route from warehouse quantity', 'A quantity of products that is en route from a warehouse.'),
(1, 't', 1654, 'Quantity ordered but not yet allocated from stock', 'A quantity of products which has been ordered but which has not yet been allocated from stock.'),
(1, 't', 1655, 'Not yet ordered quantity', 'The quantity which has not yet been ordered.'),
(1, 't', 1656, 'Net reserve power', 'The reserve power available for the net.'),
(1, 't', 1657, 'Maximum number of units per shelf', 'Maximum number of units of a product that can be placed on a shelf.'),
(1, 't', 1658, 'Stowaway', 'Number of stowaway(s) on a conveyance.'),
(1, 't', 1659, 'Tug', 'The number of tugboat(s).'),
(1, 't', 1660, 'Maximum quantity capability of the package', 'Maximum quantity of a product that can be contained in a package.'),
(1, 't', 1661, 'Calculated', 'The calculated quantity.'),
(1, 't', 1662, 'Monthly volume, estimated', 'Volume estimated for a month.'),
(1, 't', 1663, 'Total number of persons', 'Quantity representing the total number of persons.'),
(1, 't', 1664, 'Tariff Quantity', 'Quantity of the goods in the unit as required by Customs for duty/tax/fee assessment. These quantities may also be used for other fiscal or statistical purposes.'),
(1, 't', 1665, 'Deducted tariff quantity',   'Quantity deducted from tariff quantity to reckon duty/tax/fee assessment bases.'),
(1, 't', 1666, 'Advised but not arrived',    'Goods are advised by the consignor or supplier, but have not yet arrived at the destination.'),
(1, 't', 1667, 'Received but not available', 'Goods have been received in the arrival area but are not yet available.'),
(1, 't', 1668, 'Goods blocked for transshipment process', 'Goods are physically present, but can not be ordered because they are scheduled for a transshipment process.'),
(1, 't', 1669, 'Goods blocked for cross docking process', 'Goods are physically present, but can not be ordered because they are scheduled for a cross docking process.'),
(1, 't', 1670, 'Chargeable number of trailers', 'The number of trailers on which charges are based.'),
(1, 't', 1671, 'Number of packages for a set', 'Number of packages used to pack the individual items in a grouping of merchandise that is sold together as a single trade item.'),
(1, 't', 1672, 'Number of items in a set', 'The number of individual items in a grouping of merchandise that is sold together as a single trade item.'),
(1, 't', 1673, 'Order sizing factor', 'A trade item specification other than gross, net weight, or volume for a trade item or a transaction, used for order sizing and pricing purposes.'),
(1, 't', 1674, 'Number of different next lower level trade items', 'Value indicates the number of differrent next lower level trade items contained in a complex trade item.'),
(1, 't', 1675, 'Agreed maximum buying quantity', 'The agreed maximum quantity of the trade item that may be purchased.'),
(1, 't', 1676, 'Agreed minimum buying quantity', 'The agreed minimum quantity of the trade item that may be purchased.'),
(1, 't', 1677, 'Free quantity of next lower level trade item', 'The numeric quantity of free items in a combination pack. The unit of measure used for the free quantity of the next lower level must be the same as the unit of measure of the Net Content of the Child Trade Item.'),
(1, 't', 1678, 'Marine Diesel Oil bunkers on board, on arrival',     'Number of Marine Diesel Oil (MDO) bunkers on board when the vessel arrives in the port.'),
(1, 't', 1679, 'Marine Diesel Oil bunkers, loaded',                  'Number of Marine Diesel Oil (MDO) bunkers taken on in the port.'),
(1, 't', 1680, 'Intermediate Fuel Oil bunkers on board, on arrival', 'Number of Intermediate Fuel Oil (IFO) bunkers on board when the vessel arrives in the port.'),
(1, 't', 1681, 'Intermediate Fuel Oil bunkers, loaded',              'Number of Intermediate Fuel Oil (IFO) bunkers taken on in the port.'),
(1, 't', 1682, 'Bunker C bunkers on board, on arrival',              'Number of Bunker C, or Number 6 fuel oil bunkers on board when the vessel arrives in the port.'),
(1, 't', 1683, 'Bunker C bunkers, loaded', 'Number of Bunker C, or Number 6 fuel oil bunkers, taken on in the port.'),
(1, 't', 1684, 'Number of individual units within the smallest packaging', 'unit Total number of individual units contained within the smallest unit of packaging.'),
(1, 't', 1685, 'Percentage of constituent element', 'The part of a product or material that is composed of the constituent element, as a percentage.'),
(1, 't', 1686, 'Quantity to be decremented (LPCO)', 'Quantity to be decremented from the allowable quantity on a License, Permit, Certificate, or Other document (LPCO).'),
(1, 't', 1687, 'Regulated commodity count', 'The number of regulated items.'),
(1, 't', 1688, 'Number of passengers, embarking', 'The number of passengers going aboard a conveyance.'),
(1, 't', 1689, 'Number of passengers, disembarking', 'The number of passengers disembarking the conveyance.'),
(1, 't', 1690, 'Constituent element or component quantity', 'The specific quantity of the identified constituent element.')
;
-- ZZZ, 'Mutually defined', 'As agreed by the trading partners.'),

CREATE TABLE acq.serial_claim (
    id     SERIAL           PRIMARY KEY,
    type   INT              NOT NULL REFERENCES acq.claim_type
                                     DEFERRABLE INITIALLY DEFERRED,
    item    BIGINT          NOT NULL REFERENCES serial.item
                                     DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX serial_claim_lid_idx ON acq.serial_claim( item );

CREATE TABLE acq.serial_claim_event (
    id             BIGSERIAL        PRIMARY KEY,
    type           INT              NOT NULL REFERENCES acq.claim_event_type
                                             DEFERRABLE INITIALLY DEFERRED,
    claim          SERIAL           NOT NULL REFERENCES acq.serial_claim
                                             DEFERRABLE INITIALLY DEFERRED,
    event_date     TIMESTAMPTZ      NOT NULL DEFAULT now(),
    creator        INT              NOT NULL REFERENCES actor.usr
                                             DEFERRABLE INITIALLY DEFERRED,
    note           TEXT
);

CREATE INDEX serial_claim_event_claim_date_idx ON acq.serial_claim_event( claim, event_date );

ALTER TABLE asset.stat_cat ADD COLUMN required BOOL NOT NULL DEFAULT FALSE;

-- now what about the auditor.*_lifecycle views??

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath ) VALUES
    (26, 'identifier', 'tcn', oils_i18n_gettext(26, 'Title Control Number', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='901']/marc:subfield[@code='a']$$ );
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath ) VALUES
    (27, 'identifier', 'bibid', oils_i18n_gettext(27, 'Internal ID', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='901']/marc:subfield[@code='c']$$ );
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.tcn','identifier', 26);
INSERT INTO config.metabib_search_alias (alias,field_class,field) VALUES ('eg.bibid','identifier', 27);

CREATE TABLE asset.call_number_class (
    id             bigserial     PRIMARY KEY,
    name           TEXT          NOT NULL,
    normalizer     TEXT          NOT NULL DEFAULT 'asset.normalize_generic',
    field          TEXT          NOT NULL DEFAULT '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099'
);

COMMENT ON TABLE asset.call_number_class IS $$
Defines the call number normalization database functions in the "normalizer"
column and the tag/subfield combinations to use to lookup the call number in
the "field" column for a given classification scheme. Tag/subfield combinations
are delimited by commas.
$$;

INSERT INTO asset.call_number_class (name, normalizer) VALUES 
    ('Generic', 'asset.label_normalizer_generic'),
    ('Dewey (DDC)', 'asset.label_normalizer_dewey'),
    ('Library of Congress (LC)', 'asset.label_normalizer_lc')
;

-- Generic fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099'
    WHERE id = 1
;

-- Dewey fields
UPDATE asset.call_number_class
    SET field = '080ab,082ab'
    WHERE id = 2
;

-- LC fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab'
    WHERE id = 3
;
 
ALTER TABLE asset.call_number
	ADD COLUMN label_class BIGINT DEFAULT 1 NOT NULL
		REFERENCES asset.call_number_class(id)
		DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE asset.call_number
	ADD COLUMN label_sortkey TEXT;

CREATE INDEX asset_call_number_label_sortkey
	ON asset.call_number(oils_text_as_bytea(label_sortkey));

ALTER TABLE auditor.asset_call_number_history
	ADD COLUMN label_class BIGINT;

ALTER TABLE auditor.asset_call_number_history
	ADD COLUMN label_sortkey TEXT;

-- Pick up the new columns in dependent views

DROP VIEW auditor.asset_call_number_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'asset', 'call_number' );

DROP VIEW auditor.asset_call_number_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'asset', 'call_number' );

DROP VIEW IF EXISTS stats.fleshed_call_number;

CREATE VIEW stats.fleshed_call_number AS
        SELECT  cn.*,
            CAST(cn.create_date AS DATE) AS create_date_day,
        CAST(cn.edit_date AS DATE) AS edit_date_day,
        DATE_TRUNC('hour', cn.create_date) AS create_date_hour,
        DATE_TRUNC('hour', cn.edit_date) AS edit_date_hour,
            rd.item_lang,
                rd.item_type,
                rd.item_form
        FROM    asset.call_number cn
                JOIN metabib.rec_descriptor rd ON (rd.record = cn.record);

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    EXECUTE 'SELECT ' || acnc.normalizer || '(' || 
       quote_literal( NEW.label ) || ')'
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;

    NEW.label_sortkey = sortkey;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.label_normalizer_generic(TEXT) RETURNS TEXT AS $func$
    # Created after looking at the Koha C4::ClassSortRoutine::Generic module,
    # thus could probably be considered a derived work, although nothing was
    # directly copied - but to err on the safe side of providing attribution:
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    # Converts the callnumber to uppercase
    # Strips spaces from start and end of the call number
    # Converts anything other than letters, digits, and periods into underscores
    # Collapses multiple underscores into a single underscore
    my $callnum = uc(shift);
    $callnum =~ s/^\s//g;
    $callnum =~ s/\s$//g;
    $callnum =~ s/[^A-Z0-9_.]/_/g;
    $callnum =~ s/_{2,}/_/g;

    return $callnum;
$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION asset.label_normalizer_dewey(TEXT) RETURNS TEXT AS $func$
    # Derived from the Koha C4::ClassSortRoutine::Dewey module
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    my $init = uc(shift);
    $init =~ s/^\s+//;
    $init =~ s/\s+$//;
    $init =~ s!/!!g;
    $init =~ s/^([\p{IsAlpha}]+)/$1 /;
    my @tokens = split /\.|\s+/, $init;
    my $digit_group_count = 0;
    for (my $i = 0; $i <= $#tokens; $i++) {
        if ($tokens[$i] =~ /^\d+$/) {
            $digit_group_count++;
            if (2 == $digit_group_count) {
                $tokens[$i] = sprintf("%-15.15s", $tokens[$i]);
                $tokens[$i] =~ tr/ /0/;
            }
        }
    }
    my $key = join("_", @tokens);
    $key =~ s/[^\p{IsAlnum}_]//g;

    return $key;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION asset.label_normalizer_lc(TEXT) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    # Library::CallNumber::LC is currently hosted at http://code.google.com/p/library-callnumber-lc/
    # The author hopes to upload it to CPAN some day, which would make our lives easier
    use Library::CallNumber::LC;

    my $callnum = Library::CallNumber::LC->new(shift);
    return $callnum->normalize();

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION asset.opac_ou_record_copy_count (org INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = record AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = record AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count (org INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id)
                JOIN asset.call_number cn ON (cn.record = record AND cn.id = cp.call_number)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id)
                JOIN asset.call_number cn ON (cn.record = record AND cn.id = cp.call_number)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.record_copy_count ( place INT, record BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_record_copy_count( place, record );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_record_copy_count( -place, record );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_record_copy_count( place, record );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_record_copy_count( -place, record );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_ou_metarecord_copy_count (org INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = record AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
                JOIN metabib.metarecord_source_map m ON (m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( av.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.opac_visible_copies av ON (av.record = record AND av.circ_lib = d.id)
                JOIN asset.copy cp ON (cp.id = av.id)
                JOIN metabib.metarecord_source_map m ON (m.source = av.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id)
                JOIN asset.call_number cn ON (cn.record = record AND cn.id = cp.call_number)
                JOIN metabib.metarecord_source_map m ON (m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, record BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = record;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id)
                JOIN asset.call_number cn ON (cn.record = record AND cn.id = cp.call_number)
                JOIN metabib.metarecord_source_map m ON (m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.metarecord_copy_count ( place INT, record BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_metarecord_copy_count( place, record );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_metarecord_copy_count( -place, record );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_metarecord_copy_count( place, record );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_metarecord_copy_count( -place, record );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

-- No transaction is required

-- Triggers on the vandelay.queued_*_record tables delete entries from
-- the associated vandelay.queued_*_record_attr tables based on the record's
-- ID; create an index on that column to avoid sequential scans for each
-- queued record that is deleted
CREATE INDEX queued_bib_record_attr_record_idx ON vandelay.queued_bib_record_attr (record);
CREATE INDEX queued_authority_record_attr_record_idx ON vandelay.queued_authority_record_attr (record);

-- Avoid sequential scans for queue retrieval operations by providing an
-- index on the queue column
CREATE INDEX queued_bib_record_queue_idx ON vandelay.queued_bib_record (queue);
CREATE INDEX queued_authority_record_queue_idx ON vandelay.queued_authority_record (queue);

-- Start picking up call number label prefixes and suffixes
-- from asset.copy_location
ALTER TABLE asset.copy_location ADD COLUMN label_prefix TEXT;
ALTER TABLE asset.copy_location ADD COLUMN label_suffix TEXT;

DROP VIEW auditor.asset_copy_lifecycle;

SELECT auditor.create_auditor_lifecycle( 'asset', 'copy' );

ALTER TABLE reporter.report RENAME COLUMN recurance TO recurrence;

-- Let's not break existing reports
UPDATE reporter.template SET data = REGEXP_REPLACE(data, E'^(.*)recuring(.*)$', E'\\1recurring\\2') WHERE data LIKE '%recuring%';
UPDATE reporter.template SET data = REGEXP_REPLACE(data, E'^(.*)recurance(.*)$', E'\\1recurrence\\2') WHERE data LIKE '%recurance%';

-- Need to recreate this view with DISTINCT calls to ARRAY_ACCUM, thus avoiding duplicated ISBN and ISSN values
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
    ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
    ARRAY_ACCUM( DISTINCT SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

-- Correct the ISSN array definition for reporter.simple_record

CREATE OR REPLACE VIEW reporter.simple_record AS
SELECT	r.id,
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
	ARRAY_ACCUM( SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
	ARRAY_ACCUM( REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) AS issn,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '650' AND subfield = 'a' AND record = r.id)) AS topic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '651' AND subfield = 'a' AND record = r.id)) AS geographic_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '655' AND subfield = 'a' AND record = r.id)) AS genre,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '600' AND subfield = 'a' AND record = r.id)) AS name_subject,
	ARRAY((SELECT DISTINCT value FROM metabib.full_rec WHERE tag = '610' AND subfield = 'a' AND record = r.id)) AS corporate_subject,
	ARRAY((SELECT value FROM metabib.full_rec WHERE tag = '856' AND subfield IN ('3','y','u') AND record = r.id ORDER BY CASE WHEN subfield IN ('3','y') THEN 0 ELSE 1 END)) AS external_uri
  FROM	biblio.record_entry r
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

CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER IF EXISTS bbb_simple_rec_trigger ON biblio.record_entry;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    DELETE FROM reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER bbb_simple_rec_trigger
        AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger();

$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.simple_rec_trigger () RETURNS TRIGGER AS $func$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM reporter.simple_rec_delete(NEW.id);
    ELSE
        PERFORM reporter.simple_rec_update(NEW.id);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER bbb_simple_rec_trigger AFTER INSERT OR UPDATE OR DELETE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_trigger ();

ALTER TABLE extend_reporter.legacy_circ_count DROP CONSTRAINT legacy_circ_count_id_fkey;

CREATE INDEX asset_copy_note_owning_copy_idx ON asset.copy_note ( owning_copy );

UPDATE config.org_unit_setting_type
    SET view_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'VIEW_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor%' AND view_perm IS NULL;

UPDATE config.org_unit_setting_type
    SET update_perm = (SELECT id FROM permission.perm_list
        WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING' LIMIT 1)
    WHERE name LIKE 'credit.processor%' AND update_perm IS NULL;

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES (
        'opac.fully_compressed_serial_holdings',
        'OPAC: Use fully compressed serial holdings',
        'Show fully compressed serial holdings for all libraries at and below
        the current context unit',
        'bool'
    );

CREATE OR REPLACE FUNCTION authority.normalize_heading( TEXT ) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    use utf8;
    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF8');
    use UUID::Tiny ':std';

    my $xml = shift() or return undef;

    my $r;

    # Prevent errors in XML parsing from blowing out ungracefully
    eval {
        $r = MARC::Record->new_from_xml( $xml );
        1;
    } or do {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    };

    if (!$r) {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    }

    # From http://www.loc.gov/standards/sourcelist/subject.html
    my $thes_code_map = {
        a => 'lcsh',
        b => 'lcshac',
        c => 'mesh',
        d => 'nal',
        k => 'cash',
        n => 'notapplicable',
        r => 'aat',
        s => 'sears',
        v => 'rvm',
    };

    # Default to "No attempt to code" if the leader is horribly broken
    my $fixed_field = $r->field('008');
    my $thes_char = '|';
    if ($fixed_field) { 
        $thes_char = substr($fixed_field->data(), 11, 1) || '|';
    }

    my $thes_code = 'UNDEFINED';

    if ($thes_char eq 'z') {
        # Grab the 040 $f per http://www.loc.gov/marc/authority/ad040.html
        $thes_code = $r->subfield('040', 'f') || 'UNDEFINED';
    } elsif ($thes_code_map->{$thes_char}) {
        $thes_code = $thes_code_map->{$thes_char};
    }

    my $auth_txt = '';
    my $head = $r->field('1..');
    if ($head) {
        # Concatenate all of these subfields together, prefixed by their code
        # to prevent collisions along the lines of "Fiction, North Carolina"
        foreach my $sf ($head->subfields()) {
            $auth_txt .= '‡' . $sf->[0] . ' ' . $sf->[1];
        }
    }
    
    if ($auth_txt) {
        my $stmt = spi_prepare('SELECT public.naco_normalize($1) AS norm_text', 'TEXT');
        my $result = spi_exec_prepared($stmt, $auth_txt);
        my $norm_txt = $result->{rows}[0]->{norm_text};
        spi_freeplan($stmt);
        undef($stmt);
        return $head->tag() . "_" . $thes_code . " " . $norm_txt;
    }

    return 'NOHEADING_' . $thes_code . ' ' . create_uuid_as_string(UUID_MD5, $xml);
$func$ LANGUAGE 'plperlu' IMMUTABLE;

COMMENT ON FUNCTION authority.normalize_heading( TEXT ) IS $$
/**
* Extract the authority heading, thesaurus, and NACO-normalized values
* from an authority record. The primary purpose is to build a unique
* index to defend against duplicated authority records from the same
* thesaurus.
*/
$$;

DROP INDEX authority.authority_record_unique_tcn;
ALTER TABLE authority.record_entry DROP COLUMN arn_value;
ALTER TABLE authority.record_entry DROP COLUMN arn_source;

ALTER TABLE acq.provider_contact
	ALTER COLUMN name SET NOT NULL;

ALTER TABLE actor.stat_cat
	ADD COLUMN usr_summary BOOL NOT NULL DEFAULT FALSE;

-- Per Robert Soulliere, it can be necessary in some cases to clean out bad
-- data from action.reservation_transit_copy before applying the missing
-- fkeys below.
-- https://bugs.launchpad.net/evergreen/+bug/721450
DELETE FROM action.reservation_transit_copy
    WHERE target_copy NOT IN (SELECT id FROM booking.resource);
-- In the same spirit as the above delete, this can only fix bad data.
UPDATE action.reservation_transit_copy
    SET reservation = NULL
    WHERE reservation NOT IN (SELECT id FROM booking.reservation);

-- Recreate some foreign keys that were somehow dropped, probably
-- by some kind of cascade from an inherited table:

ALTER TABLE action.reservation_transit_copy
	ADD CONSTRAINT artc_tc_fkey FOREIGN KEY (target_copy)
		REFERENCES booking.resource(id)
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED,
	ADD CONSTRAINT reservation_transit_copy_reservation_fkey FOREIGN KEY (reservation)
		REFERENCES booking.reservation(id)
		ON DELETE SET NULL
		DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX user_bucket_item_target_user_idx
	ON container.user_bucket_item ( target_user );

CREATE INDEX m_c_t_collector_idx
	ON money.collections_tracker ( collector );

CREATE INDEX aud_actor_usr_address_hist_id_idx
	ON auditor.actor_usr_address_history ( id );

CREATE INDEX aud_actor_usr_hist_id_idx
	ON auditor.actor_usr_history ( id );

CREATE INDEX aud_asset_cn_hist_creator_idx
	ON auditor.asset_call_number_history ( creator );

CREATE INDEX aud_asset_cn_hist_editor_idx
	ON auditor.asset_call_number_history ( editor );

CREATE INDEX aud_asset_cp_hist_creator_idx
	ON auditor.asset_copy_history ( creator );

CREATE INDEX aud_asset_cp_hist_editor_idx
	ON auditor.asset_copy_history ( editor );

CREATE INDEX aud_bib_rec_entry_hist_creator_idx
	ON auditor.biblio_record_entry_history ( creator );

CREATE INDEX aud_bib_rec_entry_hist_editor_idx
	ON auditor.biblio_record_entry_history ( editor );

CREATE TABLE action.hold_request_note (

    id     BIGSERIAL PRIMARY KEY,
    hold   BIGINT    NOT NULL REFERENCES action.hold_request (id)
                              ON DELETE CASCADE
                              DEFERRABLE INITIALLY DEFERRED,
    title  TEXT      NOT NULL,
    body   TEXT      NOT NULL,
    slip   BOOL      NOT NULL DEFAULT FALSE,
    pub    BOOL      NOT NULL DEFAULT FALSE,
    staff  BOOL      NOT NULL DEFAULT FALSE  -- created by staff

);
CREATE INDEX ahrn_hold_idx ON action.hold_request_note (hold);

-- Tweak a constraint to add a CASCADE

ALTER TABLE action.hold_notification DROP CONSTRAINT hold_notification_hold_fkey;

ALTER TABLE action.hold_notification
	ADD CONSTRAINT hold_notification_hold_fkey
		FOREIGN KEY (hold) REFERENCES action.hold_request (id)
		ON DELETE CASCADE
		DEFERRABLE INITIALLY DEFERRED;

CREATE TRIGGER asset_label_sortkey_trigger
    BEFORE UPDATE OR INSERT ON asset.call_number
    FOR EACH ROW EXECUTE PROCEDURE asset.label_normalizer();

CREATE OR REPLACE FUNCTION container.clear_all_expired_circ_history_items( )
RETURNS VOID AS $$
--
-- Delete expired circulation bucket items for all users that have
-- a setting for patron.max_reading_list_interval.
--
DECLARE
    today        TIMESTAMP WITH TIME ZONE;
    threshold    TIMESTAMP WITH TIME ZONE;
	usr_setting  RECORD;
BEGIN
	SELECT date_trunc( 'day', now() ) INTO today;
	--
	FOR usr_setting in
		SELECT
			usr,
			value
		FROM
			actor.usr_setting
		WHERE
			name = 'patron.max_reading_list_interval'
	LOOP
		--
		-- Make sure the setting is a valid interval
		--
		BEGIN
			threshold := today - CAST( translate( usr_setting.value, '"', '' ) AS INTERVAL );
		EXCEPTION
			WHEN OTHERS THEN
				RAISE NOTICE 'Invalid setting patron.max_reading_list_interval for user %: ''%''',
					usr_setting.usr, usr_setting.value;
				CONTINUE;
		END;
		--
		--RAISE NOTICE 'User % threshold %', usr_setting.usr, threshold;
		--
    	DELETE FROM container.copy_bucket_item
    	WHERE
        	bucket IN
        	(
        	    SELECT
        	        id
        	    FROM
        	        container.copy_bucket
        	    WHERE
        	        owner = usr_setting.usr
        	        AND btype = 'circ_history'
        	)
        	AND create_time < threshold;
	END LOOP;
	--
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION container.clear_all_expired_circ_history_items( ) IS $$
/*
 * Delete expired circulation bucket items for all users that have
 * a setting for patron.max_reading_list_interval.
*/
$$;

CREATE OR REPLACE FUNCTION container.clear_expired_circ_history_items( 
	 ac_usr IN INTEGER
) RETURNS VOID AS $$
--
-- Delete old circulation bucket items for a specified user.
-- "Old" means older than the interval specified by a
-- user-level setting, if it is so specified.
--
DECLARE
    threshold TIMESTAMP WITH TIME ZONE;
BEGIN
	-- Sanity check
	IF ac_usr IS NULL THEN
		RETURN;
	END IF;
	-- Determine the threshold date that defines "old".  Subtract the
	-- interval from the system date, then truncate to midnight.
	SELECT
		date_trunc( 
			'day',
			now() - CAST( translate( value, '"', '' ) AS INTERVAL )
		)
	INTO
		threshold
	FROM
		actor.usr_setting
	WHERE
		usr = ac_usr
		AND name = 'patron.max_reading_list_interval';
	--
	IF threshold is null THEN
		-- No interval defined; don't delete anything
		-- RAISE NOTICE 'No interval defined for user %', ac_usr;
		return;
	END IF;
	--
	-- RAISE NOTICE 'Date threshold: %', threshold;
	--
	-- Threshold found; do the delete
	delete from container.copy_bucket_item
	where
		bucket in
		(
			select
				id
			from
				container.copy_bucket
			where
				owner = ac_usr
				and btype = 'circ_history'
		)
		and create_time < threshold;
	--
	RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION container.clear_expired_circ_history_items( INTEGER ) IS $$
/*
 * Delete old circulation bucket items for a specified user.
 * "Old" means older than the interval specified by a
 * user-level setting, if it is so specified.
*/
$$;

CREATE OR REPLACE VIEW reporter.hold_request_record AS
SELECT  id,
    target,
    hold_type,
    CASE
        WHEN hold_type = 'T'
            THEN target
        WHEN hold_type = 'I'
            THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = ahr.target)
        WHEN hold_type = 'V'
            THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = ahr.target)
        WHEN hold_type IN ('C','R','F')
            THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = ahr.target)
        WHEN hold_type = 'M'
            THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = ahr.target)
    END AS bib_record
  FROM  action.hold_request ahr;

UPDATE  metabib.rec_descriptor
  SET   date1=LPAD(NULLIF(REGEXP_REPLACE(NULLIF(date1, ''), E'\\D', '0', 'g')::INT,0)::TEXT,4,'0'),
        date2=LPAD(NULLIF(REGEXP_REPLACE(NULLIF(date2, ''), E'\\D', '9', 'g')::INT,9999)::TEXT,4,'0');

-- Change some ints to bigints:

ALTER TABLE container.biblio_record_entry_bucket_item
	ALTER COLUMN target_biblio_record_entry SET DATA TYPE bigint;

ALTER TABLE vandelay.queued_bib_record
	ALTER COLUMN imported_as SET DATA TYPE bigint;

ALTER TABLE action.hold_copy_map
	ALTER COLUMN id SET DATA TYPE bigint;

-- Make due times get pushed to 23:59:59 on insert OR update
DROP TRIGGER IF EXISTS push_due_date_tgr ON action.circulation;
CREATE TRIGGER push_due_date_tgr BEFORE INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove )
SELECT 'upc', 'UPC', '//*[@tag="024" and @ind1="1"]/*[@code="a"]', $r$(?:-|\s.+$)$r$
WHERE NOT EXISTS (
    SELECT 1 FROM acq.lineitem_marc_attr_definition WHERE code = 'upc'
);  

-- '@@' auto-placeholder barcode support
CREATE OR REPLACE FUNCTION asset.autogenerate_placeholder_barcode ( ) RETURNS TRIGGER AS $f$
BEGIN
	IF NEW.barcode LIKE '@@%' THEN
		NEW.barcode := '@@' || NEW.id;
	END IF;
	RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER autogenerate_placeholder_barcode
	BEFORE INSERT OR UPDATE ON asset.copy
	FOR EACH ROW EXECUTE PROCEDURE asset.autogenerate_placeholder_barcode();

COMMIT;

-- Some operations go outside of the transaction, because they may
-- legitimately fail.

\qecho ALTERs of auditor.action_hold_request_history will fail if the table
\qecho doesn't exist; ignore those errors if they occur.

ALTER TABLE auditor.action_hold_request_history ADD COLUMN cut_in_line BOOL;

ALTER TABLE auditor.action_hold_request_history
ADD COLUMN mint_condition boolean NOT NULL DEFAULT TRUE;

ALTER TABLE auditor.action_hold_request_history
ADD COLUMN shelf_expire_time TIMESTAMPTZ;

\qecho Outside of the transaction: adding indexes that may or may not exist.
\qecho If any of these CREATE INDEX statements fails because the index already
\qecho exists, ignore the failure.

CREATE INDEX acq_picklist_owner_idx   ON acq.picklist ( owner );
CREATE INDEX acq_picklist_creator_idx ON acq.picklist ( creator );
CREATE INDEX acq_picklist_editor_idx  ON acq.picklist ( editor );
CREATE INDEX acq_po_note_creator_idx  ON acq.po_note ( creator );
CREATE INDEX acq_po_note_editor_idx   ON acq.po_note ( editor );
CREATE INDEX fund_alloc_allocator_idx ON acq.fund_allocation ( allocator );
CREATE INDEX li_creator_idx   ON acq.lineitem ( creator );
CREATE INDEX li_editor_idx    ON acq.lineitem ( editor );
CREATE INDEX li_selector_idx  ON acq.lineitem ( selector );
CREATE INDEX li_note_creator_idx  ON acq.lineitem_note ( creator );
CREATE INDEX li_note_editor_idx   ON acq.lineitem_note ( editor );
CREATE INDEX li_usr_attr_def_usr_idx  ON acq.lineitem_usr_attr_definition ( usr );
CREATE INDEX po_editor_idx   ON acq.purchase_order ( editor );
CREATE INDEX po_creator_idx  ON acq.purchase_order ( creator );
CREATE INDEX acq_po_org_name_order_date_idx ON acq.purchase_order( ordering_agency, name, order_date );
CREATE INDEX action_in_house_use_staff_idx  ON action.in_house_use ( staff );
CREATE INDEX action_non_cat_circ_patron_idx ON action.non_cataloged_circulation ( patron );
CREATE INDEX action_non_cat_circ_staff_idx  ON action.non_cataloged_circulation ( staff );
CREATE INDEX action_survey_response_usr_idx ON action.survey_response ( usr );
CREATE INDEX ahn_notify_staff_idx           ON action.hold_notification ( notify_staff );
CREATE INDEX circ_all_usr_idx               ON action.circulation ( usr );
CREATE INDEX circ_circ_staff_idx            ON action.circulation ( circ_staff );
CREATE INDEX circ_checkin_staff_idx         ON action.circulation ( checkin_staff );
CREATE INDEX hold_request_fulfillment_staff_idx ON action.hold_request ( fulfillment_staff );
CREATE INDEX hold_request_requestor_idx     ON action.hold_request ( requestor );
CREATE INDEX non_cat_in_house_use_staff_idx ON action.non_cat_in_house_use ( staff );
CREATE INDEX actor_usr_note_creator_idx     ON actor.usr_note ( creator );
CREATE INDEX actor_usr_standing_penalty_staff_idx ON actor.usr_standing_penalty ( staff );
CREATE INDEX usr_org_unit_opt_in_staff_idx  ON actor.usr_org_unit_opt_in ( staff );
CREATE INDEX asset_call_number_note_creator_idx ON asset.call_number_note ( creator );
CREATE INDEX asset_copy_note_creator_idx    ON asset.copy_note ( creator );
CREATE INDEX cp_creator_idx                 ON asset.copy ( creator );
CREATE INDEX cp_editor_idx                  ON asset.copy ( editor );

CREATE INDEX actor_card_barcode_lower_idx ON actor.card (lower(barcode));

DROP INDEX IF EXISTS authority.unique_by_heading_and_thesaurus;

\qecho If the following CREATE INDEX fails, It will be necessary to do some
\qecho data cleanup as described in the comments.

CREATE UNIQUE INDEX unique_by_heading_and_thesaurus
    ON authority.record_entry (authority.normalize_heading(marc))
	WHERE deleted IS FALSE or deleted = FALSE;

-- If the unique index fails, uncomment the following to create
-- a regular index that will help find the duplicates in a hurry:
--CREATE INDEX by_heading_and_thesaurus
--    ON authority.record_entry (authority.normalize_heading(marc))
--    WHERE deleted IS FALSE or deleted = FALSE
--;

-- Then find the duplicates like so to get an idea of how much
-- pain you're looking at to clean things up:
--SELECT id, authority.normalize_heading(marc)
--    FROM authority.record_entry
--    WHERE authority.normalize_heading(marc) IN (
--        SELECT authority.normalize_heading(marc)
--        FROM authority.record_entry
--        GROUP BY authority.normalize_heading(marc)
--        HAVING COUNT(*) > 1
--    )
--;

-- Once you have removed the duplicates and the CREATE UNIQUE INDEX
-- statement succeeds, drop the temporary index to avoid unnecessary
-- duplication:
-- DROP INDEX authority.by_heading_and_thesaurus;

-- 0448.data.trigger.circ.staff_age_to_lost.sql

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES 
    (   'circ.staff_age_to_lost',
        'circ', 
        oils_i18n_gettext(
            'circ.staff_age_to_lost',
            'An overdue circulation should be aged to a Lost status.',
            'ath',
            'description'
        ), 
        TRUE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        delay_field
    ) VALUES (
        36,
        FALSE,
        1,
        'circ.staff_age_to_lost',
        'circ.staff_age_to_lost',
        'CircIsOverdue',
        'MarkItemLost',
        'due_date'
    )
;

-- Speed up item-age browse axis (new books feed)
CREATE INDEX cp_create_date  ON asset.copy (create_date);

-- Speed up call number browsing
CREATE INDEX asset_call_number_label_sortkey_browse ON asset.call_number(oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib) WHERE deleted IS FALSE OR deleted = FALSE;

\qecho Upgrade script completed.
\qecho But wait, there's more: please run reingest-1.6-2.0.pl
\qecho in order to create an SQL script to run to partially reindex 
\qecho the bib records; this is required to make the new facet
\qecho sidebar in OPAC search results work and to upgrade the keyword 
\qecho indexes to use the revised NACO normalization routine.
