BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0112');

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

COMMIT;
