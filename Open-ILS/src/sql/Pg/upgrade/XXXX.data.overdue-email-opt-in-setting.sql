BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.usr_setting_type (
    name,
    opac_visible,
    label,
    description,
    grp,
    datatype,
    reg_default
) VALUES (
    'circ.default_overdue_notices_enabled',
    TRUE,
    oils_i18n_gettext(
        'circ.default_overdue_notices_enabled',
        'Receive Overdue and Courtesy Emails',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.default_overdue_notices_enabled',
        'Receive overdue and predue email notifications',
        'cust',
        'description'
    ),
    'circ',
    'bool',
    'true'
);

COMMIT;

\qecho
\qecho The following query will set the circ.default_overdue_notices_enabled
\qecho user setting to true (the default value) for all existing users,
\qecho ensuring they continue to receive overdue/predue emails.
\qecho
\qecho     INSERT INTO actor.usr_setting (usr, name, value)
\qecho     SELECT
\qecho         id,
\qecho         'circ.default_overdue_notices_enabled',
\qecho         'true'
\qecho     FROM actor.usr;
\qecho
\qecho The following query will add the circ.default_overdue_notices_enabled
\qecho user setting as an opt-in setting for all action triggers that send
\qecho emails based on a circ being due (unless another opt-in setting is
\qecho already in use).
\qecho
\qecho     UPDATE action_trigger.event_definition
\qecho     SET opt_in_setting = 'circ.default_overdue_notices_enabled',
\qecho         usr_field = 'usr'
\qecho     WHERE opt_in_setting IS NULL
\qecho         AND hook = 'checkout.due'
\qecho         AND reactor = 'SendEmail';
\qecho
\qecho Evergreen admins who wish to use the new setting should run both of
\qecho the above queries.  Admins who do not wish to use it, or who are
\qecho already using a custom opt-in setting of their own, do not need to
\qecho do anything.
\qecho

