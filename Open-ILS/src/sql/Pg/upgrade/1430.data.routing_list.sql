BEGIN;

SELECT evergreen.upgrade_deps_block_check('1430', :eg_version);

INSERT INTO config.print_template
    (name, label, owner, active, locale, content_type, template)
VALUES ('serials_routing_list', 'Serials routing list', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  SET title = template_data.title;
  SET distribution = template_data.distribution;
  SET issuance = template_data.issuance;
  SET routing_list = template_data.routing_list;
  SET stream = template_data.stream;
%] 

<p>[% title %]</p>
<p>[% issuance.label %]</p>
<p>([% distribution.holding_lib.shortname %]) [% distribution.label %] / [% stream.routing_label %] ID [% stream.id %]</p>
  <ol>
	[% FOR route IN routing_list %]
    <li>
    [% IF route.reader %]
      [% route.reader.first_given_name %] [% route.reader.family_name %]
      [% IF route.note %]
        - [% route.note %]
      [% END %]
      [% route.reader.mailing_address.street1 %]
      [% route.reader.mailing_address.street2 %]
      [% route.reader.mailing_address.city %], [% route.reader.mailing_address.state %] [% route.reader.mailing_address.post_code %]
    [% ELSIF route.department %]
      [% route.department %]
      [% IF route.note %]
        - [% route.note %]
      [% END %]
    [% END %]
    </li>
  [% END %]
  </ol>
</div>

$TEMPLATE$ WHERE name = 'serials_routing_list';

COMMIT;
