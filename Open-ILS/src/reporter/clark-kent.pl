#!/usr/bin/perl -w

use strict;
use DBI;
use FileHandle;
use XML::LibXML;
use Getopt::Long;
use DateTime;
use DateTime::Format::ISO8601;
use JSON;
use Data::Dumper;
use OpenILS::WWW::Reporter::transforms;
use Text::CSV_XS;
use Spreadsheet::WriteExcel;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:daemon/;
use OpenSRF::Utils::Logger qw/:level/;

my $current_time = DateTime->from_epoch( epoch => time() )->strftime('%FT%T%z');

my ($base_xml, $count, $daemon) = ('/openils/conf/reporter.xml', 1);

GetOptions(
	"file=s"	=> \$base_xml,
	"daemon"	=> \$daemon,
	"concurrency=i"	=> \$count,
);

my $parser = XML::LibXML->new;
$parser->expand_xinclude(1);

my $doc = $parser->parse_file($base_xml);

my $db_driver = $doc->findvalue('/reporter/setup/database/driver');
my $db_host = $doc->findvalue('/reporter/setup/database/host');
my $db_name = $doc->findvalue('/reporter/setup/database/name');
my $db_user = $doc->findvalue('/reporter/setup/database/user');
my $db_pw = $doc->findvalue('/reporter/setup/database/password');

my $dsn = "dbi:" . $db_driver . ":dbname=" . $db_name .';host=' . $db_host;

my $dbh;

daemonize("Clark Kent, waiting for trouble") if ($daemon);

DAEMON:

$dbh = DBI->connect($dsn,$db_user,$db_pw);

# Move new reports into the run queue
$dbh->do(<<'SQL', {}, $current_time);
INSERT INTO reporter.output ( stage3, state ) 
	SELECT	id, 'wait'
	  FROM	reporter.stage3 
	  WHERE	runtime <= $1
	  	AND (	( 	recurrence = '0 seconds'::INTERVAL
				AND id NOT IN ( SELECT stage3 FROM reporter.output ) )
	  		OR (	recurrence > '0 seconds'::INTERVAL
				AND id NOT IN (
					SELECT	stage3
					  FROM	reporter.output
					  WHERE	state <> 'complete')
			)
		)
	  ORDER BY runtime;
SQL

# make sure we're not already running $count reports
my ($running) = $dbh->selectrow_array(<<SQL);
SELECT	count(*)
  FROM	reporter.output
  WHERE	state = 'running';
SQL

if ($count <= $running) {
	print "Already running maximum ($running) concurrent reports\n";
	exit 1;
}

# if we have some open slots then generate the sql
my $run = $count - $running;

my $sth = $dbh->prepare(<<SQL);
SELECT	*
  FROM	reporter.output
  WHERE	state = 'wait'
  ORDER BY queue_time
  LIMIT $run;
SQL

$sth->execute;

my @reports;
while (my $r = $sth->fetchrow_hashref) {
	my $s3 = $dbh->selectrow_hashref(<<"	SQL", {}, $r->{stage3});
		SELECT * FROM reporter.stage3 WHERE id = ?;
	SQL

	my $s2 = $dbh->selectrow_hashref(<<"	SQL", {}, $s3->{stage2});
		SELECT * FROM reporter.stage2 WHERE id = ?;
	SQL

	$s3->{stage2} = $s2;
	$r->{stage3} = $s3;

	generate_query( $r );
	push @reports, $r;
}

$sth->finish;

$dbh->disconnect;

# Now we spaun the report runners

for my $r ( @reports ) {
	next if (safe_fork());

	# This is the child (runner) process;
	my $p = JSON->JSON2perl( $r->{stage3}->{params} );
	daemonize("Clark Kent reporting: $p->{reportname}");

	$dbh = DBI->connect($dsn,$db_user,$db_pw);

	try {

		$dbh->do(<<'		SQL',{}, $r->{sql}->{'select'}, $$, $r->{id});
			UPDATE	reporter.output
			  SET	state = 'running',
			  	run_time = 'now',
				query = ?,
			  	run_pid = ?
			  WHERE	id = ?;
		SQL

		$sth = $dbh->prepare($r->{sql}->{'select'});

		$sth->execute(@{ $r->{sql}->{'bind'} });
		$r->{data} = $sth->fetchall_arrayref;

		my $base = $doc->findvalue('/reporter/setup/files/output_base');
		my $s1 = $r->{stage3}->{stage2}->{stage1};
		my $s2 = $r->{stage3}->{stage2}->{id};
		my $s3 = $r->{stage3}->{id};
		my $output = $r->{id};

		mkdir($base);
		mkdir("$base/$s1");
		mkdir("$base/$s1/$s2");
		mkdir("$base/$s1/$s2/$s3");
		mkdir("$base/$s1/$s2/$s3/$output");
	
		my @formats;
		if (ref $p->{output_format}) {
			@formats = @{ $p->{output_format} };
		} else {
			@formats = ( $p->{output_format} );
		}
	
		if ( grep { $_ eq 'csv' } @formats ) {
			build_csv("$base/$s1/$s2/$s3/$output/report-data.csv", $r);
		}
		
		if ( grep { $_ eq 'excel' } @formats ) {
			build_excel("$base/$s1/$s2/$s3/$output/report-data.xls", $r);
		}
		
		if ( grep { $_ eq 'html' } @formats ) {
			mkdir("$base/$s1/$s2/$s3/$output/html");
			build_html("$base/$s1/$s2/$s3/$output/report-data.html", $r);
		}


		$dbh->begin_work;
		$dbh->do(<<'		SQL',{}, $r->{stage3}->{id});
			UPDATE	reporter.stage3
			  SET	runtime = runtime + recurrence
			  WHERE	id = ? AND recurrence > '0 seconds'::INTERVAL;
		SQL
		$dbh->do(<<'		SQL',{}, $r->{id});
			UPDATE	reporter.output
			  SET	state = 'complete',
			  	complete_time = 'now'
			  WHERE	id = ?;
		SQL
		$dbh->commit;


	} otherwise {
		my $e = shift;
		$dbh->rollback;
		$dbh->do(<<'		SQL',{}, $e, $r->{id});
			UPDATE	reporter.output
			  SET	state = 'error',
			  	error_time = 'now',
				error = ?,
			  	run_pid = NULL
			  WHERE	id = ?;
		SQL
	};

	$dbh->disconnect;

	exit; # leave the child
}

if ($daemon) {
	sleep 60;
	goto DAEMON;
}

#-------------------------------------------------------------------

sub build_csv {
	my $file = shift;
	my $r = shift;

	my $csv = Text::CSV_XS->new({ always_quote => 1, eol => "\015\012" });
	my $f = new FileHandle (">$file");

	$csv->print($f, $r->{sql}->{columns});
	$csv->print($f, $_) for (@{$r->{data}});

	$f->close;
}
sub build_excel {
	my $file = shift;
	my $r = shift;
	my $p = JSON->JSON2perl( $r->{stage3}->{params} );

	my $xls = Spreadsheet::WriteExcel->new($file);
	my $sheet = $xls->add_worksheet($p->{reportname});

	$sheet->write_row('A1', $r->{sql}->{columns});

	$sheet->write_col('A2', $r->{data});

	$xls->close;
}

sub build_html {}

sub table_by_id {
	my $id = shift;
	my ($node) = $doc->findnodes("//*[\@id='$id']");
	if ($node && $node->findvalue('@table')) {
		($node) = $doc->findnodes("//*[\@id='".$node->getAttribute('table')."']");
	}
	return $node;
}

sub generate_query {
	my $r = shift;

	my $p = JSON->JSON2perl( $r->{stage3}->{params} );

	my @group_by;
	my @aggs;
	my $core = $r->{stage3}->{stage2}->{stage1};
	my @dims;

	for my $t (keys %{$$p{filter}}) {
		if ($t ne $core) {
			push @dims, $t;
		}
	}

	for my $t (keys %{$$p{output}}) {
		if ($t ne $core && !grep { $t } @dims ) {
			push @dims, $t;
		}
	}

	my @dim_select;
	my @dim_from;
	for my $d (@dims) {
		my $t = table_by_id($d);
		my $t_name = $t->findvalue('tablename');
		push @dim_from, "$t_name AS \"$d\"";

		my $k = $doc->findvalue("//*[\@id='$d']/\@key");
		push @dim_select, "\"$d\".\"$k\" AS \"${d}_${k}\"";

		for my $c ( keys %{$$p{output}{$d}} ) {
			push @dim_select, "\"$d\".\"$c\" AS \"${d}_${c}\"";
		}

		for my $c ( keys %{$$p{filter}{$d}} ) {
			next if (exists $$p{output}{$d}{$c});
			push @dim_select, "\"$d\".\"$c\" AS \"${d}_${c}\"";
		}
	}

	my $d_select =
		'(SELECT ' . join(',', @dim_select) .
		'  FROM ' . join(',', @dim_from) . ') AS dims';
	
	my @output_order = map { { (split ':')[1] => (split ':')[2] } } @{ $$p{output_order} };
	
	my $col = 1;
	my @groupby;
	my @output;
	my @columns;
	my @join;
	my @join_base;
	for my $pair (@output_order) {
		my ($t_name) = keys %$pair;
		my $t = $t_name;

		$t_name = "dims" if ($t ne $core);

		my $t_node = table_by_id($t);

		for my $c ( values %$pair ) {
			my $label = $t_node->findvalue("fields/field[\@name='$c']/label");

			my $full_col = $c;
			$full_col = "${t}_${c}" if ($t ne $t_name);
			$full_col = "\"$t_name\".\"$full_col\"";

			
			if (my $xform_type = $$p{xform}{type}{$t}{$c}) {
				my $xform = $$OpenILS::WWW::Reporter::dtype_xforms{$xform_type};
				if ($xform->{group}) {
					push @groupby, $col;
				}
				$label = "$$xform{label} -- $label";

				my $tmp = $xform->{'select'};
				$tmp =~ s/\?COLNAME\?/$full_col/gs;
				$tmp =~ s/\?PARAM\?/$$p{xform}{param}{$t}{$c}/gs;
				$full_col = $tmp;
			} else {
				push @groupby, $col;
			}

			push @output, "$full_col AS \"$label\"";
			push @columns, $label;
			$col++;
		}

		if ($t ne $t_name && (!@join_base || !grep{$t eq $_}@join_base)) {
			my $k = $doc->findvalue("//*[\@id='$t']/\@key");
			my $f = $doc->findvalue("//*[\@id='$t']/\@field");
			push @join, "dims.\"${t}_${k}\" = \"$core\".\"$f\"";
			push @join_base, $t;
		}
	}

	my @where;
	my @bind;
	for my $t ( keys %{$$p{filter}} ) {
		my $t_name = $t;
		$t_name = "dims" if ($t ne $core);

		my $t_node = table_by_id($t);

		for my $c ( keys %{$$p{filter}{$t}} ) {
			my $label = $t_node->findvalue("fields/field[\@name='$c']/label");

			my $full_col = $c;
			$full_col = "${t}_${c}" if ($t ne $t_name);
			$full_col = "\"$t_name\".\"$full_col\"";

			# XXX make this use widget specific code

			my ($fam) = keys %{ $$p{filter}{$t}{$c} };
			my ($w) = keys %{ $$p{filter}{$t}{$c}{$fam} };
			my $val = $$p{filter}{$t}{$c}{$fam}{$w};

			if (ref $val) {
				push @where, "$full_col IN (".join(",",map {'?'}@$val).")";
				push @bind, @$val;
			} else {
				push @where, "$full_col = ?";
				push @bind, $val;
			}
		}

		if ($t ne $t_name && (!@join_base || !grep{$t eq $_}@join_base)) {
			my $k = $doc->findvalue("//*[\@id='$t']/\@key");
			my $f = $doc->findvalue("//*[\@id='$t']/\@field");
			push @join, "dims.\"${t}_${k}\" = \"$core\".\"$f\"";
			push @join_base, $t;
		}
	}

	my $t = table_by_id($core)->findvalue('tablename');
	my $from = " FROM $t AS \"$core\" RIGHT JOIN $d_select ON (". join(' AND ', @join).")";
	my $select =
		"SELECT ".join(',', @output).
		  $from.
		  ' WHERE '.join(' AND ', @where).
		  ' GROUP BY '.join(',',@groupby);

	$r->{sql}->{'select'}	= $select;
	$r->{sql}->{'bind'}	= \@bind;
	$r->{sql}->{columns}	= \@columns;
	
}






