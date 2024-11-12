package OpenILS::Application::Reporter;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.output_visible',
    method => 'output_visible'
);

sub output_visible {
    my( $self, $conn, $auth, $output_id, @perms) = @_;

    @perms = grep { $_ ne 'VIEW_REPORT_OUTPUT' } @perms;
    push @perms, 'VIEW_REPORT_OUTPUT'; # required permission

    my $e = new_rstore_editor(xact=>1, authtoken=>$auth);
    return 0 unless $e->checkauth;

    my $output = $e->retrieve_reporter_schedule($output_id);
    return 1 if $output->runner == $e->requestor->id; # you can see your own

    my $output_folder = $e->retrieve_reporter_output_folder($output->folder);
    return 1 if $output_folder->owner == $e->requestor->id; # you can see ones in your folders

    if ($U->is_true($output_folder->shared)) {
        return 0 if $U->check_user_perms(
            $e->requestor->id,
            $output_folder->share_with,
            @perms
        );

        return 1; # check_user_perms returns the first permission that failed
    }

    return 0;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.folder.create',
    method => 'create_folder'
);

sub create_folder {
    my( $self, $conn, $auth, $type, $folder ) = @_;

    my $e = new_rstore_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('RUN_REPORTS');
    return $e->die_event unless ($type ne 'template' || $e->allowed('CREATE_REPORT_TEMPLATE'));

    return 0 if $folder->owner ne $e->requestor->id;

    $folder->owner($e->requestor->id);
    my $meth = "create_reporter_${type}_folder";
    $e->$meth($folder) or return $e->die_event;
    $e->commit;

    return $folder->id;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.report.exists',
    method => 'report_exists',
    notes => q/
        Returns 1 if a report with the given name and folder already exists.
    /
);

sub report_exists {
    my( $self, $conn, $auth, $report ) = @_;

    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('RUN_REPORTS');

    my $existing = $e->search_reporter_report(
        {folder=>$report->folder, name=>$report->name});
    return 1 if @$existing;
    return 0;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.folder.visible.retrieve',
    method => 'retrieve_visible_folders'
);

sub retrieve_visible_folders {
    my( $self, $conn, $auth, $type ) = @_;
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    if($type eq 'output') {
        return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
    } else {
        return $e->event unless $e->allowed('RUN_REPORTS');
    }

    my $class = 'rrf';
    $class = 'rtf' if $type eq 'template';
    $class = 'rof' if $type eq 'output';
    my $flesh = {
        flesh => 1,
        flesh_fields => { $class => ['owner', 'share_with']},
        order_by => { $class => 'name ASC'}
    };

    my $meth = "search_reporter_${type}_folder";
    my $fs = $e->$meth( [{ owner => $e->requestor->id, simple_reporter => 'f' }, $flesh] );

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

__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.folder_data.retrieve.stream',
    method => 'retrieve_folder_data',
    stream => 1
);

sub retrieve_folder_data {
    my( $self, $conn, $auth, $type, $folderid, $limit, $offset, $order_by ) = @_;
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    if (!ref($folderid)) {
        $folderid = { folder => $folderid };
    }

    if($type eq 'output') {
        return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
    } else {
        return $e->event unless $e->allowed('RUN_REPORTS');
    }

    my $meth = "search_reporter_${type}";
    my $class = 'rr';
    $class = 'rt' if $type eq 'template';

    unless ($order_by) {
        $order_by = { $class => 'create_time DESC' };
    }

    my $flesh = {
        flesh => 1,
        flesh_fields => { $class => ['owner']},
        order_by => $order_by
    };
    $flesh->{limit} = $limit if $limit;
    $flesh->{offset} = $offset if $offset;

    my $list = $e->$meth([$folderid, $flesh]);
    if ($self->api_name =~ /stream$/) {
        $conn->respond($_) for @$list;
        return;
    }
    return $list;
}

__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.schedule.retrieve_by_folder',
    method => 'retrieve_schedules');
sub retrieve_schedules {
    my( $self, $conn, $auth, $folderId, $limit, $complete ) = @_;
    my $offset = 0;
    if (ref $limit) {
        $offset = $$limit{offset} || 0;
        $limit = $$limit{limit};
    }
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);

    my $search = ref($folderId) ? $folderId : { folder => $folderId };
    my $query = [
        $search,
        {
            order_by => { rs => 'run_time DESC' } ,
            flesh => 2,
            flesh_fields => { rs => ['report'], rr => ['template'] }
        }
    ];

    $query->[1]->{limit} = $limit if $limit;
    $query->[1]->{offset} = $offset if $offset;
    $query->[0]->{complete_time} = undef unless $complete;
    $query->[0]->{complete_time} = { '!=' => undef } if $complete;

    return $e->search_reporter_schedule($query);
}

__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.schedule.retrieve',
    method => 'retrieve_schedules');
sub retrieve_schedule {
    my( $self, $conn, $auth, $sched_id ) = @_;
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
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
    return $e->die_event unless $e->allowed('CREATE_REPORT_TEMPLATE');
    $template->owner($e->requestor->id);

    my $existing = $e->search_reporter_template( {owner=>$template->owner,
            folder=>$template->folder, name=>$template->name},{idlist=>1});
    return OpenILS::Event->new('REPORT_TEMPLATE_EXISTS') if @$existing;

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

    my $existing = $e->search_reporter_report( {owner=>$report->owner,
            folder=>$report->folder, name=>$report->name},{idlist=>1});
    return OpenILS::Event->new('REPORT_REPORT_EXISTS') if @$existing;

    my $rpt = $e->create_reporter_report($report)
        or return $e->die_event;
    $schedule->report($rpt->id);
    $schedule->runner($e->requestor->id);
    $e->create_reporter_schedule($schedule) or return $e->die_event;
    $e->commit;
    return $rpt;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.schedule.create',
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
    my( $self, $conn, $auth, $id, $opts ) = @_;
    $opts ||= {};
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
    my $t = $e->retrieve_reporter_template([$id,$opts])
        or return $e->event;
    return $t;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.report.retrieve',
    method => 'retrieve_report');
sub retrieve_report {
    my( $self, $conn, $auth, $id, $opts ) = @_;
    $opts ||= {};
    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
    my $r = $e->retrieve_reporter_report([$id,$opts])
        or return $e->event;
    return $r;
}

__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.report.fleshed.retrieve',
    method => 'retrieve_fleshed_report',
    signature => {
        desc => q/Returns report, fleshed with template, template.owner
        and schedules. Fleshes report.runs() as a single-item array 
        containing the most recently created reporter.schedule./
    }
);
sub retrieve_fleshed_report {
    my( $self, $conn, $auth, $id, $options ) = @_;
    $options ||= {};

    my $e = new_rstore_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed(['RUN_REPORTS','VIEW_REPORT_OUTPUT']);
    my $r = $e->retrieve_reporter_report([
        $id, {
        flesh => 2,
        flesh_fields => {
            rr => ['template'],
            rt => ['owner']
        }
    }]) or return $e->event;

    my $output = $e->search_reporter_schedule([
        {report => $id},
        {limit => 1, order_by => {rs => 'run_time DESC'}}
    ]);

    $r->runs($output);

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
    return $e->die_event unless $e->allowed('CREATE_REPORT_TEMPLATE');
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
    api_name => 'open-ils.reporter.schedule.update',
    method => 'update_schedule');
sub update_schedule {
    my( $self, $conn, $auth, $schedule ) = @_;
    my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('RUN_REPORTS');
    my $s = $e->retrieve_reporter_schedule($schedule->id)
        or return $e->die_event;
    my $r = $e->retrieve_reporter_report($s->report)
        or return $e->die_event;
    if( $r->owner ne $e->requestor->id ) {
        $e->rollback;
        return 0;
    }
    $e->update_reporter_schedule($schedule)
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
    api_name => 'open-ils.reporter.template.delete.cascade',
    method => 'cascade_delete_template');

#__PACKAGE__->register_method(
#   api_name => 'open-ils.reporter.template.delete.cascade.force',
#   method => 'cascade_delete_template');

sub cascade_delete_template {
    my( $self, $conn, $auth, $templateId ) = @_;

    my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('RUN_REPORTS');

    my $ret = cascade_delete_template_impl(
        $e, $e->requestor->id, $templateId, ($self->api_name =~ /force/o) );
    return $ret if ref $ret; # some fatal event occurred

    $e->rollback if $ret == 0;
    $e->commit if $ret > 0;
    return $ret;
}


__PACKAGE__->register_method(
    api_name => 'open-ils.reporter.report.delete.cascade',
    method => 'cascade_delete_report');

#__PACKAGE__->register_method(
#   api_name => 'open-ils.reporter.report.delete.cascade.force',
#   method => 'cascade_delete_report');

sub cascade_delete_report {
    my( $self, $conn, $auth, $reportId ) = @_;

    my $e = new_rstore_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('RUN_REPORTS');

    my $ret = cascade_delete_report_impl($e, $e->requestor->id, $reportId);
    return $ret if ref $ret; # some fatal event occurred

    $e->rollback if $ret == 0;
    $e->commit if $ret > 0;
    return $ret;
}


# performs a cascading template delete
# returns 2 if all data was deleted
# returns 1 if some data was deleted
# returns 0 if no data was deleted
# returns event on error
sub cascade_delete_template_impl {
    my( $e, $owner, $templateId ) = @_;

    # fetch the template to delete
    my $template = $e->search_reporter_template(
        {id=>$templateId, owner=>$owner})->[0] or return 0;

    # fetch he attached report IDs for this  owner
    my $reports = $e->search_reporter_report(
        {template=>$templateId, owner=>$owner},{idlist=>1});

    # delete the attached reports
    my $all_rpts_deleted = 1;
    for my $r (@$reports) {
        my $evt = cascade_delete_report_impl($e, $owner, $r);
        return $evt if ref $evt;
        $all_rpts_deleted = 0 unless $evt == 2;
    }

    # fetch all reports attached to this template that
    # do not belong to $owner.  If there are any, we can't
    # delete the template
    my $alt_reports = $e->search_reporter_report(
        {template=>$templateId, owner=>{"!=" => $owner}},{idlist=>1});

    # all_rpts_deleted will be false if a report has an
    # attached scheduled owned by a different user
    return 1 if @$alt_reports or not $all_rpts_deleted;

    $e->delete_reporter_template($template)
        or return $e->die_event;
    return 2;
}

# performs a cascading report delete
# returns 2 if all data was deleted
# returns 1 if some data was deleted
# returns 0 if no data was deleted
# returns event on error
sub cascade_delete_report_impl {
    my( $e, $owner, $reportId ) = @_;

    # fetch the report to delete
    my $report = $e->search_reporter_report(
        {id=>$reportId, owner=>$owner})->[0] or return 0;

    # fetch the attached schedule IDs for this owner
    my $scheds = $e->search_reporter_schedule(
        {report=>$reportId, runner=>$owner},{idlist=>1});

    # delete the attached schedules
    for my $sched (@$scheds) {
        my $evt = delete_schedule_impl($e, $sched);
        return $evt if $evt;
    }

    # fetch all schedules attached to this report that
    # do not belong to $owner.  If there are any, we can't
    # delete the report
    my $alt_scheds = $e->search_reporter_schedule(
        {report=>$reportId, runner=>{"!=" => $owner}},{idlist=>1});

    return 1 if @$alt_scheds;

    $e->delete_reporter_report($report)
        or return $e->die_event;

    return 2;
}


# deletes the requested schedule
# returns undef on success, event on error
sub delete_schedule_impl {
    my( $e, $schedId ) = @_;
    my $s = $e->retrieve_reporter_schedule($schedId)
        or return $e->die_event;
    $e->delete_reporter_schedule($s) or return $e->die_event;
    return undef;
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
    my $org_col = $$args{org_column};
    my $orgs = $$args{org};

#   if ($orgs && !$$args{no_fetch}) {
#       ($orgs) = $self
#               ->method_lookup( 'open-ils.reporter.org_unit.full_path' )
#               ->run( @$orgs );
#       $orgs = [ map {$_->id} @$orgs ];
#   }

    # Find the class the iplements the given hint
    my ($class) = grep {
        $Fieldmapper::fieldmap->{$_}{hint} eq $hint } Fieldmapper->classes;

    return undef unless $class->Selector;

    $class =~ s/Fieldmapper:://og;
    $class =~ s/::/_/og;

    my $method;
    my $margs;

    if( $org_col ) {
        $method = "search_$class";
        $margs = { $org_col => $orgs };
    } else {
        $method = "retrieve_all_$class";
    }

    $logger->info("reporter.magic_fetch => $method");

    return $e->$method($margs);
}

__PACKAGE__->register_method(
    method => 'search_templates',
    api_name => 'open-ils.reporter.search.templates',
    stream => 1
);

sub search_templates {
    my ($self, $client, $auth, $query_args) = @_;

    my $limit  = $query_args->{limit} || 100;
    my $offset = $query_args->{offset} || 0;
    my $folder = $query_args->{folder};
    my $fields = $query_args->{fields} || ['name','description'];
    my $query_string  = $query_args->{query};

    return undef unless $query_string;

    my $e = new_rstore_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my ($visible_folders) = $self
        ->method_lookup('open-ils.reporter.folder.visible.retrieve')
        ->run($auth, 'template');

    my @visible_folder_ids = map { $_->id } @$visible_folders; 

    return undef unless @$visible_folders;

    my $query = {
        select => {rt => ['id']},
        from => 'rt',
        where => {
            folder => \@visible_folder_ids,
            '-and' => []
        },
        limit => $limit,
        offset => $offset
    };

    if ($folder) { # search request for specific folder + sub-folders
        my ($root_folder) = grep { $_->id == $folder} @$visible_folders;

        return OpenILS::Event->new('BAD_PARAMS', 
            desc => q/Cannot search requested folder/) unless $root_folder;

        # find all folders that are descendants of the selected folder.
        my @ffilter;
        my $finder;
        $finder = sub {
            my $node = shift;
            return unless $node;
            push(@ffilter, $node->id);
            my @children = grep { $_->parent == $node->id } @$visible_folders;
            $finder->($_) for @children;
        };

        $finder->($root_folder);
        $query->{where}->{folder} = \@ffilter;
    }

    $query_string =~ s/^\s+|\s+$//gm; # remove open/trailing spaces
    my @query_parts = split(/ +/, $query_string);

    # Compile the query parts and searched fields down to a JSON-query
    # structure like this.  Note that single-field searches have no
    # nested -or's.
    # where => {
    #   -and => [
    #       {-or => [
    #           {$field1 => {~* => $value1}},
    #           {$field2 => {~* => $value1}}
    #       },
    #       {-or => [
    #           {$field1 => {~* => $value2}},
    #           {$field2 => {~* => $value2}}
    #       }
    #   ]
    #}
    for my $part (@query_parts) {
        my $subq;

        if (@$fields > 1) {
            $subq = {'-or' => []};
            for my $field (@$fields) {
                push(@{$subq->{'-or'}}, {$field => {'~*' => "(^|\\m)$part"}});
            }
        } else {
            $subq = {$fields->[0] => {'~*' => "(^|\\m)$part"}};
        }

        push(@{$query->{where}->{'-and'}}, $subq);
    }

    my $template_ids = $e->json_query($query);

    # Flesh template owner for consistency with retrieve_folder_data
    my $flesh = {flesh => 1, flesh_fields => {rt => ['owner','folder']}};

    $client->respond($e->retrieve_reporter_template([$_->{id}, $flesh])) 
        for @$template_ids;

    return;
}



1;
