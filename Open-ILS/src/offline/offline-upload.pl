#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
#  Uploads offline action files
#	pending files go into $base_dir/pending/<org>/<ws>.log
#	completed transactions go into $base_dir/archive/<org>/YYYMMDDHHMM/<ws>.log
# --------------------------------------------------------------------

our ($ORG, $META_FILE, $LOCK_FILE, $TIME_DELTA, $MD5_SUM, $PRINT_HTML, $MAX_FILE_SIZE,
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
	my $numbytes = 0;
	my $string = "";
	open(FILE, ">$output");
	while( <$filehandle> ) { 
		$numbytes += length "$_";
		$string .= "$_";

		if( $numbytes > $MAX_FILE_SIZE ) {
			close(FILE);
			unlink($output);
			&handle_event('OFFLINE_FILE_ERROR');
		}

		print FILE; 
	}
	close(FILE);

	if(my $checksum = $cgi->param('checksum')) {
		my $md5 = md5_hex($string);
		$logger->debug("offline: received checksum $checksum, our data shows $md5");
		&handle_event(OpenILS::Event->new('OFFLINE_CHECKSUM_FAILED')) if( $md5 ne $checksum ) ;
	}


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
	my $checksum = $cgi->param('checksum') || "";

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
					<input type='hidden' name='checksum' value='$checksum'> </input>
				</form>
			</center>
		HTML
}







