#!/usr/bin/perl
use strict;

use OpenILS::Application::Storage;
use OpenILS::Application::Storage::CDBI;

# I need to abstract the driver loading away...
use OpenILS::Application::Storage::Driver::Pg;

use CGI qw/:standard start_*/;

OpenILS::Application::Storage::CDBI->connection('dbi:Pg:host=10.0.0.2;dbname=open-ils-dev', 'postgres');
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
				$u->$col( $cgi->param($col."_$id") );
			}
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		actor::org_unit->create( { map { defined($cgi->param($_)) ? ($_ => $cgi->param($_)) : () } keys %org_cols } );
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

		tr.row_class td {
			border: solid lightgrey 1px;
		}
		
		tr.header_class th {
			background-color: lightblue;
		}

	</style>
	<script language='javascript' src='/js/widgets/xtree.js'></script>
</head>

<body style='padding: 25px;'>

<h1>Library Hierarchy Setup</h1>
<hr/>
HEADER

my $top;
for my $lib ( actor::org_unit->search( {parent_ou=>undef} ) ) {
	my $name = $lib->name;
	$name =~ s/'/\\'/og;
	print <<"	HEADER";
<div style="float: left;">
	<script language='javascript'>

		function getById (id) { return document.getElementById(id); }
		function createAppElement (el) { return document.createElement(el); }
		function createAppTextNode (txt) { return document.createTextNode(txt); }
	
		var node_$lib = new WebFXTree('$name');
	HEADER
	$top = $lib->id;
	last;
}

for my $lib ( actor::org_unit->search_like( {parent_ou => '%'}, {order_by => 'id'} ) ) {
	my $name = $lib->name;
	$name =~ s/'/\\'/og;
	my $parent = $lib->parent_ou;
	my $uri = $cgi->url(-relative=>1);
	print <<"	JS"
		var node_$lib = new WebFXTreeItem('$name','$uri?action=child&id=$lib');
	JS
}for my $lib ( sort {$a->name cmp $b->name} actor::org_unit->retrieve_all ) {
	my $parent = $lib->parent_ou;
	next unless $parent;
	print <<"	JS"
		node_$parent.add(node_$lib);
	JS
}

print <<HEADER;
		document.write(node_$top);
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
				td("<input type='text' name='name_$node' value='". $node->name() ."'>"),
			);
			print Tr(
				th($org_cols{shortname}),
				td("<input type='text' name='shortname_$node' value='". $node->shortname() ."'>"),
			);
			print Tr(
				th($org_cols{ou_type}),
				td("<select name='ou_type_$node'>".do{
							my $out = '';
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
						my $out = '';
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

			print	"</table></form><hr/>";


			print "<h2>New Child</h2>";
	
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
				td("<select name='ou_type_$node'>".do{
						my $out = '';
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


