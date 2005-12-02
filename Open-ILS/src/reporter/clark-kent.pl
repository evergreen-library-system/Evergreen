#!/usr/bin/perl -w

use strict;
use diagnostics;
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
use POSIX;
use GD::Graph::pie;
use GD::Graph::bars3d;
use GD::Graph::lines3d;

use open ':utf8';


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

my ($dbh,$running,$sth,@reports,$run, $current_time);

daemonize("Clark Kent, waiting for trouble") if ($daemon);

DAEMON:

$dbh = DBI->connect($dsn,$db_user,$db_pw, {pg_enable_utf8 => 1, RaiseError => 1});

$current_time = DateTime->from_epoch( epoch => time() )->strftime('%FT%T%z');
# Move new reports into the run queue
$dbh->do(<<'SQL', {}, $current_time);
INSERT INTO reporter.output ( stage3, state ) 
	SELECT	id, 'wait'
	  FROM	reporter.stage3 
	  WHERE	runtime <= $1
	  	AND (	( 	recurrence = '0 seconds'::INTERVAL
				AND (
					id NOT IN ( SELECT stage3 FROM reporter.output )
					OR rerun IS TRUE
				)
			)
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
($running) = $dbh->selectrow_array(<<SQL);
SELECT	count(*)
  FROM	reporter.output
  WHERE	state = 'running';
SQL

if ($count <= $running) {
	if ($daemon) {
		$dbh->disconnect;
		sleep 1;
		POSIX::waitpid( -1, POSIX::WNOHANG );
		sleep 60;
		goto DAEMON;
	}
	print "Already running maximum ($running) concurrent reports\n";
	exit 1;
}

# if we have some open slots then generate the sql
$run = $count - $running;

$sth = $dbh->prepare(<<SQL);
SELECT	*
  FROM	reporter.output
  WHERE	state = 'wait'
  ORDER BY queue_time
  LIMIT $run;
SQL

$sth->execute;

@reports = ();
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

	$dbh = DBI->connect($dsn,$db_user,$db_pw, {pg_enable_utf8 => 1, RaiseError => 1});

	try {
		$dbh->do(<<'		SQL',{}, $r->{sql}->{'select'}, $$, $r->{id});
			UPDATE	reporter.output
			  SET	state = 'running',
			  	run_time = 'now',
				query = ?,
			  	run_pid = ?
			  WHERE	id = ?;
		SQL

		my ($runtime) = $dbh->selectrow_array("SELECT run_time FROM reporter.output WHERE id = ?",{},$r->{id});
		$r->{run_time} = $runtime;

		$sth = $dbh->prepare($r->{sql}->{'select'});

		$sth->execute(@{ $r->{sql}->{'bind'} });
		$r->{data} = $sth->fetchall_arrayref;

		pivot_data($r);

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
		$dbh->do(<<'		SQL',{}, $r->{run_time}, $r->{stage3}->{id});
			UPDATE	reporter.stage3
			  SET	runtime = CAST(? AS TIMESTAMP WITH TIME ZONE) + recurrence
			  WHERE	id = ? AND recurrence > '0 seconds'::INTERVAL;
		SQL
		$dbh->do(<<'		SQL',{}, $r->{stage3}->{id});
			UPDATE	reporter.stage3
			  SET	rerun = FALSE
			  WHERE	id = ? AND rerun = TRUE;
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
	sleep 1;
	POSIX::waitpid( -1, POSIX::WNOHANG );
	sleep 60;
	goto DAEMON;
}

#-------------------------------------------------------------------

sub pivot_data {
	my $r = shift;
	my $p = JSON->JSON2perl( $r->{stage3}->{params} );
	my $settings = $r->{sql};
	my $data = $r->{data};

	return unless (defined($settings->{pivot}));

	my @groups = (map { ($_ - 1) } @{ $settings->{groupby} });
	my @values = (0 .. (scalar(@{$settings->{columns}}) - 1));
	splice(@values,$_,1) for (reverse @groups);

	# remove pivot from group-by
	my $count = 0;
	my $pivot_groupby;
	while ($count < scalar(@{$settings->{groupby}})) {
		if (defined $pivot_groupby) {
			$settings->{groupby}->[$count] -= 1;
			if ($settings->{groupby}->[$count] >= $values[0] + 1) {
				$settings->{groupby}->[$count] -= 1;
			}
		} elsif ($settings->{groupby}->[$count] == $settings->{pivot} + 1) {
			$pivot_groupby = $count;
		}
		$count++;
	}


	# grab positions of non-group-bys
	@values = (0 .. (scalar(@{$settings->{columns}}) - 1));
	splice(@values,$_,1) for (reverse @groups);
	
	# we're only doing one "value" for now, so grab that and remove from headings
	my ($val_col) = @values;

	my @remove_me = sort
		{ $b <=> $a }
		($val_col, $settings->{groupby}->[$pivot_groupby] - 1);

	my %p_header;
	for my $row (@$data) {
		$p_header{ $$row[$settings->{pivot}] } = [] unless exists($p_header{ $$row[$settings->{pivot}] });
		
		push @{ $p_header{ $$row[$settings->{pivot}] } }, $$row[$val_col];
		
		splice(@$row,$_,1) for (@remove_me);
	}

	push @{ $settings->{columns} }, sort keys %p_header;

	# remove from headings;
	splice(@{$settings->{columns}},$_,1) for (@remove_me);

	# remove pivot from groupby
	splice(@{$settings->{groupby}}, $pivot_groupby, 1);
	@groups = (map { ($_ - 1) } @{ $settings->{groupby} });

	$count = scalar(keys %p_header);
	my %seenit;
	my @new_data;
	{	no warnings;
		for my $row (@$data) {

			my $fingerprint = join('',@$row[@groups]);
			next if $seenit{$fingerprint};

			$seenit{$fingerprint}++;

			for my $h ( sort keys %p_header ) {
				push @$row, shift(@{ $p_header{$h} });
			}

			push @new_data, [@$row];
		}
	}

	#replace old data with new
	$r->{data} = \@new_data;

}

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

	my $sheetname = substr($p->{reportname},1,31);
	$sheetname =~ s/\W/_/gos;
	
	my $sheet = $xls->add_worksheet($sheetname);

	$sheet->write_row('A1', $r->{sql}->{columns});

	$sheet->write_col('A2', $r->{data});

	$xls->close;
}

sub build_html {
	my $file = shift;
	my $r = shift;
	my $p = JSON->JSON2perl( $r->{stage3}->{params} );

	my $index = new FileHandle (">$file");
	my $raw = new FileHandle (">$file.raw.html");
	
	# index header
	print $index <<"	HEADER";
<html>
	<head>
		<title>$$p{reportname}</title>
		<style>
			table { border-collapse: collapse; }
			th { background-color: lightgray; }
			td,th { border: solid black 1px; }
			* { font-family: sans-serif; font-size: 10px; }
		</style>
	</head>
	<body>
		<h2><u>$$p{reportname}</u></h2>
	HEADER

	
	# add a link to the raw output html
	print $index "<a href='report-data.html.raw.html'>Raw output data</a><br/><br/><br/><br/>";

	# create the raw output html file
	print $raw "<html><head><title>$$p{reportname}</title>";

	print $raw <<'	CSS';
		<style>
			table { border-collapse: collapse; }
			th { background-color: lightgray; }
			td,th { border: solid black 1px; }
			* { font-family: sans-serif; font-size: 10px; }
		</style>
	CSS

	print $raw "</head><body><table>";

	{	no warnings;
		print $raw "<tr><th>".join('</th><th>',@{$r->{sql}->{columns}}).'</th></tr>';
		print $raw "<tr><td>".join('</td><td>',@$_                    ).'</td></tr>' for (@{$r->{data}});
	}

	print $raw '</table></body></html>';
	
	$raw->close;

	# get the graph types
	my @graphs;
	if (ref $$p{html_graph_type}) {
		@graphs = @{ $$p{html_graph_type} };
	} else {
		@graphs = ( $$p{html_graph_type} );
	}

	# Time for a pie chart
	if (grep {$_ eq 'pie'} @graphs) {
		my $pics = draw_pie($r, $p, $file);
		for my $pic (@$pics) {
			print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/><br/><br/><br/><br/>";
		}
	}

	print $index '<br/><br/><br/><br/>';
	# Time for a bar chart
	if (grep {$_ eq 'bar'} @graphs) {
		my $pics = draw_bars($r, $p, $file);
		for my $pic (@$pics) {
			print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/><br/><br/><br/><br/>";
		}
	}

	print $index '<br/><br/><br/><br/>';
	# Time for a bar chart
	if (grep {$_ eq 'line'} @graphs) {
		my $pics = draw_lines($r, $p, $file);
		for my $pic (@$pics) {
			print $index "<img src='report-data.html.$pic->{file}' alt='$pic->{name}'/><br/><br/><br/><br/>";
		}
	}


	# and that's it!
	print $index '</body></html>';
	
	$index->close;
}

sub draw_pie {
	my $r = shift;
	my $p = shift;
	my $file = shift;
	my $data = $r->{data};
	my $settings = $r->{sql};

	my @groups = (map { ($_ - 1) } @{ $settings->{groupby} });
	
	my @values = (0 .. (scalar(@{$settings->{columns}}) - 1));
	delete @values[@groups];

	my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');
	
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
				label			=> $settings->{columns}->[$vcol],
				start_angle		=> 180,
				legend_placement	=> 'R',
				logo			=> $logo,
				logo_position		=> 'TL',
				logo_resize		=> 0.5,
				show_values		=> 1,
			);

			my $format = $pic->export_format;

			open(IMG, ">$file.pie.$vcol.$sub_graph.$format");
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
				  name => $settings->{columns}->[$vcol].' (Pie)',
				} unless ($forgetit);

			last if ($sub_graph == $split);
		}

	}
	
	return \@pics;
}

sub draw_bars {
	my $r = shift;
	my $p = shift;
	my $file = shift;
	my $data = $r->{data};
	my $settings = $r->{sql};

	my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');

	my @groups = (map { ($_ - 1) } @{ $settings->{groupby} });

	
	my @values = (0 .. (scalar(@{$settings->{columns}}) - 1));
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
		splice(@$dataset,$_,1) for (sort { $b <=> $a } @trim_cols);

		if (grep { $_ } @$dataset) {
			push @new_data, $dataset;
			push @use_me, $set_index;
		} else {
			push @no_use, $set_index;
		}
		$set_index++;
		
	}

	for my $col (@use_me) {
		push @leg, $settings->{columns}->[$col + @groups - 1] if (map { 1 } grep { $col == $_ } @values);
	}

	my $w = 100 + 10 * scalar(@{$new_data[0]});
	$w = 400 if ($w < 400);

	my $h = 10 * (scalar(@new_data) / 2);

	$h = 0 if ($h < 0);

	my $pic = new GD::Graph::bars3d ($w + 250, $h + 500);

	$pic->set(
		title			=> $p->{reportname},
		x_labels_vertical	=> 1,
		shading			=> 1,
		bar_depth		=> 5,
		bar_spacing		=> 2,
		y_max_value		=> $max_y,
		legend_placement	=> 'TR',
		boxclr			=> 'lgray',
		logo			=> $logo,
		logo_position		=> 'R',
		logo_resize		=> 0.5,
		show_values		=> 1,
		overwrite		=> 1,
	);
	$pic->set_legend(@leg);

	my $format = $pic->export_format;

	open(IMG, ">$file.bar.$format");
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
		  name => $p->{reportname}.' (Bar)',
		}];

}

sub draw_lines {
	my $r = shift;
	my $p = shift;
	my $file = shift;
	my $data = $r->{data};
	my $settings = $r->{sql};

	my $logo = $doc->findvalue('/reporter/setup/files/chart_logo');

	my @groups = (map { ($_ - 1) } @{ $settings->{groupby} });

	
	my @values = (0 .. (scalar(@{$settings->{columns}}) - 1));
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
			push @use_me, $set_index;
		} else {
			push @no_use, $set_index;
		}
		$set_index++;
		
	}

	for my $col (@use_me) {
		push @leg, $settings->{columns}->[$col + @groups - 1] if (map { 1 } grep { $col == $_ } @values);
	}

	my $w = 100 + 10 * scalar(@{$new_data[0]});
	$w = 400 if ($w < 400);

	my $h = 10 * (scalar(@new_data) / 2);

	$h = 0 if ($h < 0);

	my $pic = new GD::Graph::lines3d ($w + 250, $h + 500);

	$pic->set(
		title			=> $p->{reportname},
		x_labels_vertical	=> 1,
		shading			=> 1,
		line_depth		=> 5,
		y_max_value		=> $max_y,
		legend_placement	=> 'TR',
		boxclr			=> 'lgray',
		logo			=> $logo,
		logo_position		=> 'R',
		logo_resize		=> 0.5,
		show_values		=> 1,
		overwrite		=> 1,
	);
	$pic->set_legend(@leg);

	my $format = $pic->export_format;

	open(IMG, ">$file.line.$format");
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
		  name => $p->{reportname}.' (Bar)',
		}];

}

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

	my @group_by = ();
	my @aggs = ();
	my $core = $r->{stage3}->{stage2}->{stage1};
	my @dims = ();

	for my $t (keys %{$$p{filter}}) {
		if ($t ne $core) {
			push @dims, $t;
		}
	}

	for my $t (keys %{$$p{output}}) {
		if ($t ne $core && !(grep { $t eq $_ } @dims) ) {
			push @dims, $t;
		}
	}

	my @dim_select = ();
	my @dim_from = ();
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
	
	my @opord = ();
	if (ref $$p{output_order}) {
		@opord = @{ $$p{output_order} };
	} else {
		@opord = ( $$p{output_order} );
	}
	my @output_order = map { { (split ':')[1] => (split ':')[2] } } @opord;
	my @p_col = split(':',$p->{pivot_col}) if $p->{pivot_col};
	my $pivot = undef;

	my $col = 1;
	my @groupby = ();
	my @output = ();
	my @columns = ();
	my @join = ();
	my @join_base = ();
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
			$pivot = scalar(@columns) - 1 if (@p_col && $t eq $p_col[1] && $c eq $p_col[2]);
			$col++;
		}

		if ($t ne $t_name && (!@join_base || !grep{$t eq $_}@join_base)) {
			my $k = $doc->findvalue("//*[\@id='$t']/\@key");
			my $f = $doc->findvalue("//*[\@id='$t']/\@field");
			push @join, "dims.\"${t}_${k}\" = \"$core\".\"$f\"";
			push @join_base, $t;
		}
	}

	my @where = ();
	my @bind = ();
	for my $t ( keys %{$$p{filter}} ) {
		my $t_name = $t;
		$t_name = "dims" if ($t ne $core);

		my $t_node = table_by_id($t);

		for my $c ( keys %{$$p{filter}{$t}} ) {
			my $label = $t_node->findvalue("fields/field[\@name='$c']/label");

			my $full_col = $c;
			$full_col = "${t}_${c}" if ($t ne $t_name);
			$full_col = "\"$t_name\".\"$full_col\"";

			my ($fam) = keys %{ $$p{filter}{$t}{$c} };
			my ($w) = keys %{ $$p{filter}{$t}{$c}{$fam} };
			my $val = $$p{filter}{$t}{$c}{$fam}{$w};

			my $filter_code_xpath = "/reporter/widgets/widget-family[\@name='$fam']/widget[\@name='$w']/filter-code[\@type='perl']";
			if (my $widget_code = $doc->findvalue($filter_code_xpath)) { # widget supplys it's own filter code
				my ($where_clause, $bind_list) = ('',[]);

				eval $widget_code;

				die "$@\n\n$widget_code" if ($@);

				push @where, $where_clause;
				push @bind, @$bind_list;

			} elsif (ref $val) {
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

	my $from = " FROM $t AS \"$core\" ";
	$from .= "RIGHT JOIN $d_select ON (". join(' AND ', @join).")" if ( @join );

	my $select =
		"SELECT ".join(',', @output). $from;

	$select .= ' WHERE '.join(' AND ', @where) if (@where);
	$select .= ' GROUP BY '.join(',',@groupby) if (@groupby);

	$r->{sql}->{'pivot'}	= $pivot;
	$r->{sql}->{'select'}	= $select;
	$r->{sql}->{'bind'}	= \@bind;
	$r->{sql}->{columns}	= \@columns;
	$r->{sql}->{groupby}	= \@groupby;
	
}






