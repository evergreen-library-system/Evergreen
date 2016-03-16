--Upgrade Script for 2.8.6 to 2.8.7
\set eg_version '''2.8.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.7', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0959', :eg_version);

CREATE OR REPLACE VIEW money.transaction_billing_summary AS
    SELECT id as xact,
        last_billing_type,
        last_billing_note,
        last_billing_ts,
        total_owed
      FROM money.materialized_billable_xact_summary;


SELECT evergreen.upgrade_deps_block_check('0972', :eg_version); -- jstompro/gmcharlt

-- LP#1550495 - Add Baker&Taylor EDI Quantity Cancel Code
-- Insert EDI Cancel Reason 85 (1200 + 85 = 1285) if it doesn't already exist
INSERT INTO acq.cancel_reason 
   (org_unit, keep_debits, id, label, description)
   SELECT 
     1, 'f',( 85+1200),
     oils_i18n_gettext(1285, 'Canceled: By Vendor', 'acqcr', 'label'),
     oils_i18n_gettext(1285, 'Line item canceled by vendor', 'acqcr', 'description')
   WHERE NOT EXISTS (
    SELECT 1 FROM acq.cancel_reason where id=(85+1200)
   );



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


SELECT evergreen.upgrade_deps_block_check('0974', :eg_version); -- tmccanna/gmcharlt

UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>
    Holds for:<br/>
	[% user.family_name %], [% user.first_given_name %]
	
    <ol>
    [% FOR hold IN target %]
        [%-
            SET idx = loop.count - 1;
            SET udata =  user_data.$idx;
        -%]
        <li>
            <div>Title: [% udata.item_title %]</div>
            <div>Author: [% udata.item_author %]</div>
            <div>Pickup Location: [% udata.pickup_lib %]</b></div>
            <div>Status: 
                [%- IF udata.ready -%]
                    Ready for pickup
                [% ELSE %]
                    #[% udata.queue_position %] of 
                      [% udata.potential_copies %] copies.
                [% END %]
            </div>
        </li>
    [% END %]
    </ol>
</div>

$$ WHERE id=12
AND template = 
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
;

COMMIT;
