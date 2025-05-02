#!/usr/bin/perl
# vim:ts=4:noet:

use strict;
use DBI;
use FileHandle;
use XML::LibXML;
use Getopt::Long;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Text::CSV_XS;
use Excel::Writer::XLSX;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:daemon/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Reporter::SQLBuilder;
use POSIX;
use GD::Graph::pie;
use GD::Graph::bars3d;
use GD::Graph::lines3d;
use Tie::IxHash;
use Email::Send;
use Scalar::Util 'looks_like_number';
use List::MoreUtils qw/uniq/;
use sigtrap qw/handler die_signal normal-signals/;

use open ':utf8';


my ($config, $sleep_interval, $lockfile, $daemon) = ('SYSCONFDIR/opensrf_core.xml', 10, 'LOCALSTATEDIR/run/reporter.pid');

my $opt_count;
my $opt_minimum_repsec_version;
my $opt_max_rows_for_charts;
my $opt_statement_timeout;
my $opt_resultset_limit;

# Process id of the first Clark started.  This is saved so that we can
# properly cleanup the lock file at the END.
my $main_pid;

GetOptions(
	"daemon"	=> \$daemon,
	"sleep=i"	=> \$sleep_interval,
	"concurrency=i"	=> \$opt_count,
	"max-rows-for-charts=i" => \$opt_max_rows_for_charts,
	"minimum-repsec-version=i" => \$opt_minimum_repsec_version,
	"resultset-limit=i" => \$opt_resultset_limit,
	"statement-timeout=i" => \$opt_statement_timeout,
	"bootstrap|boostrap=s"	=> \$config,
	"lockfile=s"	=> \$lockfile,
);

if (-e $lockfile) {
	die "I seem to be running already. If not, remove $lockfile and try again\n";
}

OpenSRF::System->bootstrap_client( config_file => $config );

my (%data_db, %state_db);

my $sc = OpenSRF::Utils::SettingsClient->new;
my $idl = $sc->config_value("IDL");
Fieldmapper->import(IDL => $idl);

$data_db{db_driver} = $sc->config_value( reporter => setup => database => 'driver' );
$data_db{db_host}   = $sc->config_value( reporter => setup => database => 'host' );
$data_db{db_port}   = $sc->config_value( reporter => setup => database => 'port' );
$data_db{db_name}   = $sc->config_value( reporter => setup => database => 'db' );
if (!$data_db{db_name}) {
    $data_db{db_name} = $sc->config_value( reporter => setup => database => 'name' );
    print STDERR "WARN: <database><name> is a deprecated setting for database name. For future compatibility, you should use <database><db> instead." if $data_db{db_name}; 
}
$data_db{db_user}   = $sc->config_value( reporter => setup => database => 'user' );
$data_db{db_pw}     = $sc->config_value( reporter => setup => database => 'pw' );
$data_db{db_app}    = $sc->config_value( reporter => setup => database => 'application_name' );



# Fetch the optional state database connection info
$state_db{db_driver} = $sc->config_value( reporter => setup => state_store => 'driver' ) || $data_db{db_driver};
$state_db{db_host}   = $sc->config_value( reporter => setup => state_store => 'host'   ) || $data_db{db_host};
$state_db{db_port}   = $sc->config_value( reporter => setup => state_store => 'port'   ) || $data_db{db_port};
$state_db{db_name}   = $sc->config_value( reporter => setup => state_store => 'db'     );
if (!$state_db{db_name}) {
    $state_db{db_name} = $sc->config_value( reporter => setup => state_store => 'name' ) || $data_db{db_name};
}
$state_db{db_user}   = $sc->config_value( reporter => setup => state_store => 'user'   ) || $data_db{db_user};
$state_db{db_pw}     = $sc->config_value( reporter => setup => state_store => 'pw'     ) || $data_db{db_pw};
$state_db{db_app}    = $sc->config_value( reporter => setup => state_store => 'application_name' )
                         || $data_db{db_app};


die "Unable to retrieve database connection information from the settings server"
    unless ($state_db{db_driver} && $state_db{db_host} && $state_db{db_port} && $state_db{db_name} && $state_db{db_user} &&
        $data_db{db_driver} && $data_db{db_host} && $data_db{db_port} && $data_db{db_name} && $data_db{db_user});

my $email_server     = $sc->config_value( email_notify => 'smtp_server' );
my $email_sender     = $sc->config_value( email_notify => 'sender_address' );
my $success_template = $sc->config_value( reporter => setup => files => 'success_template' );
my $fail_template    = $sc->config_value( reporter => setup => files => 'fail_template' );
my $output_base      = $sc->config_value( reporter => setup => files => 'output_base' );
my $base_uri         = $sc->config_value( reporter => setup => 'base_uri' );

my $state_dsn = "dbi:" . $state_db{db_driver} . ":dbname=" . $state_db{db_name} .';host=' . $state_db{db_host} . ';port=' . $state_db{db_port};
$state_dsn .= ";application_name='$state_db{db_app}'" if $state_db{db_app};
my $data_dsn  = "dbi:" .  $data_db{db_driver} . ":dbname=" .  $data_db{db_name} .';host=' .  $data_db{db_host} . ';port=' .  $data_db{db_port};
$data_dsn .= ";application_name='$data_db{db_app}'" if $data_db{db_app};

my $count               = $opt_count //
                          $sc->config_value( reporter => setup => 'parallel' ) //
                          1;
$count = 1 unless $count =~ /^\d+$/ && $count > 0;
my $statement_timeout   = $opt_statement_timeout //
                          $sc->config_value( reporter => setup => 'statement_timeout' ) //
                          60;
$statement_timeout = 60 unless $statement_timeout =~ /^\d+$/;
my $max_rows_for_charts = $opt_max_rows_for_charts //
                          $sc->config_value( reporter => setup => 'max_rows_for_charts' ) //
                          1000;
$max_rows_for_charts = 1000 unless $max_rows_for_charts =~ /^\d+$/;
my $resultset_limit     = $opt_resultset_limit //
                          $sc->config_value( reporter => setup => 'resultset_limit' ) //
                          0;
$resultset_limit = 0 unless $resultset_limit =~ /^\d+$/; # 0 means no limit
my $minimum_repsec_version = $opt_minimum_repsec_version //
                             $sc->config_value( reporter => setup => 'minimum_repsec_version' ) //
                             7;
$minimum_repsec_version = 7 unless $minimum_repsec_version =~ /^\d+$/; # 7 is the template version that introduced repsec functionality

# What follows is an emperically-derived magic number; if
# the row count is larger than this, the table-sorting JavaScript
# won't be loaded to excessive churn when viewing HTML reports
# in the staff client or web browser.
my $sortable_limit = 10000;

my ($dbh,$running,$sth,@reports,$run, $current_time);

if ($daemon) {
	daemonize("Clark Kent, waiting for trouble");
    $main_pid = $$ unless ($main_pid);
	open(F, ">$lockfile") or die "Cannot write lockfile '$lockfile'";
	print F $$;
	close F;
}


DAEMON:

$dbh = DBI->connect(
	$state_dsn,
	$state_db{db_user},
	$state_db{db_pw},
	{ AutoCommit => 1,
	  pg_expand_array => 0,
	  pg_enable_utf8 => 1,
	  RaiseError => 1
	}
);

$current_time = DateTime->from_epoch( epoch => time() )->strftime('%FT%T%z');

# make sure we're not already running $count reports
($running) = $dbh->selectrow_array(<<SQL);
SELECT	count(*)
  FROM	reporter.schedule
  WHERE	start_time IS NOT NULL AND complete_time IS NULL;
SQL

if ($count <= $running) {
	if ($daemon) {
		$dbh->disconnect;
		sleep 1;
		POSIX::waitpid( -1, POSIX::WNOHANG );
		sleep $sleep_interval;
		goto DAEMON;
	}
	print "Already running maximum ($running) concurrent reports\n";
	exit 1;
}

# if we have some open slots then generate the sql
$run = $count - $running;

$sth = $dbh->prepare(<<SQL);
SELECT	*
  FROM	reporter.schedule
  WHERE	start_time IS NULL AND run_time < NOW()
  ORDER BY run_time
  LIMIT $run;
SQL

$sth->execute;

@reports = ();
while (my $r = $sth->fetchrow_hashref) {
	my $s3 = $dbh->selectrow_hashref(<<"	SQL", {}, $r->{report});
		SELECT * FROM reporter.report WHERE id = ?;
	SQL

	my $s2 = $dbh->selectrow_hashref(<<"	SQL", {}, $s3->{template});
		SELECT * FROM reporter.template WHERE id = ?;
	SQL

	$s3->{template} = $s2;
	$r->{report} = $s3;

	my $b = OpenILS::Reporter::SQLBuilder->new;
	$b->minimum_repsec_version($minimum_repsec_version) if $minimum_repsec_version;
	$b->runner($r->{runner});

	my $report_data = OpenSRF::Utils::JSON->JSON2perl( $r->{report}->{data} );
	$b->register_params( $report_data );

	$r->{resultset} = $b->parse_report( OpenSRF::Utils::JSON->JSON2perl( $r->{report}->{template}->{data} ) );
	$r->{resultset}->set_do_rollup($report_data->{__do_rollup}) if $report_data->{__do_rollup};
	$r->{resultset}->set_pivot_data($report_data->{__pivot_data}) if $report_data->{__pivot_data};
	$r->{resultset}->set_pivot_label($report_data->{__pivot_label}) if $report_data->{__pivot_label};
	$r->{resultset}->set_pivot_default($report_data->{__pivot_default}) if $report_data->{__pivot_default};
	$r->{resultset}->set_record_bucket($report_data->{__record_bucket}) if defined $report_data->{__record_bucket};
	$r->{resultset}->set_bib_column_number($report_data->{__bib_column_number}) if defined $report_data->{__bib_column_number};
	$r->{resultset}->relative_time($r->{run_time});
	$r->{resultset}->resultset_limit($resultset_limit) if $resultset_limit;
	push @reports, $r;
}

$sth->finish;

$dbh->disconnect;

# Now we spawn the report runners

for my $r ( @reports ) {
	next if (safe_fork());

	# This is the child (runner) process;
	daemonize("Clark Kent reporting: $r->{report}->{name}");

	my $state_dbh = DBI->connect(
		$state_dsn,
		$state_db{db_user},
		$state_db{db_pw},
		{ AutoCommit => 1,
		  pg_expand_array => 0,
		  pg_enable_utf8 => 1,
		  RaiseError => 1
		}
	);

	my $data_dbh = DBI->connect(
		$data_dsn,
		$data_db{db_user},
		$data_db{db_pw},
		{ AutoCommit => 1,
		  pg_expand_array => 0,
		  pg_enable_utf8 => 1,
		  RaiseError => 1
		}
	);
	$data_dbh->do('SET statement_timeout = ?', {}, ($statement_timeout * 60 * 1000));

	try {
		$state_dbh->do(<<'		SQL',{}, $r->{id});
			UPDATE	reporter.schedule
			  SET	start_time = now()
			  WHERE	id = ?;
		SQL

		$logger->debug('Report SQL: ' . $r->{resultset}->toSQL);
		$sth = $data_dbh->prepare($r->{resultset}->toSQL);

		$sth->execute;
		$r->{data} = $sth->fetchall_arrayref;

		$r->{column_labels} = [$r->{resultset}->column_label_list];

		if ($r->{resultset}->pivot_data && $r->{resultset}->pivot_label) {
			my @labels = $r->{resultset}->column_label_list;
			my $newdata = pivot_data(
				{ columns => $r->{column_labels}, data => $r->{data}},
				$r->{resultset}->pivot_label,
				$r->{resultset}->pivot_data,
				$r->{resultset}->pivot_default
			);

			$r->{column_labels} = $newdata->{columns};
			$r->{data} = $newdata->{data};
			$r->{group_by_list} = $newdata->{group_by_list};
		} else {
			$r->{group_by_list} = [$r->{resultset}->group_by_list(0)];
		}

		my $s2 = $r->{report}->{template}->{id};
		my $s3 = $r->{report}->{id};
		my $output = $r->{id};

		mkdir($output_base);
		mkdir("$output_base/$s2");
		mkdir("$output_base/$s2/$s3");
		mkdir("$output_base/$s2/$s3/$output");
	
		my $output_dir = "$output_base/$s2/$s3/$output";

		if ( $r->{csv_format} ) {
			build_csv("$output_dir/report-data.csv", $r);
		}

		if ( $r->{excel_format} ) {
			build_excel("$output_dir/report-data.xlsx", $r);
		}

		build_html("$output_dir/report-data.html", $r);

        my $bibcol = $r->{resultset}->bib_column_number;
        my $colCount = scalar(@{$r->{column_labels}});
        $logger->debug("reporter: bibcol = $bibcol, colCount = $colCount");
        if ( defined $bibcol && $bibcol <= $colCount ) {

            if ( $r->{new_record_bucket} ) {
                $logger->debug("reporter: calling create_record_bucket");
                my $bucket_id = create_record_bucket(
                    $state_dbh,
                    $r->{report}->{owner},
                    $r->{report}->{name},
                    'Generated by report #' . $r->{report}->{id}
                );
                $logger->debug("reporter: calling populate_record_bucket");
                populate_record_bucket($state_dbh, $bucket_id, $bibcol, $r);
            }

            if ( $r->{existing_record_bucket} ) {
                my $bucket_id = $r->{resultset}->record_bucket;
                $logger->debug("reporter: calling populate_record_bucket");
                populate_record_bucket($state_dbh, $bucket_id, $bibcol, $r);
            }

        } else {
            if ( $r->{new_record_bucket} || $r->{existing_record_bucket} ) {
                $logger->error("reporter: Bib Id column position out of range.");
                throw Error::Simple("Error: Bib Id column position out of range.");
            }
        }

		$state_dbh->begin_work;

		if ($r->{report}->{recur} ) {
			my $sql = <<'			SQL';
				INSERT INTO reporter.schedule (
						report,
						folder,
						runner,
						run_time,
						email,
						csv_format,
						excel_format,
						html_format,
						chart_pie,
						chart_bar,
						chart_line )
					VALUES ( ?, ?, ?, ?::TIMESTAMPTZ + ?, ?, ?, ?, ?, ?, ?, ? );
			SQL

			my $prevP = $state_dbh->{PrintError};
			$state_dbh->{PrintError} = 0;
			if (!$state_dbh->do(
				$sql,
				{},
				$r->{report}->{id},
				$r->{folder},
				$r->{runner},
				$r->{run_time},
				$r->{report}->{recurrence},
				$r->{email},
				$r->{csv_format},
				$r->{excel_format},
				$r->{html_format},
				$r->{chart_pie},
				$r->{chart_bar},
				$r->{chart_line},
			)) {
				# Ignore duplicate key errors on reporter.schedule (err 7 is a fatal query error). Just look for the constraint name in the message to avoid l10n issues.
				warn($state_dbh->errstr()) unless $state_dbh->err() == 7 && $state_dbh->errstr() =~ m/rpt_sched_recurrence_once_idx/;
			}
			$state_dbh->{PrintError} = $prevP;
		}

		$state_dbh->do(<<'		SQL',{}, $r->{id});
			UPDATE	reporter.schedule
			  SET	complete_time = now()
			  WHERE	id = ?;
		SQL

		$state_dbh->commit;

		my $new_r = $state_dbh->selectrow_hashref(<<"		SQL", {}, $r->{id});
			SELECT * FROM reporter.schedule WHERE id = ?;
		SQL

		$r->{start_time}    = $new_r->{start_time};
		$r->{complete_time} = $new_r->{complete_time};

		if ($r->{email}) {
			send_success($r);
		}

	} otherwise {
		my $e = shift;
		$r->{error_text} = ''.$e;
		if (!$state_dbh->{AutoCommit}) {
			$state_dbh->rollback;
		}
		$state_dbh->do(<<'		SQL',{}, $e, $r->{id});
			UPDATE	reporter.schedule
			  SET	error_text = ?,
			  	complete_time = now(),
				error_code = 1
			  WHERE	id = ?;
		SQL

		my $new_r = $state_dbh->selectrow_hashref(<<"		SQL", {}, $r->{id});
			SELECT * FROM reporter.schedule WHERE id = ?;
		SQL

		$r->{error_text}    = $new_r->{error_text};
		$r->{complete_time} = $new_r->{complete_time};

		if ($r->{email}) {
			send_fail($r);
		}

	};

	$state_dbh->disconnect;
	$data_dbh->disconnect;

	exit; # leave the child
}

if ($daemon) {
	sleep 1;
	POSIX::waitpid( -1, POSIX::WNOHANG );
	sleep $sleep_interval;
	goto DAEMON;
}

#-------------------------------------------------------------------

sub send_success {
	my $r = shift;
	open F, $success_template or die "Cannot read '$success_template'";
	my $tmpl = join('',<F>);
	close F;

	my $url = $base_uri . '/' .
		$r->{report}->{template}->{id} . '/' .
		$r->{report}->{id} . '/' .
		$r->{id} . '/report-data.html';

	$tmpl =~ s/{TO}/$r->{email}/smog;
	$tmpl =~ s/{FROM}/$email_sender/smog;
	$tmpl =~ s/{REPLY_TO}/$email_sender/smog;
	$tmpl =~ s/{REPORT_NAME}/$r->{report}->{name} -- $r->{report}->{template}->{name}/smog;
	$tmpl =~ s/{RUN_TIME}/$r->{run_time}/smog;
	$tmpl =~ s/{COMPLETE_TIME}/$r->{complete_time}/smog;
	$tmpl =~ s/{OUTPUT_URL}/$url/smog;

	my $tdata = OpenSRF::Utils::JSON->JSON2perl( $r->{report}->{template}->{data} );
	if ($$tdata{version} >= 4) {
		$tmpl =~ s/{EXTERNAL_URL}/$$tdata{doc_url}/smog;
	}

	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => $email_server]);
	$sender->send($tmpl);
}

sub send_fail {
	my $r = shift;
	open F, $fail_template or die "Cannot read '$fail_template'";
	my $tmpl = join('',<F>);
	close F;

	my $sql = $r->{resultset}->toSQL;

	$tmpl =~ s/{TO}/$r->{email}/smog;
	$tmpl =~ s/{FROM}/$email_sender/smog;
	$tmpl =~ s/{REPLY_TO}/$email_sender/smog;
	$tmpl =~ s/{REPORT_NAME}/$r->{report}->{name} -- $r->{report}->{template}->{name}/smog;
	$tmpl =~ s/{RUN_TIME}/$r->{run_time}/smog;
	$tmpl =~ s/{ERROR_TEXT}/$r->{error_text}/smog;
	$tmpl =~ s/{SQL}/$sql/smog;

	my $tdata = OpenSRF::Utils::JSON->JSON2perl( $r->{report}->{template}->{data} );
	if ($$tdata{version} >= 4) {
		$tmpl =~ s/{EXTERNAL_URL}/$$tdata{doc_url}/smog;
	}

	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => $email_server]);
	$sender->send($tmpl);
}

sub generate_unique_bucket_name {
    my ($bucket_dbh, $base_name, $owner) = @_;
    my $name = $base_name;
    my $counter = 1;

    while (1) {
        my $exists = $bucket_dbh->selectrow_array("SELECT EXISTS (SELECT 1 FROM container.biblio_record_entry_bucket WHERE name = ? AND owner = ? AND btype = ?)", undef, $name, $owner, 'staff_client');
        last unless $exists;
        $name = $base_name . " (" . $counter++ . ")";
    }

    return $name;
}

sub create_record_bucket {
    my ($bucket_dbh, $owner, $name, $description) = @_;
    $logger->debug('reporter: creating record bucket');

    my $unique_name = generate_unique_bucket_name($bucket_dbh, $name, $owner);

    my $sql = 'INSERT INTO container.biblio_record_entry_bucket (owner, name, btype, description) VALUES (?, ?, ?, ?)';
    my $sth = $bucket_dbh->prepare($sql);
    $sth->execute($owner, $unique_name, 'staff_client', $description);

    # my $bucket_id = $bucket_dbh->last_insert_id(undef, "container", "biblio_record_entry_bucket", "id");
    my ($bucket_id) = $bucket_dbh->selectrow_array("SELECT currval('container.biblio_record_entry_bucket_id_seq')");

    $logger->debug("reporter: created record bucket with id $bucket_id");
    return $bucket_id;
}

sub check_record_bucket_exists {
    my ($bucket_dbh, $bucket_id) = @_;
    my $sth = $bucket_dbh->prepare("SELECT 1 FROM container.biblio_record_entry_bucket WHERE id = ?");
    $sth->execute($bucket_id);
    my ($exists) = $sth->fetchrow_array();
    return $exists ? 1 : 0;
}

sub get_max_pos {
    my ($bucket_dbh, $bucket_id) = @_;
    my $sth = $bucket_dbh->prepare("SELECT MAX(pos) FROM container.biblio_record_entry_bucket_item WHERE bucket = ?");
    $sth->execute($bucket_id);
    my ($max_pos) = $sth->fetchrow_array();
    return defined $max_pos ? $max_pos : 0;
}

sub filter_valid_bibs {
    my ($dbh, @bib_ids) = @_;
    return @bib_ids if scalar(@bib_ids) == 0;
    my $placeholders = join(',', ('?') x @bib_ids);  # Create a placeholder string
    my $sth = $dbh->prepare("SELECT id FROM biblio.record_entry WHERE id IN ($placeholders)");
    $sth->execute(@bib_ids);
    my %valid_bibs = map { $_->[0] => 1 } @{$sth->fetchall_arrayref};
    return keys %valid_bibs;  # Return list of valid bib IDs
}

sub report_invalid_bibs {
    my ($unique_bibs_ref, $valid_bibs_ref) = @_;
    my %valid_bibs = map { $_ => 1 } @$valid_bibs_ref;
    my @non_matching_bibs = grep { !$valid_bibs{$_} } @$unique_bibs_ref;

    if (@non_matching_bibs) {
        $logger->warn("reporter: Non-matching bib ids: " . join(", ", @non_matching_bibs));
    }
}

sub populate_record_bucket {
    my ($bucket_dbh, $bucket_id, $index0_bib_column_number, $r) = @_;
    $logger->debug("reporter: populating record bucket with id $bucket_id, using column $index0_bib_column_number");
    if (! check_record_bucket_exists($bucket_dbh, $bucket_id)) {
        $logger->debug("reporter: record bucket with id $bucket_id does not exist");
        return;
    }

    my $order = get_max_pos($bucket_dbh, $bucket_id); # we'll start our own pos for the inserts here

    my %unique_bibs; # we'll use the relative position as the value here

    my @original_bibs = uniq( map { $_->[$index0_bib_column_number] } @{$r->{data}} );

    foreach my $potential_bib_id (@original_bibs) {
        next unless $potential_bib_id && looks_like_number($potential_bib_id);
        next if exists $unique_bibs{$potential_bib_id};
        $unique_bibs{$potential_bib_id} = ++$order;
    }

    my @valid_bibs = filter_valid_bibs($bucket_dbh, keys %unique_bibs);

    report_invalid_bibs(\@original_bibs, \@valid_bibs);

    # Prepare the SQL statement outside the loop for efficiency
    my $sql = 'INSERT INTO container.biblio_record_entry_bucket_item (bucket, target_biblio_record_entry, pos) VALUES (?, ?, ?)';
    my $sth = $bucket_dbh->prepare($sql);

    # $bucket_dbh->begin_work; # if we want to wrap in a transaction
    my $error_count = 0;
    my @bibs_erred = ();
    foreach my $bib_id (@valid_bibs) {
        $logger->debug("reporter: adding bib $bib_id bucket $bucket_id in position $unique_bibs{$bib_id}");
        eval {
            $sth->execute($bucket_id, $bib_id, $unique_bibs{$bib_id});
        };
        if ($@) {
            push @bibs_erred, $bib_id; $error_count++;
            $logger->warn("Error inserting bib into bucket for record $bib_id: " . $DBI::errstr);
            # throw Error::Simple("Error inserting bib into bucket for record $record->[$index0_bib_column_number]: " . $DBI::errstr);
        }
    }
    if ($error_count) {
        # $bucket_dbh->rollback; # if we want to wrap in a transaction; place into loop for quicker exit
        $logger->warn("reporter: Errors inserting these bib ids: " . join(", ", @bibs_erred));
        throw Error::Simple("reporter: Errors inserting these bib ids: " . join(", ", @bibs_erred));
    }
    # $bucket_dbh->commit; # if we want to wrap in a transaction
    $logger->debug("reporter: finished with bucket population");
}

sub build_csv {
	my $file = shift;
	my $r = shift;

	my $csv = Text::CSV_XS->new({ always_quote => 1, eol => "\015\012" });

	return unless ($csv);
	
	my $f = new FileHandle (">$file") or die "Cannot write to '$file'";

	$csv->print($f, $r->{column_labels});
	$csv->print($f, $_) for (@{$r->{data}});

	$f->close;
}
sub build_excel {
	my $file = shift;
	my $r = shift;
	my $xls = Excel::Writer::XLSX->new($file);

	my $sheetname = substr($r->{report}->{name},0,30);
	$sheetname =~ s/\W/_/gos;
	
	my $sheet = $xls->add_worksheet($sheetname);
	# don't try to write formulas, just write anything that starts with = as a text cell
	$sheet->add_write_handler(qr/^=/, sub { return shift->write_string(@_); } );

	$sheet->write_row('A1', $r->{column_labels});

	$sheet->write_col('A2', $r->{data});

	$xls->close;
}

sub build_html {
	my $file = shift;
	my $r = shift;

	my $index = new FileHandle (">$file") or die "Cannot write to '$file'";

	my $tdata = OpenSRF::Utils::JSON->JSON2perl( $r->{report}->{template}->{data} );
	
	# index header
	print $index <<"	HEADER";
<html>
	<head>
		<meta charset='utf-8'>
		<title>$$r{report}{name}</title>
		<style>
			table { border-collapse: collapse; }
			th { background-color: lightgray; }
			td,th { border: solid black 1px; }
			* { font-family: sans-serif; font-size: 1rem; }
		</style>
	</head>
	<body>
		<center>
		<h2><u>$$r{report}{name}</u></h2>
		$$r{report}{description}<br/>
	HEADER

	if ($$tdata{version} >= 4 and $$tdata{doc_url}) {
		print $index "<a target='_blank' href='$$tdata{doc_url}'>External template documentation</a><br/>";
	}

	print $index "<br/><br/>";

	my @links;

    my $br4 = '<br/>' x 4;
	# add a link to the raw output html
	push @links, "<a href='report-data.html.raw.html'>Tabular Output</a>" if ($r->{html_format});

	# add a link to the CSV output
	push @links, "<a href='report-data.xlsx'>Excel Output</a>" if ($r->{excel_format});

	# add a link to the CSV output
	push @links, "<a href='report-data.csv'>CSV Output</a>" if ($r->{csv_format});

	# debugging output
	push @links, "<a href='report-data.html.debug.html'>Debugging Info</a>";

	my $debug = new FileHandle (">$file.debug.html") or die "Cannot write to '$file.debug.html'";
	print $debug "<html><head><meta charset='utf-8'><title>DEBUG: $$r{report}{name}</title></head><body>";

	{	no warnings;
		if ($$tdata{version} >= 4 and $$tdata{doc_url}) {
			print $debug "<b><a target='_blank' href='$$tdata{doc_url}'>External template documentation</a></b><br/><a href='report-data.html'>Back to output index</a><hr/>";
		}

		print $debug '<h1>Generated SQL</h1><pre>' . $r->{resultset}->toSQL() . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>Template</h1><pre>' . Dumper( $r->{report}->{template} ) . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>Template Data</h1><pre>' . Dumper( $tdata ) . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>Report Parameter</h1><pre>' . Dumper( $r->{report} ) . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>Report Parameter Data</h1><pre>' . Dumper( $tdata ) . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>Report Run Time</h1><pre>' . $r->{resultset}->relative_time . "</pre><a href='report-data.html'>Back to output index</a><hr/>";
		print $debug '<h1>OpenILS::Reporter::SQLBuilder::ResultSet Object</h1><pre>' . Dumper( $r->{resultset} ) . "</pre><a href='report-data.html'>Back to output index</a>";
	}

	print $debug '</body></html>';

	$debug->close;

	print $index join(' -- ', @links);
	print $index "$br4</center>";

	if ($r->{html_format}) {
		# create the raw output html file
		my $raw = new FileHandle (">$file.raw.html") or die "Cannot write to '$file.raw.html'";
		print $raw "<html><head><meta charset='utf-8'><title>$$r{report}{name}</title>";

		print $raw <<'		CSS';
			<style>
				table { border-collapse: collapse; }
				th { background-color: lightgray; }
				td,th { border: solid black 1px; }
				* { font-family: sans-serif; }
			</style>
			<link rel="stylesheet" href="/js/sortable/sortable-theme-minimal.css" />
		CSS

		print $raw "</head><body><a href='report-data.html'>Back to output index</a><br/><table class='sortable-theme-minimal' data-sortable>";

		{	no warnings;
			print $raw "<thead><tr><th>".join('</th><th>', @{$r->{column_labels}})."</th></tr></thead>\n<tbody>";
			print $raw "<tr><td>".join('</td><td>', @$_)."</td></tr>\n" for (@{$r->{data}});
		}

		print $raw '</tbody></table>';
		if (@{ $r->{data} } <= $sortable_limit) {
			print $raw '<script src="/js/sortable/sortable.min.js"></script>';
		}
		print $raw '</body></html>';
	
		$raw->close;
	}

	# Time for a pie chart
	if ($r->{chart_pie}) {
		if (scalar(@{$r->{data}}) > $max_rows_for_charts) {
			print $index "<strong>Report output has too many rows to make a pie chart</strong>$br4";
		} else {
			my $pics = draw_pie($r, $file);
			for my $pic (@$pics) {
				print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/>$br4";
			}
		}
	}

	print $index $br4;
	# Time for a bar chart
	if ($r->{chart_bar}) {
		if (scalar(@{$r->{data}}) > $max_rows_for_charts) {
			print $index "<strong>Report output has too many rows to make a bar chart</strong>$br4";
		} else {
			my $pics = draw_bars($r, $file);
			for my $pic (@$pics) {
				print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/>$br4";
			}
		}
	}

	print $index $br4;
	# Time for a bar chart
	if ($r->{chart_line}) {
		if (scalar(@{$r->{data}}) > $max_rows_for_charts) {
			print $index "<strong>Report output has too many rows to make a line chart</strong>$br4";
		} else {
			my $pics = draw_lines($r, $file);
			for my $pic (@$pics) {
				print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/>$br4";
			}
	    }
	}

	# and that's it!
	print $index '</body></html>';
	
	$index->close;
}

sub draw_pie {
	my $r = shift;
	my $file = shift;

	my $data = $r->{data};

	my @groups = @{ $r->{group_by_list} };
	
	my @values = (0 .. (scalar(@{$r->{column_labels}}) - 1));
	delete @values[@groups];

	#my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');
	
	my @pics;
	for my $vcol (@values) {
		next unless (defined $vcol);

		my @pic_data = ([],[]);
		for my $row (@$data) {
			next if (!defined($$row[$vcol]) || $$row[$vcol] == 0);
			my $val = $$row[$vcol];
			push @{$pic_data[0]}, join(" -- ", @$row[@groups])." ($val)";
			push @{$pic_data[1]}, $val;
		}

		next unless (@{$pic_data[0]});

		my $size = 300;
		my $split = int(scalar(@{$pic_data[0]}) / $size);
		my $last = scalar(@{$pic_data[0]}) % $size;

		for my $sub_graph (0 .. $split) {
			
			if ($sub_graph == $split) {
				$size = $last;
			}

			my @sub_data;
			for my $set (@pic_data) {
				push @sub_data, [ splice(@$set,0,$size) ];
			}

			my $pic = new GD::Graph::pie;

			$pic->set(
				label			=> $r->{column_labels}->[$vcol],
				start_angle		=> 180,
				legend_placement	=> 'R',
				#logo			=> $logo,
				#logo_position		=> 'TL',
				#logo_resize		=> 0.5,
				show_values		=> 1,
			);

			my $format = $pic->export_format;

			open(IMG, ">$file.pie.$vcol.$sub_graph.$format") or die "Cannot write '$file.pie.$vcol.$sub_graph.$format'";
			binmode IMG;

			my $forgetit = 0;
			try {
				$pic->plot(\@sub_data) or die $pic->error;
				print IMG $pic->gd->$format;
			} otherwise {
				my $e = shift;
				warn "Couldn't draw $file.pie.$vcol.$sub_graph.$format : $e";
				$forgetit = 1;
			};

			close IMG;


			push @pics,
				{ file => "pie.$vcol.$sub_graph.$format",
				  name => $r->{column_labels}->[$vcol].' (Pie)',
				} unless ($forgetit);

			last if ($sub_graph == $split);
		}

	}
	
	return \@pics;
}

sub draw_bars {
	my $r = shift;
	my $file = shift;
	my $data = $r->{data};

	#my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');

	my @groups = @{ $r->{group_by_list} };

	
	my @values = (0 .. (scalar(@{$r->{column_labels}}) - 1));
	splice(@values,$_,1) for (reverse @groups);

	my @pic_data;
	{	no warnings;
		for my $row (@$data) {
			push @{$pic_data[0]}, join(' -- ', @$row[@groups]);
		}
	}

	my @leg;
	my $set = 1;

	my %trim_candidates;

	my $max_y = 0;
	for my $vcol (@values) {
		next unless (defined $vcol);
		$pic_data[$set] ||= [];

		my $pos = 0;
		for my $row (@$data) {
			my $val = $$row[$vcol] ? $$row[$vcol] : 0;
			push @{$pic_data[$set]}, $val;
			$max_y = $val if ($val > $max_y);
			$trim_candidates{$pos}++ if ($val == 0);
			$pos++;
		}

		$set++;
	}
	my $set_count = scalar(@pic_data) - 1;
	my @trim_cols = grep { $trim_candidates{$_} == $set_count } keys %trim_candidates;

	my @new_data;
	my @use_me;
	my @no_use;
	my $set_index = 0;
	for my $dataset (@pic_data) {
		splice(@$dataset,$_,1) for (reverse sort @trim_cols);

		if (grep { $_ } @$dataset) {
			push @new_data, $dataset;
			push @use_me, $set_index if ($set_index > 0);
		} else {
			push @no_use, $set_index;
		}
		$set_index++;
		
	}

	return [] unless ($new_data[0] && @{$new_data[0]});

	for my $col (@use_me) {
		push @leg, $r->{column_labels}->[$values[$col - 1]];
	}

	my $w = 100 + 10 * scalar(@{$new_data[0]});
	$w = 400 if ($w < 400);

	my $h = 10 * (scalar(@new_data) / 2);

	$h = 0 if ($h < 0);

	my $pic = new GD::Graph::bars3d ($w + 250, $h + 500);

	$pic->set(
		title			=> $r->{report}{name},
		x_labels_vertical	=> 1,
		shading			=> 1,
		bar_depth		=> 5,
		bar_spacing		=> 2,
		y_max_value		=> $max_y,
		legend_placement	=> 'TR',
		boxclr			=> 'lgray',
		#logo			=> $logo,
		#logo_position		=> 'R',
		#logo_resize		=> 0.5,
		show_values		=> 1,
		overwrite		=> 1,
	);
	$pic->set_legend(@leg);

	my $format = $pic->export_format;

	open(IMG, ">$file.bar.$format") or die "Cannot write '$file.bar.$format'";
	binmode IMG;

	try {
		$pic->plot(\@new_data) or die $pic->error;
		print IMG $pic->gd->$format;
	} otherwise {
		my $e = shift;
		warn "Couldn't draw $file.bar.$format : $e";
	};

	close IMG;

	return [{ file => "bar.$format",
		  name => $r->{report}{name}.' (Bar)',
		}];

}

sub draw_lines {
	my $r    = shift;
	my $file = shift;
	my $data = $r->{data};

	#my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');

	my @groups = @{ $r->{group_by_list} };
	
	my @values = (0 .. (scalar(@{$r->{column_labels}}) - 1));
	splice(@values,$_,1) for (reverse @groups);

	my @pic_data;
	{	no warnings;
		for my $row (@$data) {
			push @{$pic_data[0]}, join(' -- ', @$row[@groups]);
		}
	}

	my @leg;
	my $set = 1;

	my $max_y = 0;
	for my $vcol (@values) {
		next unless (defined $vcol);
		$pic_data[$set] ||= [];


		for my $row (@$data) {
			my $val = $$row[$vcol] ? $$row[$vcol] : 0;
			push @{$pic_data[$set]}, $val;
			$max_y = $val if ($val > $max_y);
		}

		$set++;
	}
	my $set_count = scalar(@pic_data) - 1;

	my @new_data;
	my @use_me;
	my @no_use;
	my $set_index = 0;
	for my $dataset (@pic_data) {

		if (grep { $_ } @$dataset) {
			push @new_data, $dataset;
			push @use_me, $set_index if ($set_index > 0);
		} else {
			push @no_use, $set_index;
		}
		$set_index++;
		
	}

	return [] unless ($new_data[0] && @{$new_data[0]});

	for my $col (@use_me) {
		push @leg, $r->{column_labels}->[$values[$col - 1]];
	}

	my $w = 100 + 10 * scalar(@{$new_data[0]});
	$w = 400 if ($w < 400);

	my $h = 10 * (scalar(@new_data) / 2);

	$h = 0 if ($h < 0);

	my $pic = new GD::Graph::lines3d ($w + 250, $h + 500);

	$pic->set(
		title			=> $r->{report}{name},
		x_labels_vertical	=> 1,
		shading			=> 1,
		line_depth		=> 5,
		y_max_value		=> $max_y,
		legend_placement	=> 'TR',
		boxclr			=> 'lgray',
		#logo			=> $logo,
		#logo_position		=> 'R',
		#logo_resize		=> 0.5,
		show_values		=> 1,
		overwrite		=> 1,
	);
	$pic->set_legend(@leg);

	my $format = $pic->export_format;

	open(IMG, ">$file.line.$format") or die "Cannot write '$file.line.$format'";
	binmode IMG;

	try {
		$pic->plot(\@new_data) or die $pic->error;
		print IMG $pic->gd->$format;
	} otherwise {
		my $e = shift;
		warn "Couldn't draw $file.line.$format : $e";
	};

	close IMG;

	return [{ file => "line.$format",
		  name => $r->{report}{name}.' (Bar)',
		}];

}


sub pivot_data {
	my $blob        = shift;
	my $pivot_label = shift;
	my $pivot_data  = shift;
	my $default     = shift;
	$default = 0 unless (defined $default);

	my $data = $$blob{data};
	my $cols = $$blob{columns};

	my @keep_labels =  @$cols;
	splice(@keep_labels, $_ - 1, 1) for (reverse sort ($pivot_label, $pivot_data));

	my @keep_cols = (0 .. @$cols - 1);
	splice(@keep_cols, $_ - 1, 1) for (reverse sort ($pivot_label, $pivot_data));

	my @gb = ( 0 .. @keep_cols - 1);

	#first, find the unique list of pivot values
	my %tmp;
	for my $row (@$data) {
		$tmp{ $$row[$pivot_label - 1] } = 1;
	}
	my @new_cols = sort keys %tmp;

	tie my %split_data, 'Tie::IxHash';
	for my $row (@$data) {

		my $row_fp = ''. join('', map { defined($$row[$_]) ? $$row[$_] : '' } @keep_cols);
		$split_data{$row_fp} ||= [];

		push @{ $split_data{$row_fp} }, $row;
	}


	#now loop over the data, building a new result set
	tie my %new_data, 'Tie::IxHash';

	for my $fp ( keys %split_data ) {

		$new_data{$fp} = [];

		for my $col (@keep_cols) {
			push @{ $new_data{$fp} }, $split_data{$fp}[0][$col];
		}

		for my $col (@new_cols) {

			my ($datum) = map { $_->[$pivot_data - 1] } grep { $_->[$pivot_label - 1] eq $col } @{ $split_data{$fp} };
			$datum ||= $default;
			push @{ $new_data{$fp} }, $datum;
		}
	}

	push @keep_labels, @new_cols;

	return { columns => \@keep_labels, data => [ values %new_data ], group_by_list => \@gb };
}


sub die_signal {
    my $sig = shift;
    $logger->warn("Reporter received signal $sig");
    exit(0);
}

END {
    unlink $lockfile if ($$ == $main_pid);
}
