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
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');

	return 0 if $folder->owner ne $e->requestor->id;

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

	my $class = 'rrf';
	$class = 'rtf' if $type eq 'template';
	$class = 'rof' if $type eq 'output';
	my $flesh = {flesh => 1,flesh_fields => { $class => ['owner', 'share_with']}};

	my $meth = "search_reporter_${type}_folder";
	my $fs = $e->$meth( [{ owner => $e->requestor->id }, $flesh] );

	my @orgs;
	my $o = $U->storagereq(
		'open-ils.storage.actor.org_unit.full_path.atomic', $e->requestor->ws_ou);
	push( @orgs, $_->id ) for @$o;

	my $fs2 = $e->$meth(
		[
			{
				shared => 't', 
				share_with => \@orgs, 
				owner => { '!=' => $e->requestor->id } 
			}, 
			$flesh
		]
	);
	push( @$fs, @$fs2);
	return $fs;
}



__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder_data.retrieve',
	method => 'retrieve_folder_data'
);

sub retrieve_folder_data {
	my( $self, $conn, $auth, $type, $folderid, $limit ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $meth = "search_reporter_${type}";
	my $class = 'rr';
	$class = 'rt' if $type eq 'template';
	my $flesh = {
		flesh => 1,
		flesh_fields => { $class => ['owner']}, 
		order_by => { $class => 'create_time DESC'} 
	};
	$flesh->{limit} = $limit if $limit;
	return $e->$meth([{ folder => $folderid }, $flesh]); 
}

__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.schedule.retrieve_by_folder',
	method => 'retrieve_schedules');
sub retrieve_schedules {
	my( $self, $conn, $auth, $folderId, $limit ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');

	my $search = { folder => $folderId };
	my $query = [
		{ folder => $folderId },
		{ order_by => { rs => 'run_time DESC' } }
	];

	$query->[1]->{limit} = $limit if $limit;
	return $e->search_reporter_schedule($query);
}

__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.schedule.retrieve',
	method => 'retrieve_schedules');
sub retrieve_schedule {
	my( $self, $conn, $auth, $sched_id ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('RUN_REPORTS');
	my $s = $e->retrieve_reporter_schedule($sched_id)
		or return $e->event;
	return $s;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template.create',
	method => 'create_template');
sub create_template {
	my( $self, $conn, $auth, $template ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
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
	my( $self, $conn, $auth, $report, $schedule ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	$report->owner($e->requestor->id);
	my $rpt = $e->create_reporter_report($report)
		or return $e->die_event;
	$schedule->report($rpt->id);
	$schedule->runner($e->requestor->id);
	$e->create_reporter_schedule($schedule) or return $e->die_event;
	$e->commit;
	return $rpt;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.scheduleer.schedule.create',
	method => 'create_schedule');
sub create_schedule {
	my( $self, $conn, $auth, $schedule ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $sched = $e->create_reporter_schedule($schedule)
		or return $e->die_event;
	$e->commit;
	return $sched;
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
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $t = $e->retrieve_reporter_template($tmpl->id)
		or return $e->die_event;
	return 0 if $t->owner ne $e->requestor->id;
	$e->update_reporter_template($tmpl)
		or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.report.update',
	method => 'update_report');
sub update_report {
	my( $self, $conn, $auth, $report ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $r = $e->retrieve_reporter_report($report->id)
		or return $e->die_event;
	if( $r->owner ne $e->requestor->id ) {
		$e->rollback;
		return 0;
	}
	$e->update_reporter_report($report)
		or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder.update',
	method => 'update_folder');
sub update_folder {
	my( $self, $conn, $auth, $type, $folder ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $meth = "retrieve_reporter_${type}_folder";
	my $f = $e->$meth($folder->id) or return $e->die_event;
	return 0 if $f->owner ne $e->requestor->id;
	$meth = "update_reporter_${type}_folder";
	$e->$meth($folder) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.folder.delete',
	method => 'delete_folder');
sub delete_folder {
	my( $self, $conn, $auth, $type, $folderId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $meth = "retrieve_reporter_${type}_folder";
	my $f = $e->$meth($folderId) or return $e->die_event;
	return 0 if $f->owner ne $e->requestor->id;
	$meth = "delete_reporter_${type}_folder";
	$e->$meth($f) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template.delete',
	method => 'delete_template');
sub delete_template {
	my( $self, $conn, $auth, $templateId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');

	my $t = $e->retrieve_reporter_template($templateId)
		or return $e->die_event;
	return 0 if $t->owner ne $e->requestor->id;
	$e->delete_reporter_template($t) or return $e->die_event;
	$e->commit;
	return 1;
}

__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.report.delete',
	method => 'delete_report');
sub delete_report {
	my( $self, $conn, $auth, $reportId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');

	my $t = $e->retrieve_reporter_report($reportId)
		or return $e->die_event;
	return 0 if $t->owner ne $e->requestor->id;
	$e->delete_reporter_report($t) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.schedule.delete',
	method => 'delete_schedule');
sub delete_schedule {
	my( $self, $conn, $auth, $scheduleId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');

	my $t = $e->retrieve_reporter_schedule($scheduleId)
		or return $e->die_event;
	return 0 if $t->runner ne $e->requestor->id;
	$e->delete_reporter_schedule($t) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.template_has_reports',
	method => 'has_reports');
sub has_reports {
	my( $self, $conn, $auth, $templateId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $rpts = $e->search_reporter_report({template=>$templateId},{idlist=>1});
	return 1 if @$rpts;
	return 0;
}

__PACKAGE__->register_method(
	api_name => 'open-ils.reporter.report_has_output',
	method => 'has_output');
sub has_output {
	my( $self, $conn, $auth, $reportId ) = @_;
	my $e = new_rstore_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('RUN_REPORTS');
	my $outs = $e->search_reporter_schedule({report=>$reportId},{idlist=>1});
	return 1 if @$outs;
	return 0;
}



__PACKAGE__->register_method(
	method => 'org_full_path',
	api_name => 'open-ils.reporter.org_unit.full_path');

sub org_full_path {
	my( $self, $conn, $orgid ) = @_;
	return $U->storagereq(
		'open-ils.storage.actor.org_unit.full_path.atomic', $orgid );
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
