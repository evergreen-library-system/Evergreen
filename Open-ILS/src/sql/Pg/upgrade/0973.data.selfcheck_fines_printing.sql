BEGIN;

SELECT evergreen.upgrade_deps_block_check('0973', :eg_version); -- tmccanna/gmcharlt

UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%- SET user = target -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>   
	Fines for:<br/>
    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR xact IN user.open_billable_transactions_summary %]
        [% IF xact.balance_owed > 0 %]
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
    [% END %]
    </ol>
</div>
$$ WHERE id=13
AND template = 
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
;

COMMIT;
