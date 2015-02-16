BEGIN;

SELECT evergreen.upgrade_deps_block_check('0907', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype ) VALUES

( 'circ.checkin.lost_zero_balance.do_not_change',
  'circ',
  'Do not change fines/fees on zero-balance LOST transaction',
  'When an item has been marked lost and all fines/fees have been completely paid on the transaction, do not void or reinstate any fines/fees EVEN IF circ.void_lost_on_checkin and/or circ.void_lost_proc_fee_on_checkin are enabled',
  'bool');

COMMIT;

