#!/usr/bin/perl
use strict;

use OpenILS::Application::Storage;
use OpenILS::Application::Storage::CDBI;

# I need to abstract the driver loading away...
use OpenILS::Application::Storage::Driver::Pg;

use CGI qw/:standard start_*/;

OpenILS::Application::Storage::CDBI->connection('dbi:Pg:host=10.0.0.2;dbname=demo-dev', 'postgres');
OpenILS::Application::Storage::CDBI->db_Main->{ AutoCommit } = 1;

my $cgi = new CGI;

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %org_cols = ( qw/id GroupID name Name parent ParentGroup/ );

my @col_display_order = ( qw/id name parent/ );

if (my $action = $cgi->param('action')) {
	if ( $action eq 'Update' ) {
		for my $id ( ($cgi->param('id')) ) {
			my $u = permission::group_tree->retrieve($id);
			for my $col ( keys %org_cols ) {
				$u->$col( $cgi->param($col."_$id") );
			}
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		permission::group_tree->create( { map { defined($cgi->param($_)) ? ($_ => $cgi->param($_)) : () } keys %org_cols } );
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

	</style>
	<script language='javascript' src='/js/widgets/xtree.js'></script>
</head>

<body style='padding: 25px;'>

<h1>User Group Hierarchy Setup</h1>
<hr/>
HEADER

my $uri = $cgi->url(-relative=>1);

my $top;
for my $grp ( permission::group_tree->search( {parent=>undef} ) ) {
	my $name = $grp->name;
	$name =~ s/'/\\'/og;
	print <<"	HEADER";
<div style="float: left;">
	<script language='javascript'>

		function getById (id) { return document.getElementById(id); }
		function createAppElement (el) { return document.createElement(el); }
		function createAppTextNode (txt) { return document.createTextNode(txt); }
	
		var node_$grp = new WebFXTree('$name','$uri?action=child&id=$grp');
	HEADER
	$top = $grp->id;
	last;
}

for my $grp ( permission::group_tree->search_like( {parent_ou => '%'}, {order_by => 'id'} ) ) {
	my $name = $grp->name;
	$name =~ s/'/\\'/og;
	my $parent = $grp->parent_ou;
	print <<"	JS"
		var node_$grp = new WebFXTreeItem('$name','$uri?action=child&id=$grp');
	JS
}for my $grp ( sort {$a->name cmp $b->name} permission::group_tree->retrieve_all ) {
	my $parent = $grp->parent_ou;
	next unless $parent;
	print <<"	JS"
		node_$parent.add(node_$grp);
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
			my $node = permission::group_tree->retrieve($id);
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
				th($org_cols{depth}),
				td("<select name='depth_$node'>".do{
							my $out = '<option>-- Select One --</option>';
							for my $type ( sort {$a->depth <=> $b->depth} actor::org_unit_type->retrieve_all) {
								$out .= "<option value='".$type->depth."' ".do {
									if ($node->depth == $type->depth) {
										"selected";
									}}.'>'.$type->name.'</option>'
							}
							$out;
						}."</select>"),
			);
			print Tr(
				th($org_cols{parent}),
				td("<select name='parent_ou_$node'>".do{
						my $out = '<option>-- Select One --</option>';
						for my $org ( sort {$a->id <=> $b->id} permission::group_tree->retrieve_all) {
							$out .= "<option value='$org' ".do {
								if ($node->parent == $org->id) {
									"selected";
								}}.'>'.do{'&nbsp;&nbsp;'x$org->depth}.$org->name.'</option>'
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
				th($org_cols{depth}),
				td("<select name='depth'>".do{
						my $out = '<option>-- Select One --</option>';
						for my $type ( sort {$a->depth <=> $b->depth} actor::org_unit_type->retrieve_all) {
							$out .= "<option value='".$type->depth."'>".$type->name.'</option>'
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


