BEGIN;

SELECT evergreen.upgrade_deps_block_check('1021', :eg_version);

-- Add missing permissions noted in LP 1517137 adjusting those added manually and ignoring those already in place.

DO $$
DECLARE fixperm TEXT[3];
DECLARE modify BOOLEAN;
DECLARE permid BIGINT;
DECLARE oldid BIGINT;
BEGIN

FOREACH fixperm SLICE 1 IN ARRAY ARRAY[
  ['564', 'MARK_ITEM_CATALOGING', 'Allow a user to mark an item status as ''cataloging'''],
  ['565', 'MARK_ITEM_DAMAGED', 'Allow a user to mark an item status as ''damaged'''],
  ['566', 'MARK_ITEM_DISCARD', 'Allow a user to mark an item status as ''discard'''],
  ['567', 'MARK_ITEM_RESERVES', 'Allow a user to mark an item status as ''reserves'''],
  ['568', 'ADMIN_ORG_UNIT_SETTING_TYPE_LOG', 'Allow a user to modify the org unit settings log'],
  ['570', 'CREATE_POP_BADGE', 'Allow a user to create a new popularity badge'],
  ['571', 'DELETE_POP_BADGE', 'Allow a user to delete a popularity badge'],
  ['572', 'UPDATE_POP_BADGE', 'Allow a user to modify a popularity badge'],
  ['573', 'CREATE_POP_PARAMETER', 'Allow a user to create a popularity badge parameter'],
  ['574', 'DELETE_POP_PARAMETER', 'Allow a user to delete a popularity badge parameter'],
  ['575', 'UPDATE_POP_PARAMETER', 'Allow a user to modify a popularity badge parameter'],
  ['576', 'CREATE_AUTHORITY_RECORD', 'Allow a user to create an authority record'],
  ['577', 'DELETE_AUTHORITY_RECORD', 'Allow a user to delete an authority record'],
  ['578', 'UPDATE_AUTHORITY_RECORD', 'Allow a user to modify an authority record'],
  ['579', 'CREATE_AUTHORITY_CONTROL_SET', 'Allow a user to create an authority control set'],
  ['580', 'DELETE_AUTHORITY_CONTROL_SET', 'Allow a user to delete an authority control set'],
  ['581', 'UPDATE_AUTHORITY_CONTROL_SET', 'Allow a user to modify an authority control set'],
  ['582', 'ACTOR_USER_DELETE_OPEN_XACTS.override', 'Override the ACTOR_USER_DELETE_OPEN_XACTS event'],
  ['583', 'PATRON_EXCEEDS_LOST_COUNT.override', 'Override the PATRON_EXCEEDS_LOST_COUNT event'],
  ['584', 'MAX_HOLDS.override', 'Override the MAX_HOLDS event'],
  ['585', 'ITEM_DEPOSIT_REQUIRED.override', 'Override the ITEM_DEPOSIT_REQUIRED event'],
  ['586', 'ITEM_DEPOSIT_PAID.override', 'Override the ITEM_DEPOSIT_PAID event'],
  ['587', 'COPY_STATUS_LOST_AND_PAID.override', 'Override the COPY_STATUS_LOST_AND_PAID event'],
  ['588', 'ITEM_NOT_HOLDABLE.override', 'Override the ITEM_NOT_HOLDABLE event'],
  ['589', 'ITEM_RENTAL_FEE_REQUIRED.override', 'Override the ITEM_RENTAL_FEE_REQUIRED event']
]
LOOP
  permid := CAST (fixperm[1] AS BIGINT);
  -- Has this permission already been manually applied at the expected id?
  PERFORM * FROM permission.perm_list WHERE id = permid;
  IF NOT FOUND THEN
    UPDATE permission.perm_list SET code = code || '_local' WHERE code = fixperm[2] AND id > 1000 RETURNING id INTO oldid;
    modify := FOUND;

    INSERT INTO permission.perm_list (id, code, description) VALUES (permid, fixperm[2], fixperm[3]);

    -- Several of these are rather unlikely for these particular permissions but safer > sorry.
    IF modify THEN
      UPDATE permission.grp_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE config.org_unit_setting_type SET update_perm = permid WHERE update_perm = oldid;
      UPDATE permission.usr_object_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE permission.usr_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE config.org_unit_setting_type SET view_perm = permid WHERE view_perm = oldid;
      UPDATE config.z3950_source SET use_perm = permid WHERE use_perm = oldid;
      DELETE FROM permission.perm_list WHERE id = oldid;
    END IF;
  END IF;
END LOOP;

END$$;

COMMIT;
