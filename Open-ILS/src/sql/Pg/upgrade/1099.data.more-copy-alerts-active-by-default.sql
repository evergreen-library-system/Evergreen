BEGIN;

SELECT evergreen.upgrade_deps_block_check('1099', :eg_version);

\qecho Making the following copy alert types active by default; if you
\qecho are not using the web staff client yet, you may want to disable
\qecho them.
\qecho  - Checkin of lost, missing, lost-and-paid, damaged, claims returned,
\qecho    long overdue, and claims never checked out items.
\qecho  - Checkout of lost, missing, lost-and-paid, damaged, claims returned,
\qecho    long overdue, and claims never checked out items.

UPDATE config.copy_alert_type
SET active = TRUE
WHERE id IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17);

COMMIT;
