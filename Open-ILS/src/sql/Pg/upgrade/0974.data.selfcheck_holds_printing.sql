BEGIN;

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
