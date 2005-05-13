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

<h1>Superuser Setup</h1>
<hr/>

HEADER

#-------------------------------------------------------------------------------
# setup part
#-------------------------------------------------------------------------------

my %user_cols = (
	qw/id SysID active Active usrname Username profile UserProfile passwd Password prefix Prefix
	   first_given_name FirstName second_given_name MiddleName family_name LastName
	   suffix Suffix dob Birthdate email Email day_phone DayPhone evening_phone EveningPhone
	   other_phone CellPhone home_ou HomeLib ident_type IdentificationType
	   ident_value Identification_value photo_url PhotoURL/ );

my @col_display_order = (
	qw/id active usrname passwd profile prefix first_given_name second_given_name
	   family_name suffix dob email day_phone evening_phone other_phone
	   home_ou ident_type ident_value photo_url/ );

my @required_cols = ( qw/profile usrname passwd profile ident_type ident_value
			 first_given_name family_name dob/ );

#-------------------------------------------------------------------------------
# Logic part
#-------------------------------------------------------------------------------

if (my $action = $cgi->param('action')) {
	if ( $action eq 'Update Selected' ) {
		for my $id ( ($cgi->param('id')) ) {
			my $u = actor::user->retrieve($id);
			for my $col ( @col_display_order ) {
				$u->$col( $cgi->param($col."_$id") );
			}
			$u->active( 'f' ) unless ($cgi->param("active_$id"));
			$u->update;
		}
	} elsif ( $action eq 'Add New' ) {
		my $u = actor::user->create(
			{ map { defined($cgi->param($_)) ? ($_ => $cgi->param($_)) : () } keys %user_cols }
		);
		$u->super_user('t');
		$u->update;
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
		print th($user_cols{$col});
	}
	
	print '<th>Update</th></tr>';
	
	for my $row ( sort { $a->usrname cmp $b->usrname } actor::user->search( { super_user => 't' } ) ) {

		print	"<tr class='row_class".
			do {
				if ( !$row->active ) {
					' deactivated';
				}
			}.
			"'>\n";

		print td($row->id); 
		print td("<input type='checkbox' name='active_$row' value='t' ".do{if($row->active){"checked"}}.">");
		print td("<input type='text' name='usrname_$row' value=".$row->usrname.">");
		print td("<input type='password' name='passwd_$row' value=".$row->passwd.">");
		print "<td><select name='profile_$row'>";
		for my $org ( actor::profile->retrieve_all ) {
			print "<option value='".$org->id."' ".do{if($row->profile == $org->id){"selected"}}.">".$org->name."</option>";
		}
		print "</select></td>";
		print td("<input type='text' name='prefix_$row' value=".$row->prefix.">");
		print td("<input type='text' name='first_given_name_$row' value=".$row->first_given_name.">");
		print td("<input type='text' name='second_given_name_$row' value=".$row->second_given_name.">");
		print td("<input type='text' name='family_name_$row' value=".$row->family_name.">");
		print td("<input type='text' name='suffix_$row' value=".$row->suffix.">");
		print td("<input type='text' name='dob_$row' value=".$row->dob.">");
		print td("<input type='text' name='email_$row' value=".$row->email.">");
		print td("<input type='text' name='day_phone_$row' value=".$row->day_phone.">");
		print td("<input type='text' name='evening_phone_$row' value=".$row->evening_phone.">");
		print td("<input type='text' name='other_phone_$row' value=".$row->other_phone.">");
		print "<td><select name='home_ou_$row'>";
		for my $org ( sort { $a->id <=> $b->id } actor::org_unit->retrieve_all ) {
			print "<option value='".$org->id."' ".do{if($row->home_ou == $org->id){"selected"}}.">".do{'&nbsp;&nbsp;'x$org->ou_type->depth}.$org->name."</option>";
		}
		print "</select></td>";
		print "<td><select name='ident_type_$row'>";
		for my $org ( config::identification_type->retrieve_all ) {
			print "<option value='".$org->id."' ".do{if($row->ident_type == $org->id){"selected"}}.">".$org->name."</option>";
		}
		print "</select></td>";
		print td("<input type='text' name='ident_value_$row' value=".$row->ident_value.">");
		print td("<input type='text' name='photo_url_$row' value=".$row->photo_url.">");

		print	"<td><input type='checkbox' value='$row' name='id'></td></tr>\n";
	}

	print "<tr class='new_row_class'>";
	print td(); # id
	print td("<input type='checkbox' name='active' value='t' checked>");
	print td("<input type='text' name='usrname'>");
	print td("<input type='password' name='passwd'>");
	print "<td><select name='profile'>";
	for my $org ( actor::profile->retrieve_all ) {
		print "<option value='".$org->id."'>".$org->name."</option>";
	}
	print "</select></td>";
	print td("<input type='text' name='prefix'>");
	print td("<input type='text' name='first_given_name'>");
	print td("<input type='text' name='second_given_name'>");
	print td("<input type='text' name='family_name'>");
	print td("<input type='text' name='suffix'>");
	print td("<input type='text' name='dob' value='YYYY-MM-DD'>");
	print td("<input type='text' name='email'>");
	print td("<input type='text' name='day_phone'>");
	print td("<input type='text' name='evening_phone'>");
	print td("<input type='text' name='other_phone'>");
	print "<td><select name='home_ou'>";
	for my $row ( sort { $a->id <=> $b->id } actor::org_unit->retrieve_all ) {
		print "<option value='".$row->id."'>".do{'&nbsp;&nbsp;'x$row->ou_type->depth}.$row->name."</option>";
	}
	print "</select></td>";
	print "<td><select name='ident_type'>";
	for my $org ( config::identification_type->retrieve_all ) {
		print "<option value='".$org->id."'>".$org->name."</option>";
	}
	print "</select></td>";
	print td("<input type='text' name='ident_value'>");
	print td("<input type='text' name='photo_url'>");
	
	
	print	"<td></td></tr></table>";
	print	"<input type='submit' name='action' value='Update Selected'/> | ";
	print	"<input type='submit' name='action' value='Add New'/>";
		"</form><hr/>";
}

print "</body></html>";


