#!/usr/bin/perl
use strict;

use OpenILS::Application::Storage;
use OpenILS::Application::Storage::CDBI;

# I need to abstract the driver loading away...
use OpenILS::Application::Storage::Driver::Pg;

use CGI qw/:standard start_*/;
our %config;
do '##CONFIG##/live-db-setup.pl';

OpenILS::Application::Storage::CDBI->connection($config{dsn},$config{usr},$config{pw});
OpenILS::Application::Storage::CDBI->db_Main->{ AutoCommit } = 1;

my $cgi = new CGI;

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %org_cols = ( qw/id SysID name Name parent_ou Parent ou_type OrgUnitType shortname ShortName/ );

my @col_display_order = ( qw/id name shortname ou_type parent_ou/ );

if (my $action = $cgi->param('action')) {
	if ( $action eq 'Update' ) {
		for my $id ( ($cgi->param('id')) ) {
			my $u = actor::org_unit->retrieve($id);
			for my $col ( keys %org_cols ) {
				next if ($cgi->param($col."_$id") =~ /Select One/o);
				$u->$col( $cgi->param($col."_$id") );
			}
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		actor::org_unit->create( { map { defined($cgi->param($_)) ? ($_ => $cgi->param($_)) : () } keys %org_cols } );
	} elsif ( $action eq 'Save Address' ) {
		my $org = actor::org_unit->retrieve($cgi->param('id'));

		my $addr = {};

		$$addr{org_unit} = $cgi->param('org_unit') || $org->id;
		$$addr{street1} = $cgi->param('street1');
		$$addr{street2} = $cgi->param('street2');
		$$addr{city} = $cgi->param('city');
		$$addr{county} = $cgi->param('county');
		$$addr{state} = $cgi->param('state');
		$$addr{country} = $cgi->param('country');
		$$addr{post_code} = $cgi->param('post_code');

		my $a_type = $cgi->param('addr_type');


		my $a = actor::org_address->retrieve($cgi->param('aid'));

		if ($a) {
			for (keys %$addr) {
				next unless $$addr{$_};
				$a->$_($$addr{$_});
			}
			$a->update;
		} else {
			$a = actor::org_address->create( {map {defined($$addr{$_}) ? ($_ => $$addr{$_}) : ()} keys %$addr} );
		}

		$org->$a_type($a->id);
		$org->update;
	}
}

#-------------------------------------------------------------------------------
# HTML part
#-------------------------------------------------------------------------------

print <<HEADER;
Content-type: text/html

<html>

<head>
	<style>
		table.table_class {
			border: dashed lightgrey 1px;
			background-color: #EEE;
			border-collapse: collapse;
		}

		deactivated {
			color: lightgrey;
		}

		tr.new_row_class {
			background: grey;
		}

		tr.row_class td {
			border: solid lightgrey 1px;
		}
		
		tr.header_class th {
			background-color: lightblue;
                        border: solid blue 1px;
                        padding: 2px;
		}


/*--------------------------------------------------|
| dTree 2.05 | www.destroydrop.com/javascript/tree/ |
|---------------------------------------------------|
| Copyright (c) 2002-2003 Geir Landrö               |
|--------------------------------------------------*/

.dtree {
        font-family: Verdana, Geneva, Arial, Helvetica, sans-serif;
        font-size: 11px;
        color: #666;
        white-space: nowrap;
}
.dtree img {
        border: 0px;
        vertical-align: middle;
}
.dtree a {
        color: #333;
        text-decoration: none;
}
.dtree a.node, .dtree a.nodeSel {
        white-space: nowrap;
        padding: 1px 2px 1px 2px;
}
.dtree a.node:hover, .dtree a.nodeSel:hover {
        color: #333;
        text-decoration: underline;
}
.dtree a.nodeSel {
        background-color: #c0d2ec;
}
.dtree .clip {
        overflow: hidden;
}


	</style>
	<script language='javascript' src='support/dtree.js'></script>
</head>

<body style='padding: 25px;'>

<a href="$config{index}">Home</a>

<h1>Library Hierarchy Setup</h1>
<hr/>
HEADER

my $uri = $cgi->url(-relative=>1);

my $top;
for my $lib ( actor::org_unit->search( {parent_ou=>undef} ) ) {
	my $name = $lib->name;
	$name =~ s/'/\\'/og;
	$top = $lib->id;
	print <<"	HEADER";
<div style="float: left;">
	<script language='javascript'>
	var tree = new dTree("tree");
	tree.add($lib, -1, "$name", "$uri?action=child&id=$lib", "$name");
	HEADER
	$top = $lib->id;
	last;
}

for my $lib ( actor::org_unit->search_like( {parent_ou => '%'}, {order_by => 'name'} ) ) {
	my $name = $lib->name;
	$name =~ s/'/\\'/og;
	my $parent = $lib->parent_ou;
	print "\ttree.add($lib, $parent, \"$name\", \"$uri?action=child&id=$lib\", \"$name\");\n";
}

print <<HEADER;
		tree.closeAllChildren($top);
		document.write(tree.toString());
	</script>
</div>
<div>

HEADER

#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	if ( $action eq 'child' ) {
		my $id = $cgi->param('id');
		if ($id) {
			my $node = actor::org_unit->retrieve($id);
			#-----------------------------------------------------------------------
			# child form
			#-----------------------------------------------------------------------

			print "<h2>Edit ".$node->name."</h2>";
			print	"<form method='POST'>".
				"<table class='table_class'><tr class='header_class'>\n";
	
			print Tr(
				th($org_cols{id}),
				td( $node->id() ),
			);
			print Tr(
				th($org_cols{name}),
				td("<input type='text' name='name_$node' value=\"". $node->name() ."\">"),
			);
			print Tr(
				th($org_cols{shortname}),
				td("<input type='text' name='shortname_$node' value='". $node->shortname() ."'>"),
			);
			print Tr(
				th($org_cols{ou_type}),
				td("<select name='ou_type_$node'>".do{
							my $out = '<option>-- Select One --</option>';
							for my $type ( sort {$a->depth <=> $b->depth} actor::org_unit_type->retrieve_all) {
								$out .= "<option value='$type' ".do {
									if ($node->ou_type == $type->id) {
										"selected";
									}}.'>'.$type->name.'</option>'
							}
							$out;
						}."</select>"),
			);
			print Tr(
				th($org_cols{parent_ou}),
				td("<select name='parent_ou_$node'>".do{
						my $out = '<option>-- Select One --</option>';
						for my $org ( sort {$a->id <=> $b->id} actor::org_unit->retrieve_all) {
							$out .= "<option value='$org' ".do {
								if ($node->parent_ou == $org->id) {
									"selected";
								}}.'>'.do{'&nbsp;&nbsp;'x$org->ou_type->depth}.$org->name.'</option>'
						}
						$out;
					}."</select><input type='hidden' value='$node' name='id'>"),
			);

			print Tr( "<td colspan='2'><input type='submit' name='action' value='Update'/></td>" );

			print	"</table></form><hr/><table cellspacing='20'><tr>";


			#-------------------------------------------------------------------------
			# Address edit form
			#-------------------------------------------------------------------------

			my %addrs = (	ill_address	=> 'ILL Address',
					holds_address	=> 'Consortial Holds Address',
					mailing_address	=> 'Mailing Address',
					billing_address	=> 'Physical Address'
			);
			for my $a (qw/billing_address mailing_address holds_address ill_address/) {
				my $addr = actor::org_address->retrieve( $node->$a ) if ($node->$a);

				my %ah = (	street1		=> $addr?$addr->street1:'',
						street2		=> $addr?$addr->street2:'',
						city		=> $addr?$addr->city:'',
						county		=> $addr?$addr->county:'',
						state		=> $addr?$addr->state:'',
						country		=> $addr?$addr->country:'US',
						post_code	=> $addr?$addr->post_code:'',
						org_unit	=> $addr?$addr->org_unit:$node->id,
						id		=> $addr?$addr->id:'',
				);

				print '</tr><tr>' if ($a eq 'holds_address');
				print <<"				TABLE";

<td>
<form method='POST'>
<table class='table_class'>
	<tr>
		<th colspan=2>$addrs{$a}</th>
	</tr>
	<tr>
		<th>SysID</th>
		<td><input type='text' name='aid' value='$ah{id}'></td>
	</tr>
	<tr>
		<th>*Street 1</th>
		<td><input type='text' name='street1' value='$ah{street1}'></td>
	</tr>
	<tr>
		<th>Street 2</th>
		<td><input type='text' name='street2' value='$ah{street2}'></td>
	</tr>
	<tr>
		<th>*City</th>
		<td><input type='text' name='city' value='$ah{city}'></td>
	</tr>
	<tr>
		<th>County</th>
		<td><input type='text' name='county' value='$ah{county}'></td>
	</tr>
	<tr>
		<th>*State</th>
		<td><input type='text' name='state' value='$ah{state}'></td>
	</tr>
	<tr>
		<th>*Country</th>
		<td><input type='text' name='country' value='$ah{country}'></td>
	</tr>
	<tr>
		<th>*ZIP</th>
		<td><input type='text' name='post_code' value='$ah{post_code}'></td>
	</tr>
</table>
<input type='hidden' name='org_unit' value='$ah{org_unit}'>
<input type='hidden' name='addr_type' value='$a'>
<input type='hidden' name='id' value='$node'>
<input type='submit' name='action' value='Save Address'>
</form></td>

				TABLE
			}

			print "<tr></table><hr><h2>New Child</h2>";
	
			print	"<form method='POST'>".
				"<table class='table_class'>\n";

			print Tr(
				th($org_cols{name}),
				td("<input type='text' name='name'>"),
			);
			print Tr(
				th($org_cols{shortname}),
				td("<input type='text' name='shortname'>"),
			);
			print Tr(
				th($org_cols{ou_type}),
				td("<select name='ou_type'>".do{
						my $out = '<option>-- Select One --</option>';
						for my $type ( sort {$a->depth <=> $b->depth} actor::org_unit_type->retrieve_all) {
							$out .= "<option value='$type'>".$type->name.'</option>'
						}
						$out;
					}."</select>"),
			);
			print Tr( "<td colspan='2'><input type='hidden' value='$node' name='parent_ou'>",
				  "<input type='submit' name='action' value='Add New'/></td>" );
			print	"</table></form><hr/>";
		}
	}
}
	
print "</div></body></html>";


