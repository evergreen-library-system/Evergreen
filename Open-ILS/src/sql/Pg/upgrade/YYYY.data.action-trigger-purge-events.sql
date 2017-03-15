BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('1XXX', :eg_version);

UPDATE action_trigger.hook SET passive = FALSE WHERE key IN (
    'format.po.html',
    'format.po.pdf',
    'format.selfcheck.checkout',
    'format.selfcheck.items_out',
    'format.selfcheck.holds',
    'format.selfcheck.fines',
    'format.acqcle.html',
    'format.acqinv.html',
    'format.acqli.html',
    'aur.ordered',
    'aur.received',
    'aur.cancelled',
    'aur.created',
    'aur.rejected'
);

COMMIT;
