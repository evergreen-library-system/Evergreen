package OpenILS::Application::Reporter;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
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


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template.update',
	method => 'update_template');
sub update_template {
	my( $self, $conn, $auth, $tmpl ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $t = $e->retrieve_reporter_template($tmpl->id)
		or return $e->die_event;
	return 0 if $t->owner ne $e->requestor->id;
	$e->update_reporter_template($tmpl)
		or return $e->die_event;
	$e->commit;
	return 1;
}



__PACKAGE__->register_method(
	method => 'magic_fetch_all',
	api_name => 'open-ils.reporter.magic_fetch');
sub magic_fetch_all {
	my( $self, $conn, $auth, $args ) = @_;
	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');

	my $hint = $$args{hint};

	# Find the class the iplements the given hint
	my ($class) = grep { 
		$Fieldmapper::fieldmap->{$_}{hint} eq $hint } Fieldmapper->classes;

	return undef unless $class->Selector;

	$class =~ s/Fieldmapper:://og;
	$class =~ s/::/_/og;
	my $method = "retrieve_all_$class";

	$logger->info("reporter.magic_fetch => $method");

	return $e->$method();
}


1;
