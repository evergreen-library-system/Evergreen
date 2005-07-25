#!/usr/bin/perl -w
use strict;

use OpenILS::Application::Storage;
use OpenILS::Application::Storage::CDBI;

# I need to abstract the driver loading away...
use OpenILS::Application::Storage::Driver::Pg;

use CGI qw/:standard start_*/;

our %config;
do 'setup.pl';

OpenILS::Application::Storage::CDBI->connection($config{dsn},$config{usr},$config{pw});
OpenILS::Application::Storage::CDBI->db_Main->{ AutoCommit } = 1;

my $cgi = new CGI;

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

		tr.row_class td {
			text-align: right;
			border: solid lightgrey 1px;
		}
		
                tr.new_row_class {
                        background: grey;
                }

		tr.header_class th {
			background-color: lightblue;
                        border: solid blue 1px;
                        padding: 2px;
		}

	</style>
<body style='padding: 25px;'>

<a href="$config{index}">Home</a>

<h1>Configure Circulation Rules</h1>
<hr/>

HEADER

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %dur_cols = (
	name		=> "Name",
	extended	=> "Extended",
	normal		=> "Normal",
	shrt		=> "Short",
	max_renewals	=> "Max Renewals",
);

my @dur_display_order = ( qw/name normal extended shrt max_renewals/ );

my %fine_cols = (
	name			=> "Name",
	high			=> "High",
	normal			=> "Normal",
	low			=> "Low",
	recurance_interval	=> "Interval",
);

my @fine_display_order = ( qw/name recurance_interval normal high low/ );

my %age_cols = (
	name	=> "Name",
	age	=> "Item Age",
	prox	=> "Holdable Radius",
);

my @age_display_order = ( qw/name age prox/ );

my %max_fine_cols = (
	name	=> "Name",
	amount	=> "Amount",
);

my @max_fine_display_order = ( qw/name amount/ );


#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	my $form = $cgi->param('rules_form');

	if ($form eq 'duration') {
		if ($action eq 'Remove Selected') {
			for my $id ( ($cgi->param('remove_me')) ) {
				config::rules::circ_duration->retrieve($id)->delete;
			}
		} elsif ( $action eq 'Add New' ) {
			config::rules::circ_duration->create(
				{ map { ($_ => $cgi->param($_)) } keys %dur_cols }
			);
		}
	} elsif ($form eq 'recuring_fine') {
		if ($action eq 'Remove Selected') {
			for my $id ( ($cgi->param('remove_me')) ) {
				config::rules::recuring_fine->retrieve($id)->delete;
			}
		} elsif ( $action eq 'Add New' ) {
			config::rules::recuring_fine->create(
				{ map { ($_ => $cgi->param($_)) } keys %fine_cols }
			);
		}
	} elsif ($form eq 'max_fine') {
		if ($action eq 'Remove Selected') {
			for my $id ( ($cgi->param('remove_me')) ) {
				config::rules::max_fine->retrieve($id)->delete;
			}
		} elsif ( $action eq 'Add New' ) {
			config::rules::max_fine->create(
				{ map { ($_ => $cgi->param($_)) } keys %max_fine_cols }
			);
		}
	} elsif ($form eq 'age_hold') {
		if ($action eq 'Remove Selected') {
			for my $id ( ($cgi->param('remove_me')) ) {
				config::rules::age_hold_protect->retrieve($id)->delete;
			}
		} elsif ( $action eq 'Add New' ) {
			config::rules::age_hold_protect->create(
				{ map { ($_ => $cgi->param($_)) } keys %age_cols }
			);
		}
	}


}


#-------------------------------------------------------------------------------
# Form part
#-------------------------------------------------------------------------------
{
	#-----------------------------------------------------------------------
	# Duration form
	#-----------------------------------------------------------------------
	print	"<form method='POST'>".
		"<input type='hidden' name='rules_form' value='duration'>".
		"<h2>Circulation Duration</h2>".
		"<table class='table_class'><tr class='header_class'>\n";
	
	for my $col ( @dur_display_order ) {
		print th($dur_cols{$col});
	}
	
	print "<td/>\n";
	
	for my $row ( config::rules::circ_duration->retrieve_all ) {
		print "</tr><tr class='row_class'>";
		for my $col ( @dur_display_order ) {
			print td($row->$col);
		}
		print	"<td><input type='checkbox' value='$row' name='remove_me'</td>";
	}
	print "</tr><tr class='new_row_class'>\n";
	
	for my $col ( @dur_display_order ) {
		print td("<input type='text' name='$col'>");
	}
	
	
	print	"<td/></tr></table>".
		"<input type='submit' name='action' value='Add New'/> | ".
		"<input type='submit' name='action' value='Remove Selected'/>".
		"</form><hr/>";
}

{
	#-----------------------------------------------------------------------
	# Recuring Fine form
	#-----------------------------------------------------------------------
	print	"<form method='POST'>".
		"<input type='hidden' name='rules_form' value='recuring_fine'>".
		"<h2>Recuring Fine Levels</h2>".
		"<table class='table_class'><tr class='header_class'>\n";
	
	for my $col ( @fine_display_order ) {
		print th($fine_cols{$col});
	}
	
	print "<td/>\n";
	
	for my $row ( config::rules::recuring_fine->retrieve_all ) {
		print "</tr><tr class='row_class'>\n";
		for my $col ( @fine_display_order ) {
			print td($row->$col);
		}
		print	"<td><input type='checkbox' value='$row' name='remove_me'</td>";
	}
	
	print "</tr><tr class='new_row_class'>\n";

	for my $col ( @fine_display_order ) {
		print td("<input type='text' name='$col'>");
	}
	
	
	print	"<td/></tr></table>".
		"<input type='submit' name='action' value='Add New'/> | ".
		"<input type='submit' name='action' value='Remove Selected'/>".
		"</form><hr/>";
}

{
	#-----------------------------------------------------------------------
	# Max Fine form
	#-----------------------------------------------------------------------
	print	"<form method='POST'>".
		"<input type='hidden' name='rules_form' value='max_fine'>".
		"<h2>Max Fine Levels</h2>".
		"<table class='table_class'><tr class='header_class'>\n";
	
	for my $col ( @max_fine_display_order ) {
		print th($max_fine_cols{$col});
	}
	
	print "<td/>\n";
	
	for my $row ( config::rules::max_fine->retrieve_all ) {
	print "</tr><tr class='row_class'>\n";
		for my $col ( @max_fine_display_order ) {
			print td($row->$col);
		}
		print	"<td><input type='checkbox' value='$row' name='remove_me'</td>";
	}
	
	print "</tr><tr class='new_row_class'>\n";

	for my $col ( @max_fine_display_order ) {
		print td("<input type='text' name='$col'>");
	}
	
	
	print	"<td/></tr></table>".
		"<input type='submit' name='action' value='Add New'/> | ".
		"<input type='submit' name='action' value='Remove Selected'/>".
		"</form><hr/>";
}

{
	#-----------------------------------------------------------------------
	# Age hold protect form
	#-----------------------------------------------------------------------
	print	"<form method='POST'>".
		"<input type='hidden' name='rules_form' value='age_hold'>".
		"<h2>Item Age Hold Protection</h2>".
		"<table class='table_class'><tr class='header_class'>\n";
	
	for my $col ( @age_display_order ) {
		print th($age_cols{$col});
	}
	
	print "<td/>\n";
	
	for my $row ( config::rules::age_hold_protect->retrieve_all ) {
		print "</tr><tr class='row_class'>\n";
		for my $col ( @age_display_order ) {
			print td($row->$col);
		}
		print	"<td><input type='checkbox' value='$row' name='remove_me'</td>";
	}

	print "</tr><tr class='new_row_class'>\n";
	
	for my $col ( @age_display_order ) {
		print td("<input type='text' name='$col'>");
	}
	
	
	print	"<td/></tr></table>".
		"<input type='submit' name='action' value='Add New'/> | ".
		"<input type='submit' name='action' value='Remove Selected'/>".
		"</form><hr/>";
}


print "</body></html>";


