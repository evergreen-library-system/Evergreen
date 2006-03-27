#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
#  Uploads offline action files
#	pending files go into $base_dir/pending/<org>/<ws>.log
#	completed transactions go into $base_dir/archive/<org>/YYYMMDDHHMM/<ws>.log
# --------------------------------------------------------------------

our ($ORG, $META_FILE, $LOCK_FILE, $TIME_DELTA, $MD5_SUM, $PRINT_HTML,
	$AUTHTOKEN, $REQUESTOR, $U, %config, $cgi, $base_dir, $logger);

require 'offline-lib.pl';

if( $cgi->param('file') ) { 
	&load_file(); 
	&handle_event(OpenILS::Event->new('SUCCESS'));
} else {
	&display_upload(); 
}

# --------------------------------------------------------------------
# Loads the POSTed file and writes the contents to disk
# --------------------------------------------------------------------
sub load_file() {

	my $wsname	= $cgi->param('ws');
	my $filehandle = $cgi->upload('file');

	my $ws = fetch_workstation($wsname);
	$ORG = $ws->owning_lib;

	# make sure we have upload priveleges
	my $evt = $U->check_perms($REQUESTOR->id, $ORG, 'OFFLINE_UPLOAD');
	handle_event($evt) if $evt;

	my $dir = get_pending_dir();
	my $output = "$dir/$wsname.log";
	my $lock = "$dir/$LOCK_FILE";

	&handle_event(OpenILS::Event->new('OFFLINE_SESSION_ACTIVE')) if( -e $lock );
	&handle_event(OpenILS::Event->new('OFFLINE_SESSION_FILE_EXISTS')) if( -e $output );

	$logger->debug("offline: Writing log file $output");
	open(FILE, ">$output");
	while( <$filehandle> ) { print FILE; }
	close(FILE);

	# Append the metadata for this workstations upload
	append_meta( {
		requestor	=> $REQUESTOR->id, 
		timestamp	=> time, 
		workstation => $wsname,
		log			=> $output, 
		delta			=> $TIME_DELTA}, 
		);
}


# --------------------------------------------------------------------
# Use this for testing manual uploads
# --------------------------------------------------------------------
sub display_upload {
	my $ws	= $cgi->param('ws') || "";

	print_html(
		title => "Offline Upload",
		body => <<"		HTML");
			<center>
				<form action='offline-upload.pl' method='post' enctype='multipart/form-data'>
					<b> - Select an offline file to upload - </b><br/><br/>
					<table>
						<tbody>
							<tr>
								<td>File to Upload: </td>
								<td><input type='file' name='file'> </input></td>
							</tr>
							<tr>
								<td>Workstation Name: </td>
								<td><input type='text' name='ws' value='$ws'></input></td>
							</tr>
							<tr>
								<td>Time Delta: </td>
								<td><input type='text' name='delta' value='$TIME_DELTA'> </input></td>
							</tr>
							<tr>
								<td colspan='2' align='center'><input type='submit' name='Submit' value='Upload'> </input></td>
							</tr>
						</tbody>
					</table>
					<input type='hidden' name='ses' value='$AUTHTOKEN'> </input>
					<input type='hidden' name='html' value='$PRINT_HTML'> </input>
				</form>
			</center>
		HTML
}







