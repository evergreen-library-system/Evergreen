BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0585', :eg_version);

INSERT into config.org_unit_setting_type
( name, label, description, datatype ) VALUES
( 'circ.checkout_fills_related_hold_exact_match_only',
    'Checkout Fills Related Hold On Valid Copy Only',
    'When filling related holds on checkout only match on items that are valid for opportunistic capture for the hold. Without this set a Title or Volume hold could match when the item is not holdable. With this set only holdable items will match.',
    'bool');

COMMIT;
