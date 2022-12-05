#!/usr/bin/perl

# Copyright (C) 2022 MOBIUS
# Author: Blake Graham-Henderson <blake@mobiusconsortium.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

use Data::Dumper;
use XML::Simple;
use Getopt::Long;
use DBD::Pg;
use File::Path qw(make_path);

our $CHUNKSIZE = 500;

our $xmlconf = "/openils/conf/opensrf.xml";
our $xmlconfseed;
our $dbHandler;
our $dbHandlerSeed;
our $sample;
our $outputFolder;
our $debug                 = 0;
our $seedTableUsedRowCount = 0;
our $seedTableRowCount     = 100000;
our @skipTables            = (
    'auditor.*',
    'search.*',
    'reporter.*',
    'metabib.*',
    'actor.workstation_setting',
    'acq.lineitem_attr',
    'action_trigger.*',
    'asset.copy_vis_attr_cache',
    'authority.rec_descriptor',
    'authority.simple_heading',
    'authority.full_rec',
    'authority.authority_linking',
    'config.upgrade_log',
    'actor.org_unit_proximity',
    'config.org_unit_setting_type_log',
    'config.xml_transform',
    'money.materialized_billable_xact_summary',
    'serial.materialized_holding_code',
    'vandelay.queued_bib_record_attr',
	'config.print_template',
	'config.workstation_setting_type',
);

our @loadOrder = (
    'actor.org_unit',
    'actor.usr',
    'acq.fund',
    'acq.provider',

    # call number data can include ##URI##,
    # which biblio.record_entry triggers create, so, they go first
    'asset.call_number',
    'asset.uri',
    'asset.uri_call_number_map',
    'biblio.record_entry',
    'biblio.monograph_part',
    'acq.edi_account',
    'acq.purchase_order',
    'acq.lineitem',
    'acq.lineitem_detail',
    'acq.invoice',
    'acq.invoice_entry',
    'asset.copy_location',
    'asset.copy',
    'biblio.peer_type',
    'authority.record_entry',
    'money.grocery',
    'money.billable_xact',
    'money.billing',

    # needs to come before actor.workstation
    'money.bnm_desk_payment',
);

our $help = "Usage: ./make_concerto_from_evergreen_db.pl [OPTION]...

This program automates the process of making a new dataset for the Evergreen code repository.
We need connection details to the Evergreen database where the intended dataset lives AND
we need connection details to a stock Evergreen database that only has the seed data.
This code requires the second database for comparison reasons. It needs to know what data is
seed data and what data is not.

Mandatory arguments
--output-folder     Folder for our generated output
--xmlseed           path to Evergreen opensrf.xml file for DB connection details to the seed database, created with --create-database --create-schema, NOT --load-all-sample

Optional
--xmlconfig         path to Evergreen opensrf.xml file for DB connection details, default /openils/conf/opensrf.xml
--sample            Number of rows to fetch eg --sample 100 (not implemented)
--debug             Set debug mode for more verbose output.
";

GetOptions(
    "sample=s"        => \$sample,
    "xmlconfig=s"     => \$xmlconf,
    "xmlseed=s"       => \$xmlconfseed,
    "output-folder=s" => \$outputFolder,
    "debug"           => \$debug,
) or printHelp();

checkCMDArgs();

setupDB();

start();

sub start {

    # make the output folder if it doesn't exist
    make_path(
        $outputFolder,
        {
            chmod => 0775,
        }
    ) if ( !( -e $outputFolder ) );

    # Gather a list of Evergreen Tables to process
    my @evergreenTables = @{ getSchemaTables() };
    my $loadAll =
        "BEGIN;\n\n-- stop on error\n\\set ON_ERROR_STOP on\n\n"
      . "-- Ignore constraints until we're done\nSET CONSTRAINTS ALL DEFERRED;\n\n";
    my @loadTables = ();
    while ( $#evergreenTables > -1 ) {
        my $thisTable = shift @evergreenTables;
        my $columnRef = shift @evergreenTables;
        if ( checkTableForInclusion($thisTable) ) {
            my $thisFile = $outputFolder . "/$thisTable.sql";
            print "Processing $thisTable > $thisFile\n";
            unlink $thisFile if -e $thisFile;
            my $thisFhandle;
            open( $thisFhandle, '>> ' . $thisFile );
            binmode( $thisFhandle, ":utf8" );
            my $lines = tableHandler( $thisTable, $columnRef, $thisFhandle );
            close($thisFhandle);
            unlink $thisFile if ( -e $thisFile && $lines == 0 );
            push( @loadTables, $thisTable ) if ( -e $thisFile && $lines > 0 );
            undef $lines;
        }
        else {
            print "Skipping: $thisTable\n" if $debug;
        }
    }
    $loadAll = loadTableOrderMaker( $loadAll, \@loadTables );
    $loadAll .= "COMMIT;\n";
    print "Writing loader > $outputFolder/load_all.sql\n";
    open( OUT, "> $outputFolder/load_all.sql" );
    binmode( OUT, ":utf8" );
    print OUT $loadAll;
    close(OUT);
}

sub loadTableOrderMaker {
    my $loadString        = shift;
    my $includedTablesRef = shift;
    my @includedTables    = @{$includedTablesRef};
    my %used              = ();

    # Loop through the pre-defined order, and check those off
    foreach (@loadOrder) {
        my $otable = $_;
        my $pos    = 0;
        foreach (@includedTables) {
            if ( $includedTables[$pos] eq $otable ) {
                $loadString .= makeLoaderLine($_);
                $used{$pos} = 1;
            }
            $pos++;
        }
        undef $pos;
    }

    # include the rest
    my $pos = 0;
    foreach (@includedTables) {
        if ( not defined $used{$pos} ) {
            $loadString .= makeLoaderLine($_);
            $used{$pos} = 1;
        }
        $pos++;
    }
    undef $pos;

    return $loadString;
}

sub makeLoaderLine {
    my $table = shift;
    my $ret   = "\\echo loading $table\n";
    $ret .= "\\i $table.sql\n\n";
    return $ret;
}

sub tableHandler {
    my $table          = shift;
    my $tableColumnRef = shift;
    my $fHandle        = shift;
    my $funcHandler    = $table;
    my $rowCount       = 0;
    $funcHandler =~ s/\./_/g;
    $funcHandler .= '_handler';

# if some tables need handled special, make a sub with the table name AKA sub biblio_record_entry_handler
    if ( functionExists($funcHandler) ) {
        my $perlcode =
            '$rowCount = '
          . $funcHandler
          . '($table, $tableColumnRef, $fHandle);';
        eval $perlcode;
    }
    else {
        $rowCount = standardHandler( $table, $tableColumnRef, $fHandle );
    }
    return $rowCount;
}

sub columnOrder {
    my $colRef  = shift;
    my %columns = %{$colRef};
    my @order   = ();
    my @ret     = ();

    while ( ( my $colname, my $colpos ) = each(%columns) ) {
        push( @order, $colpos );
    }
    @order = sort { $a <=> $b } @order;
    foreach (@order) {
        my $thisPOS = $_;
        while ( ( my $colname, my $colpos ) = each(%columns) ) {
            if ( $colpos == $thisPOS ) {
                push( @ret, $colname );
            }
        }
        undef $thisPOS;
    }
    return \@ret;
}

sub functionExists {

    # no strict 'refs';
    my $funcname = shift;
    return \&{$funcname} if defined &{$funcname};
    return;
}

sub getDataChunk {
    my $query  = shift;
    my $offset = shift;
    $query .= "\nLIMIT $CHUNKSIZE OFFSET $offset\n";
    print $query if $debug;
    my @results = @{ dbhandler_query($query) };
    return \@results;
}

sub standardHandler {
    my $table          = shift;
    my $tableColumnRef = shift;
    my $fHandle        = shift;
    my $omitColumnsRef = shift;
    my %omitColumn     = %{$omitColumnsRef} if $omitColumnsRef;
    my $query          = "SELECT ";
    my $sqlOutTop      = "COPY $table (";
    my $order          = "ORDER BY ";
    my @colOrder       = @{ columnOrder($tableColumnRef) };
    my $colCount       = 1;
    my $rowCount       = 0;

    foreach (@colOrder) {

        # if the calling code wants to remove some columns, we skip them here
        if ( ( !$omitColumnsRef ) || ( not defined $omitColumn{$_} ) ) {
            $query     .= "$_, ";
            $sqlOutTop .= "$_, ";
            $order     .= "$colCount, ";
            $colCount++;
        }
        else {
            print "removing column: $_\n";
        }
    }
    $query     = substr( $query,     0, -2 );  # remove the trailing comma+space
    $sqlOutTop = substr( $sqlOutTop, 0, -2 );  # remove the trailing comma+space
    $order     = substr( $order,     0, -2 );  # remove the trailing comma+space
    $query .= " FROM $table\n$order";

    # makes it possible to not have to quote strings, dates, etc.
    $sqlOutTop .= ") FROM stdin;\n";

    my $offset    = 0;
    my @data      = @{ getDataChunk( $query, $offset ) };
    my $firstTime = 1;
    while ( $#data > 0 )   #skipping column def metadata at the end of the array
    {
        my $sqlOut = $sqlOutTop;
        my @differencesFromSeed =
          @{ removeDuplicateStockData( \@data, $table, $firstTime ) };
        $firstTime = 0;
        my $outCount = 0;
        foreach (@differencesFromSeed) {
            $outCount++;
            $rowCount++;
            my $row = $_;
            foreach ( @{$row} ) {
                $_ = '\N' if !defined $_;

                # escape reserved tokens
                $_ =~ s/\n/\\n/g;    # newline
                $_ =~ s/\r/\\r/g;    # carriage return
                $_ =~ s/\t/\\t/g;    # tab
                $_ =~ s/\v/\\v/g;    # vertical tab
                $_ =~ s/\f/\\f/g;    # form feed
                $sqlOut .= "$_\t";
            }
            $sqlOut = substr( $sqlOut, 0, -1 );
            $sqlOut .= "\n";
        }
        print $fHandle $sqlOut if $outCount > 0;

        # postgres sql syntax for finish of stdin
        print $fHandle "\\.\n\n" if $outCount > 0;

        undef $sqlOut;
        undef $outCount;
        $offset += $CHUNKSIZE;
        @data = @{ getDataChunk( $query, $offset ) };
    }
    print $fHandle injectSequenceUpdate($table);

    undef @data;
    undef $sqlOutTop;
    undef $query;

    return $rowCount;
}

sub biblio_record_entry_handler {
    my $table          = shift;
    my $tableColumnRef = shift;
    my $fHandle        = shift;
    my %omitColumns    = ( 'vis_attr_vector' => 1 );
    return standardHandler( $table, $tableColumnRef, $fHandle, \%omitColumns );
}

sub actor_workstation_handler {
    my $table          = shift;
    my $tableColumnRef = shift;
    my $fHandle        = shift;
    my $lines =
      standardHandler( $table, $tableColumnRef, $fHandle, \%omitColumns );
    print $fHandle <<'splitter';

-- a case where the deleted workstation had payments
INSERT INTO actor.workstation(id,name,owning_lib)
SELECT missingworkstation.id, aou.shortname||FLOOR(RANDOM() * 100 + 1)::INT, 1
    FROM
    (
        SELECT
        DISTINCT mbdp.cash_drawer AS id
        FROM
        money.bnm_desk_payment mbdp
        LEFT JOIN actor.workstation aw ON (mbdp.cash_drawer = aw.id)
        WHERE
        aw.id IS NULL
    ) missingworkstation
JOIN actor.org_unit aou ON (aou.id=1);

-- anonymize workstation names
UPDATE
actor.workstation aw
    SET name=aou.shortname||'-'||aw.id
FROM actor.org_unit aou
WHERE
    aou.id=aw.owning_lib;
splitter

    return $lines;
}

sub injectSequenceUpdate {
    my $table      = shift;
    my @schema     = split( /\./, $table );
    my $schemaName = @schema[0];
    my $ret        = '';
    my $query      = <<'splitter';
SELECT * FROM
(
SELECT t.oid::regclass AS table_name,
       a.attname AS column_name,
       s.relname AS sequence_name
FROM pg_class AS t
   JOIN pg_attribute AS a
      ON a.attrelid = t.oid
   JOIN pg_depend AS d
      ON d.refobjid = t.oid
         AND d.refobjsubid = a.attnum
   JOIN pg_class AS s
      ON s.oid = d.objid
WHERE d.classid = 'pg_catalog.pg_class'::regclass
  AND d.refclassid = 'pg_catalog.pg_class'::regclass
  AND d.deptype IN ('i', 'a')
  AND t.relkind IN ('r', 'P')
  AND s.relkind = 'S'
) AS a
WHERE
    a.table_name = '!!tbname!!'::regclass
splitter

    $query =~ s/!!tbname!!/$table/g;
    my @results = @{ dbhandler_query($query) };
    while ( $#results > 0 ) {
        my $this    = shift @results;
        my @row     = @{$this};
        my $colname = @row[1];
        my $seqname = @row[2];
        $ret .= "\\echo sequence update column: !!colname!!\n";
        $ret .=
"SELECT SETVAL('!!seqname!!', (SELECT MAX(!!colname!!) FROM !!tbname!!));\n";
        $ret =~ s/!!tbname!!/$table/g;
        $ret =~ s/!!colname!!/$colname/g;
        $ret =~ s/!!seqname!!/$schemaName.$seqname/g;
        undef $colname;
        undef $seqname;
    }

    return $ret;
}

sub removeDuplicateStockData {
    my $resultsRef = shift;
    my $table      = shift;
    my $firstTime  = shift;
    $seedTableRowCount = getTableRowCount( $table, 1 ) if ($firstTime);
    $seedTableUsedRowCount = 0 if ($firstTime);
    my @ret         = ();
    my @results     = @{$resultsRef};
    my $colRef      = @results[$#results];
    my %columns     = %{$colRef};
    my $resultsPOS  = 0;
    my $removeCount = 0;

    foreach (@results) {
        my $rowRef = $_;
        last if $resultsPOS == $#results;
        $resultsPOS++;

        # don't bother if we know we've already used up the seed data table
        if ( $seedTableUsedRowCount < $seedTableRowCount ) {
            my @row    = @{$rowRef};
            my @vals   = ();
            my $pos    = 0;
            my $select = "SELECT ";
            my $where  = "WHERE 1=1";
            while ( ( my $colname, my $colpos ) = each(%columns) ) {

# compare ID numbers when there is an ID column, otherwise, compare the rest of the columns
                if (   ( $colname ne 'id' && not defined $columns{'id'} )
                    || ( $colname eq 'id' ) )
                {
                    $select .= "$colname, ";
                    if (
                        defined @row[$colpos]
                      ) # if it's null data, the SQL needs to be "is null", not "="
                    {
                        $pos++;
                        $where .= " AND $colname = \$$pos";
                        push( @vals, @row[$colpos] );
                    }
                    else {
                        $where .= " AND $colname is null";
                    }
                }
            }

            # remove the trailing comma+space
            $select = substr( $select, 0, -2 );
            $select .= "\nFROM $table\n$where\n";
            print $select if $debug;
            print Dumper( \@vals ) if $debug;
            my @res = @{ dbhandler_query( $select, \@vals, 1 ) };

            # seed data doesn't have a match, want this row for our new dataset
            if ( $#res == 0 ) {
                push( @ret, $rowRef );
            }
            else {
                $removeCount++;

# Each time we match seed data, we count. If the number of rows found equals the
# number of total rows, we don't need to keep checking back on the seed database
                $seedTableUsedRowCount++;
            }
            undef @res;
            undef $select;
            undef $where;
            undef $pos;
            undef @vals;
        }
        else {
# exhausted the seed database table rows, this data can just blindly get added to the
# result set
            push( @ret, $rowRef );
        }
    }

    # print Dumper(\@ret);
    print "Removed $removeCount rows (exists in seed data)\n" if $removeCount;
    return \@ret;
}

sub getSchemaTables {
    my @ret       = ();
    my @tableTest = ();
    my $query     = <<'splitter';
SELECT schemaname||'.'||tablename
FROM pg_catalog.pg_tables
WHERE
schemaname NOT IN('pg_catalog','information_schema')
ORDER BY 1

splitter

    my @results   = @{ dbhandler_query($query) };
    my $resultPos = 0;
    foreach (@results) {
        my $row = $_;
        my @row = @{$row};
        if ( getTableRowCount( @row[0] ) > 0 ) {
            push( @ret, lc @row[0] );
            push( @ret, getTableColumnNames( @row[0] ) );
        }
        else {
            print "no rows in @row[0]\n" if $debug;
        }
        $resultPos++;
        last if $#results == $resultPos;    # ignore the column header metadata
    }

    undef $resultPos;

    return \@ret;
}

sub getTableRowCount {
    my $table   = shift;
    my $seed    = shift;
    my $ret     = 0;
    my $query   = "SELECT count(*) FROM $table";
    my @results = @{ dbhandler_query( $query, undef, $seed ) };
    foreach (@results) {
        my $row = $_;
        my @row = @{$row};
        $ret = @row[0];
        last;    # ignore column header metadata
    }

    return $ret;
}

sub getTableColumnNames {
    my $table   = shift;
    my $ret     = 0;
    my $query   = "SELECT * FROM $table LIMIT 1";
    my @results = @{ dbhandler_query($query) };
    $ret = pop @results;
    return $ret;
}

sub getDBconnects {
    my $openilsfile = shift;
    my $xml         = new XML::Simple;
    my $data        = $xml->XMLin($openilsfile);
    my %conf;
    $conf{"dbhost"} =
      $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}
      ->{databases}->{database}->{host};
    $conf{"db"} = $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}
      ->{databases}->{database}->{db};
    $conf{"dbuser"} =
      $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}
      ->{databases}->{database}->{user};
    $conf{"dbpass"} =
      $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}
      ->{databases}->{database}->{pw};
    $conf{"port"} =
      $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}
      ->{databases}->{database}->{port};
    return \%conf;

}

sub checkTableForInclusion {
    my $table  = shift;
    my @schema = split( /\./, $table );
    foreach (@skipTables) {
        return 0 if ( lc $table eq lc $_ );
        if ( $_ =~ /\*$/ ) {
            my @thisSchema = split( /\./, $_ );
            return 0 if ( lc @schema[0] eq lc @thisSchema[0] );
        }
    }
    return 1;
}

sub logfile_readFile {
    my $file   = shift;
    my $trys   = 0;
    my $failed = 0;
    my @lines;

    #print "Attempting open\n";
    if ( -e $file ) {
        my $worked = open( inputfile, '< ' . $file );
        if ( !$worked ) {
            print "******************Failed to read file*************\n";
        }
        binmode( inputfile, ":utf8" );
        while ( !( open( inputfile, '< ' . $file ) ) && $trys < 100 ) {
            print "Trying again attempt $trys\n";
            $trys++;
            sleep(1);
        }
        if ( $trys < 100 ) {

            #print "Finally worked... now reading\n";
            @lines = <inputfile>;
            close(inputfile);
        }
        else {
            print "Attempted $trys times. COULD NOT READ FILE: $file\n";
        }
        close(inputfile);
    }
    else {
        print "File does not exist: $file\n";
    }
    return \@lines;
}

sub dbhandler_setupConnection {
    my $dbname = shift;
    my $host   = shift;
    my $login  = shift;
    my $pass   = shift;
    my $port   = shift;
    my $seed   = shift;
    if ($seed) {
        $dbHandlerSeed = DBI->connect(
            "DBI:Pg:dbname=$dbname;host=$host;port=$port",
            $login, $pass,
            {
                AutoCommit       => 1,
                post_connect_sql => "SET CLIENT_ENCODING TO 'UTF8'",
                pg_utf8_strings  => 1
            }
        );
    }
    else {
        $dbHandler = DBI->connect(
            "DBI:Pg:dbname=$dbname;host=$host;port=$port",
            $login, $pass,
            {
                AutoCommit       => 1,
                post_connect_sql => "SET CLIENT_ENCODING TO 'UTF8'",
                pg_utf8_strings  => 1
            }
        );
    }
}

sub dbhandler_query {
    my $querystring = shift;
    my $valuesRef   = shift;
    my $seed        = shift;
    my @values      = $valuesRef ? @{$valuesRef} : ();
    my @ret;

    my $query;
    $query = $dbHandler->prepare($querystring)     if ( !$seed );
    $query = $dbHandlerSeed->prepare($querystring) if ($seed);
    my $i = 1;
    foreach (@values) {
        $query->bind_param( $i, $_ );
        $i++;
    }
    $query->execute();
    my @columnNames = @{ $query->{NAME} };
    my %colPos      = ();
    my $pos         = 0;
    foreach (@columnNames) {
        $colPos{$_} = $pos;
        $pos++;
    }
    undef @columnNames;

    while ( my $row = $query->fetchrow_arrayref() ) {
        my @pushData = ();
        foreach ( @{$row} ) {
            my $thisCol = $_;
            if ( ref $thisCol eq 'ARRAY' )    # handle [] datatypes
            {
                my $t = join( ',', @{$thisCol} );
                if ( isStringArray($thisCol) == 1 ) {
                    $t = join( "','", @{$thisCol} );
                }
                push( @pushData, "{$t}" );
                undef $t;
            }
            else {
                push( @pushData, $thisCol );
            }
            undef $thisCol;
        }
        push( @ret, \@pushData );
    }
    undef($querystring);
    push( @ret, \%colPos );

    return \@ret;
}

sub isStringArray {
    my $arrayRef = shift;
    my @array    = @{$arrayRef};
    foreach (@array) {
        if ( $_ =~ m/[^\-^0-9^\.]/g ) {
            return 1;
        }
    }
    return 0;
}

sub setupDB {
    my %dbconf = %{ getDBconnects($xmlconf) };
    dbhandler_setupConnection(
        $dbconf{"db"},     $dbconf{"dbhost"}, $dbconf{"dbuser"},
        $dbconf{"dbpass"}, $dbconf{"port"}
    );

    %dbconf = %{ getDBconnects($xmlconfseed) };
    dbhandler_setupConnection( $dbconf{"db"}, $dbconf{"dbhost"},
        $dbconf{"dbuser"}, $dbconf{"dbpass"}, $dbconf{"port"}, 1 );
}

sub checkCMDArgs {
    print "Checking command line arguments...\n" if ($debug);

    if ( $outputFolder eq '' ) {
        print
"Output folder not provided. Please pass in a command line path argument with --output-folder\n";
        exit 1;
    }
    if ( !$xmlconfseed ) {
        print
"Please provide a path to the Evergreen seed database conneciton details. Please pass in a command line path argument with --xmlseed\n";
        exit 1;
    }

    if ( !-e $xmlconf ) {
        print
"$xmlconf does not exist.\nEvergreen database xml configuration file does not exist. Please provide a path to the Evergreen opensrf.xml database conneciton details. --xmlconf\n";
        exit 1;
    }

    if ( !-e $xmlconfseed ) {
        print
"$xmlconfseed does not exist.\nEvergreen seed database xml configuration file does not exist. Please provide a path to the seed Evergreen opensrf.xml database conneciton details. --xmlconfseed\n";
        exit 1;
    }

    # Trim any trailing / on path
    $outputFolder =~ s/\/$//g;
}

sub printHelp {
    print $help;
    exit 0;
}

exit;
