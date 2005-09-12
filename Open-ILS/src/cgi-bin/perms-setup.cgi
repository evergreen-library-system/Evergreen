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

<h1>Permission List Setup</h1>
<hr/>

HEADER

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %profile_cols = ( qw/id SysID code Name description Description/ );

my @col_display_order = ( qw/id code description/ );

#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	if ( $action eq 'Remove Selected' ) {
		for my $id ( ($cgi->param('id')) ) {
			permission::perm_list->retrieve($id)->delete;
		}
	} elsif ( $action eq 'Update Selected' ) {
		for my $id ( ($cgi->param('id')) ) {
			my $u = permission::perm_list->retrieve($id);
			$u->code( $cgi->param("code_$id") );
			$u->description( $cgi->param("description_$id") );
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		permission::perm_list->create(
			{ code		=> $cgi->param("code"),
			  description	=> $cgi->param("description")
			}
		);
	}
}


#-------------------------------------------------------------------------------
# Form part
#-------------------------------------------------------------------------------
{
	#-----------------------------------------------------------------------
	# User form
	#-----------------------------------------------------------------------
	print	"<form method='POST'>".
		"<table class='table_class'><tr class='header_class'>\n";
	
	for my $col ( @col_display_order ) {
		print th($profile_cols{$col});
	}
	
	print '<th>Action</th></tr>';
	
	for my $row ( sort { $a->code cmp $b->code } (permission::perm_list->retrieve_all) ) {
		print Tr(
			td( $row->id() ),
			td("<input type='text' name='code_$row' value='". $row->code() ."'>"),
			td("<input type='text' size='50' name='description_$row' value='". $row->description() ."'>"),
			td("<input type='checkbox' value='$row' name='id'>"),
		);
	}

	print "<tr class='new_row_class'>",
		td(),
		td("<input type='text' name='code'>"),
		td("<input type='text' size='50' name='description'>"),
		td(),
		"</tr>";
	print	"</table>";
	print	"<input type='submit' name='action' value='Remove Selected'/> | ";
	print	"<input type='submit' name='action' value='Update Selected'/> | ";
	print	"<input type='submit' name='action' value='Add New'/></form><hr/>";
}

print "</body></html>";


