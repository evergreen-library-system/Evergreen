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

<h1>Copy Status Setup</h1>
<hr/>

HEADER

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %cs_cols = ( qw/id SysID name Name holdable Unholdable/ );

my @col_display_order = ( qw/id name holdable/ );

#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	if ( $action eq 'Remove Selected' ) {
		for my $id ( ($cgi->param('id')) ) {
			next unless ($id > 99);
			config::copy_status->retrieve($id)->delete;
		}
	} elsif ( $action eq 'Update Selected' ) {
		for my $id ( ($cgi->param('id')) ) {
			my $u = config::copy_status->retrieve($id);
			$u->name( $cgi->param("name_$id") );
			$u->holdable( $cgi->param("holdable_$id") );
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		config::copy_status->create( { name => $cgi->param("name") } );
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
		print th($cs_cols{$col});
	}
	
	print '<th>Action</th></tr>';
	
	for my $row ( sort { $a->name cmp $b->name } (config::copy_status->retrieve_all) ) {
		print Tr(
			td( $row->id() ),
			td("<input type='text' name='name_$row' value='". $row->name() ."'>"),
			td("<input type='checkbox' name='holdable_$row' value='f'". do {'checked' unless $row->holdable()} .">"),
			td("<input type='checkbox' value='$row' name='id'>"),
		);
	}

	print "<tr class='new_row_class'>",
		td(),
		td("<input type='text' name='name'>"),
		td("<input type='checkbox' name='holdable' value='f'>"),
		td(),
		"</tr>";

	print	"</table>";
	print	"<input type='submit' name='action' value='Remove Selected'/> | ";
	print	"<input type='submit' name='action' value='Update Selected'/> | ";
	print	"<input type='submit' name='action' value='Add New'/></form><hr/>";
}

print "</body></html>";


