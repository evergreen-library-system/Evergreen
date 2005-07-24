#!/usr/bin/perl
use strict;

use OpenILS::Application::Storage;
use OpenILS::Application::Storage::CDBI;

# I need to abstract the driver loading away...
use OpenILS::Application::Storage::Driver::Pg;

use CGI qw/:standard start_*/;

our %config;
do '../setup.pl';

OpenILS::Application::Storage::CDBI->connection($config{dsn},$config{usr},$config{pw});
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
			my $u = permission::grp_tree->retrieve($id);
			for my $col ( keys %org_cols ) {
				next if ($cgi->param($col."_$id") =~ /Select One/o);
				$u->$col( $cgi->param($col."_$id") );
			}
			$u->update;
		}
	} elsif ( $action eq 'Set Permissions' ) {
		my $grp = permission::grp_tree->retrieve($cgi->param('perms'));
		my @ids = $cgi->param('permission');
		for my $perm ( permission::perm_list->retrieve_all ) {
			if (my $id = $cgi->param('permission_'.$perm->id) ) {
				my $p = permission::grp_perm_map->search({perm=>$id,grp=>$grp->id})->next;
				my $d = $cgi->param("depth_$id");
				if (!$p) {
					$p = permission::grp_perm_map->create({perm=>$id,grp=>$grp->id,depth=>$d});
				} else {
					$p->depth( $d );
				}
				$p->update;
			} else {
				permission::grp_perm_map->search({perm=>$perm->id,grp=>$grp->id})->delete_all;
			}
		}
		$cgi->param('action'=>'child');
	} elsif ( $action eq 'Add New' ) {
		permission::grp_tree->create( { map { defined($cgi->param($_)) ? ($_ => $cgi->param($_)) : () } keys %org_cols } );
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

<a href="$config{index}">Home</a>

<h1>User Group Hierarchy Setup</h1>
<hr/>
HEADER

my $uri = $cgi->url(-relative=>1);

my $top;
for my $grp ( permission::grp_tree->search( {parent=>undef} ) ) {
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

for my $grp ( permission::grp_tree->search_like( {parent => '%'}, {order_by => 'id'} ) ) {
	my $name = $grp->name;
	$name =~ s/'/\\'/og;
	my $parent = $grp->parent;
	print <<"	JS"
		var node_$grp = new WebFXTreeItem('$name','$uri?action=child&id=$grp');
	JS
}

for my $grp ( sort {$a->name cmp $b->name} permission::grp_tree->retrieve_all ) {
	my $parent = $grp->parent;
	next unless $parent;
	print <<"	JS"
		node_$parent.add(node_$grp);
	JS
}

print <<HEADER;
		document.write(node_$top);
	</script>
</div>
<div style="float:right; width:50%;">

HEADER

#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	if ( $action eq 'child' ) {
		my $id = $cgi->param('id');
		if ($id) {
			my $node = permission::grp_tree->retrieve($id);
			#-----------------------------------------------------------------------
			# child form
			#-----------------------------------------------------------------------

			print "<h2>Edit Group '".$node->name."'</h2>";
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
				th($org_cols{parent}),
				td("<select name='parent_$node'>".do{
						my $out = '<option>-- Select One --</option>';
						for my $org ( sort {$a->id <=> $b->id} permission::grp_tree->retrieve_all) {
							$out .= "<option value='$org' ".do {
								if ($node->parent == $org->id) {
									"selected";
								}}.'>'.$org->name.'</option>'
						}
						$out;
					}."</select><input type='hidden' value='$node' name='id'>"),
			);

			print Tr( "<td colspan='2'><input type='submit' name='action' value='Update'/></td>" );

			print	"</table></form><hr/>";


			print "<h2>Group Permissions</h2>";

			print   "<form method='POST'>".
				"<table class='table_class'>\n".
				"<tr class='header_class'><th>Permission</th><th>Select</th><th>At Depth</th></tr>";

			for my $perm ( sort {$a->code cmp $b->code} permission::perm_list->retrieve_all ) {
				my $grp = $node;
				my $out = '<select name="depth_'.$perm->id.'"><option value="">-- Select One --</option>';
				for my $outype ( actor::org_unit_type->retrieve_all ) {
					my $grp = $node;
					$out .= "<option value='".$outype->depth."' ".do{
						my $stuff = '';
						do {
							if ($grp) {
								my $setting = permission::grp_perm_map->search(
								  		{ grp  => $grp->id,
										  perm => $perm->id }
								)->next;
								$stuff = "selected " if($setting && $outype->depth == $setting->depth);
								if($stuff && $setting && $setting->grp != $node->id) {
									$out =~ s/^<select/<select disabled/o;
								}
							}
						} while (!$stuff && $grp && ($grp = $grp->parent));
						$stuff;
					}.">".$outype->name."</option>";
				}
				$out .= "</select>";
				$grp = $node;
				print Tr( "<td>".$perm->code."</td><td>".
					  "<input type='checkbox' name='permission_$perm' value='$perm' ".
					  do{
					  	my $stuff = '';
						do {
							if ($grp) {
								my $setting = permission::grp_perm_map->search(
								  		{ grp  => $grp->id,
										  perm => $perm->id }
								)->next;
							  	$stuff = "checked " if ($setting);
								$stuff .= "disabled " if($setting && $setting->grp != $node->id);
							}
						} while (!$stuff && $grp && ($grp = $grp->parent));
					  	$stuff;
					  }.
					  "></td><td>$out</td>"

				);
			}
			
			print Tr( "<td colspan='3'><input type='hidden' value='$node' name='perms'>",
				  "<input type='submit' name='action' value='Set Permissions'/></td>" );
			print	"</table></form><hr/>";



			print "<h2>New Child</h2>";
	
			print	"<form method='POST'>".
				"<table class='table_class'>\n";

			print Tr(
				th($org_cols{name}),
				td("<input type='text' name='name'>"),
			);
			print Tr( "<td colspan='2'><input type='hidden' value='$node' name='parent'>",
				  "<input type='submit' name='action' value='Add New'/></td>" );
			print	"</table></form><hr/>";

		}
	}
}
	
print "</div></body></html>";


