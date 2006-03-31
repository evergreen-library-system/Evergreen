#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
#  Uploads offline action files
#	pending files go into $base_dir/pending/<org>/<ws>.log
#	completed transactions go into 
#	$base_dir/archive/<org>/YYYMMDDHHMM/<ws>.log
# --------------------------------------------------------------------

our $U;
our $logger;
my $MAX_FILE_SIZE = 1000000000; # - roughly 1G upload file size max
require 'offline-lib.pl';


&execute();
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# If the file is present, load it up, otherwise prompt with a very
# basic HTML upload form
# --------------------------------------------------------------------
sub execute {

	if( &offline_cgi->param('file') ) { 

		&load_file(); 
		&handle_event(OpenILS::Event->new('SUCCESS', payload => &offline_seskey));

	} else {
		&display_upload(); 
	}
}


# --------------------------------------------------------------------
# Loads the POSTed file and writes the contents to disk
# --------------------------------------------------------------------
sub load_file() {

	my $wsname	= &offline_cgi->param('ws');
	my $filehandle = &offline_cgi->upload('file');

	# make sure we have upload priveleges
	my $evt = $U->check_perms(&offline_requestor->id, &offline_org, 'OFFLINE_UPLOAD');
	handle_event($evt) if $evt;

	&handle_event(OpenILS::Event->new('OFFLINE_INVALID_SESSION')) if( ! -e &offline_pending_dir );
	my $output = &offline_pending_dir . '/' . "$wsname.log";

	&handle_event(OpenILS::Event->new('OFFLINE_SESSION_ACTIVE')) if( -e &offline_lock_file );
	&handle_event(OpenILS::Event->new('OFFLINE_SESSION_FILE_EXISTS')) if( -e $output );

	$logger->debug("offline: Writing log file $output");
	my $numbytes = 0;
	my $string = "";

	my $cs = &offline_cgi->param('checksum');

	open(FILE, ">$output");

	while( <$filehandle> ) { 
		$numbytes += length "$_";
		$string .= "$_" if $cs;

		if( $numbytes > $MAX_FILE_SIZE ) {
			close(FILE);
			unlink($output);
			&handle_event('OFFLINE_FILE_ERROR');
		}

		print FILE; 
	}
	close(FILE);

	if($cs) {
		my $md5 = md5_hex($string);
		$logger->debug("offline: received checksum $cs, our data shows $md5");
		&handle_event(OpenILS::Event->new('OFFLINE_CHECKSUM_FAILED')) if( $md5 ne $cs ) ;
	}


	# Append the metadata for this workstations upload
	append_meta( {
		requestor	=> &offline_requestor->id, 
		timestamp	=> time, 
		workstation => $wsname,
		log			=> $output, 
		delta			=> &offline_time_delta}, 
		);
}


# --------------------------------------------------------------------
# Use this for testing manual uploads
# --------------------------------------------------------------------
sub display_upload {

	my $ws = &offline_cgi->param('ws') || "";
	my $cs = &offline_cgi->param('checksum') || "";
	my $td = &offline_time_delta;
	my $at = &offline_authtoken;
	my $sk = &offline_description || "";

	print_html(
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
								<td><input type='text' name='delta' value='$td'> </input></td>
							</tr>
							<tr>
								<td>Session Description</td>
								<td><input type='text' name='desc' value='$sk'> </input></td>
							</tr>
							<tr>
								<td colspan='2' align='center'><input type='submit' name='Submit' value='Upload'> </input></td>
							</tr>
						</tbody>
					</table>
					<input type='hidden' name='ses' value='$at'> </input>
					<input type='hidden' name='checksum' value='$cs'> </input>
					<input type='hidden' name='createses' value='1'> </input>
				</form>
			</center>
		HTML
}







