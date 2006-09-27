package OpenILS::Application::Reporter;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder.create',
	method => 'create_folder'
);

sub create_folder {
	my( $self, $conn, $auth, $type, $folder ) = @_;

	my $e = new_rstore_editor(xact=>1, authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');

	$folder->owner($e->requestor->id);
	my $meth = "create_reporter_${type}_folder";
	$e->$meth($folder) or return $e->die_event;
	$e->commit;

	return $folder->id;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder.visible.retrieve',
	method => 'retrieve_visible_folders'
);

sub retrieve_visible_folders {
	my( $self, $conn, $auth, $type ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');

	my $meth = "search_reporter_${type}_folder";
	my $fs = $e->$meth( { owner => $e->requestor->id } );

	# XXX fetch folders visible to me

	return $fs;
}



__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder_data.retrieve',
	method => 'retrieve_folder_data'
);

sub retrieve_folder_data {
	my( $self, $conn, $auth, $type, $folderid ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $meth = "search_reporter_${type}";
	return $e->$meth( { folder => $folderid } );
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template.create',
	method => 'create_template');
sub create_template {
	my( $self, $conn, $auth, $template ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	$template->owner($e->requestor->id);
	my $tmpl = $e->create_reporter_template($template)
		or return $e->die_event;
	$e->commit;
	return $tmpl;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.report.create',
	method => 'create_report');
sub create_report {
	my( $self, $conn, $auth, $report ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	$report->owner($e->requestor->id);
	my $tmpl = $e->create_reporter_report($report)
		or return $e->die_event;
	$e->commit;
	return $tmpl;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template.retrieve',
	method => 'retrieve_template');
sub retrieve_template {
	my( $self, $conn, $auth, $id ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $t = $e->retrieve_reporter_template($id) 
		or return $e->event;
	return $t;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.report.retrieve',
	method => 'retrieve_report');
sub retrieve_report {
	my( $self, $conn, $auth, $id ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $r = $e->retrieve_reporter_report($id) 
		or return $e->event;
	return $r;
}


1;
