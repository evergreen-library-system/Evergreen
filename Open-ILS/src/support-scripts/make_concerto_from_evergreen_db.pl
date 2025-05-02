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
use Cwd qw/abs_path getcwd/;

our $CHUNKSIZE = 500;

our $cwd    = getcwd();
our %dbconf = ();
our $dbhost;
our $databaseName = 'postgres';
our $dbuser;
our $dbpass;
our $dbport;
our $seedDBName;
our $dbHandler;
our $dbHandlerSeed;
our $sample;
our $outputFolder;
our $debug                 = 0;
our $seedTableUsedRowCount = 0;
our $seedTableRowCount     = 100000;
our $doUpgrade             = 0;
our $doTestRestore         = 0;
our $doSeedOnly            = 0;
our $seedFrom              = 0;
our $nonInteractive        = 0;
our $egRepoPath;
our $egRepoDestBranch = 'master';
our @skipTables       = (
    'auditor.*',
    'search.*',
    'reporter.*',
    'metabib.*',
    'actor.workstation_setting',
    'acq.lineitem_attr',
    'acq.acq_lineitem_history',
    'acq.acq_purchase_order_history',
    'action_trigger.*',
    'asset.copy_vis_attr_cache',
    'authority.rec_descriptor',
    'authority.simple_heading',
    'authority.full_rec',
    'authority.authority_linking',
    'actor.org_unit_proximity',
    'config.org_unit_setting_type_log',
    'config.xml_transform',
    'money.materialized_billable_xact_summary',
    'serial.materialized_holding_code',
    'vandelay.queued_bib_record_attr',
    'config.print_template',
    'config.workstation_setting_type',
    'permission.grp_perm_map',
    'permission.perm_list',
# all of the passwords are getting set to demo123, no need to compare that table, they are generated upon db restore.
    'actor.passwd',
# Waiting for the coded value map in 3.13 to be resolved before we decide what to do for these three tables, skipping them for now.
    'config.coded_value_map',
    'config.marc_subfield',
    'config.record_attr_definition',
    'sip.setting',
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

# a mechanism to call out special tables where we don't want the default behavior
# here we can teach this software which columns need to be used for comparison
# to seed data, and which columns we need to output into our SQL load file
our %tableColumnOverride = (

    # the id column isn't important,
    # we need to ensure that we abide by the unique constraints
    # comp is "comparison", these columns are what we use to dedupe from seed data
    # load is "load these columns only", any other columns in the table will receive PG defaults
    'actor.org_unit_setting' => {
        'comp' => [ 'org_unit', 'name' ],
        'load' => [ 'org_unit', 'name', 'value' ]
    },
    'config.metabib_class' => {
        'comp' => [ 'name', 'label' ]
    },
    'config.org_unit_setting_type' => {
        'comp' => [ 'name', 'label' ]
    },
    'config.global_flag' => {
        'comp' => [ 'name' ]
    },
    'permission.grp_tree' => {
        'comp' => [ 'name' ]
    },
    # Waiting for the coded value map in 3.13 to be resolved before we decide what to do here.
    # 'config.coded_value_map' => {
    #     'comp' => ['ctype', 'code', 'value'],
    #     'load' => ['ctype', 'code', 'value', 'description', 'opac_visible', 'search_label', 'is_simple', 'concept_uri']
    # },
    # 'config.marc_subfield' => {
    #     'comp' => [ 'marc_format', 'marc_record_type', 'tag', 'code' ]
    # },
    # 'config.record_attr_definition' => {
    #     'comp' => [ 'name', 'label' ]
    # },

);

our $help = "Usage: ./make_concerto_from_evergreen_db.pl [OPTION]...

This program automates the process of making a new dataset for the Evergreen code repository.
We need connection details to a postgres database. The provided database user needs to have
permissions to create databases.

This code will accept a pre-created seed database or it can create it's own. A blank \"seed\"
Evergreen database is needed for comparison reasons. It uses this as a reference to determine
which data is seed data and which data is not.

Mandatory arguments
--db-host           postgresql server hostname/IP
--db-user           Database Username to connect
--db-pass           Database password to connect
--db-port           Database port to connect
--evergreen-repo    Folder path to the root of the Evergreen git repository
--output-folder     Folder for our generated output

Optional
--perform-upgrade   This routine will restore previously generated dataset and upgrade it to match the
                    provided Evergreen repository version.
--non-interactive   Suppress user input prompts
--db-name           Enhanced Concerto source postgres database name if you're generating a new dataset.
--test-restore      This option will cause the software to create a new database and populate it with the previously generated dataset
--debug             Set debug mode for more verbose output.
--create-seed-db    This option will create a new DB from the version of Evergreen that the dataset was from. Just the seed DB, no data.
--seed-from-egdbid  Supply the software the database ID number form which to create the seed database (used in conjunction with --create-seed-db)
--seed-db-name      Evergreen database name for the seed database, created with --create-database --create-schema, NOT --load-all-sample
                    If you don't provide this, we will attempt to create one based upon a previously generated dataset located in
                    --output-folder. However, this will be required if you do not have a previously generated dataset.

Examples:
Generate new dataset from existing DB:
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--db-name eg_enhanced \
--output-folder output \
--seed-db-name seed_from_1326 \
--evergreen-repo /home/opensrf/repos/Evergreen

If you don't have a seed database, you can omit it, and we'll make one based
upon the version we find in the file <output_folder>/config.upgrade_log.sql
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--db-name eg_enhanced \
--output-folder output \
--evergreen-repo /home/opensrf/repos/Evergreen

Or, you can have this software make a seed DB, and that's all it will do.
The version of Evergreen it will use will be found in <output_folder>/config.upgrade_log.sql
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--output-folder output \
--evergreen-repo /home/opensrf/repos/Evergreen \
--create-seed-db

Or, you can have this software make a seed DB based on your specified version of Evergreen
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--output-folder output \
--evergreen-repo /home/opensrf/repos/Evergreen \
--create-seed-db \
--seed-from-egdbid 1350

Upgrade a previously-created dataset. Use this when cutting new releases of Evergreen and you want to include
the enhanced dataset to match. It will use the current git branch found in the provided path to the EG repo.
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--output-folder output \
--evergreen-repo /home/opensrf/repos/Evergreen \
--perform-upgrade

Test the existing dataset. Create a new database and restore the dataset.
The software will first create a database that matches the version of Evergreen in the
dataset output folder, then restore the dataset into the newly created database.
./make_concerto_from_evergreen_db.pl \
--db-host localhost \
--db-user evergreen \
--db-pass evergreen \
--db-port 5432 \
--output-folder output \
--evergreen-repo /home/opensrf/repos/Evergreen \
--test-restore

";

GetOptions(
    "db-host=s"          => \$dbhost,
    "db-name=s"          => \$databaseName,
    "db-user=s"          => \$dbuser,
    "db-pass=s"          => \$dbpass,
    "db-port=s"          => \$dbport,
    "seed-db-name=s"     => \$seedDBName,
    "output-folder=s"    => \$outputFolder,
    "debug"              => \$debug,
    "evergreen-repo=s"   => \$egRepoPath,
    "perform-upgrade"    => \$doUpgrade,
    "test-restore"       => \$doTestRestore,
    "non-interactive"    => \$nonInteractive,
    "create-seed-db"     => \$doSeedOnly,
    "seed-from-egdbid=s" => \$seedFrom,
) or printHelp();

checkCMDArgs();

setupDB();

createSeedDB() if $doSeedOnly;

start() if !$doUpgrade && !$doTestRestore;

upgrade() if $doUpgrade;

testRestore() if $doTestRestore;

sub start {

    # make the output folder if it doesn't exist
    make_path(
        $outputFolder,
        {
            chmod => 0775,
        }
    ) if ( !( -e $outputFolder ) );

    my $currentEGDBVersionNum = getLastEGDBVersionFromOutput();
    my $previousGitBranch     = checkoutEGMatchingGitVersion($currentEGDBVersionNum);
    my $tempDB                = checkSeed();
    gitCheckoutBranch( $previousGitBranch, 0, 1 );

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

            # upgrade_log is written as part of the dataset, but not loaded.
            # it's used purely to figure out what version of Evergreen we are on
            # during this execution. So, later, when we run the upgrade procedure, we
            # can figure out where we were when this was generated.
            push( @loadTables, $thisTable )
              if ( -e $thisFile && $lines > 0 && !( $thisFile =~ /config\.upgrade_log/ ) );
            undef $lines;
        }
        else {
            print "Skipping: $thisTable\n" if $debug;
        }
    }
    $loadAll = loadTableOrderMaker( $loadAll, \@loadTables );

    $loadAll .= "SELECT SETVAL('money.billable_xact_id_seq', (SELECT MAX(id) FROM money.billing));\n\n";
    $loadAll .= "SELECT SETVAL('config.remote_account_id_seq', (SELECT MAX(id) FROM config.remote_account));\n\n";
    $loadAll .= "SELECT SETVAL('money.payment_id_seq', (SELECT MAX(id) FROM money.payment));\n\n";
    $loadAll .= "SELECT SETVAL('asset.copy_id_seq', (SELECT MAX(id) FROM asset.copy));\n\n";
    $loadAll .= "SELECT SETVAL('vandelay.queue_id_seq', (SELECT MAX(id) FROM vandelay.queue));\n\n";
    $loadAll .= "SELECT SETVAL('vandelay.queued_record_id_seq', (SELECT MAX(id) FROM vandelay.queued_record));\n\n";
    $loadAll .= "SELECT SETVAL('acq.acq_lineitem_pkey_seq', (SELECT MAX(audit_id) FROM acq.acq_lineitem_history));\n\n";
    $loadAll .= "SELECT SETVAL('acq.acq_purchase_order_pkey_seq', (SELECT MAX(audit_id) FROM acq.acq_purchase_order_history));\n\n";
    $loadAll .= "SELECT SETVAL('actor.workstation_id_seq', (SELECT MAX(id) FROM actor.workstation_setting));\n\n";
    $loadAll .= "SELECT SETVAL('actor.org_unit_id_seq', (SELECT MAX(id) FROM actor.org_unit));\n\n";
    $loadAll .= "SELECT SETVAL('actor.usr_standing_penalty_id_seq', (SELECT MAX(id) FROM actor.usr_standing_penalty));\n\n";
    $loadAll .= "SELECT SETVAL('actor.usr_message_id_seq', (SELECT MAX(id) FROM (SELECT MAX(id) \"id\" FROM actor.usr_standing_penalty UNION ALL SELECT MAX(id) \"id\" FROM actor.usr_message) AS a));\n\n";

    $loadAll .= "COMMIT;\n\nSELECT actor.change_password(id,'demo123') FROM actor.usr;\n";
    $loadAll .= loaderDateCarryForward() . "\n";

    print "Writing loader > $outputFolder/load_all.sql\n";
    open( OUT, "> $outputFolder/load_all.sql" );
    binmode( OUT, ":utf8" );
    print OUT $loadAll;
    close(OUT);
    $dbHandler->disconnect;
    $dbHandlerSeed->disconnect;
    dropDB($tempDB) if $tempDB;
    exit if !$doUpgrade;
}

sub upgrade {
    my $restoreDBName = getNextAvailableDBName();
    print "Using database name: $restoreDBName\n" if $debug;
    my $currentEGDBVersionNum = getLastEGDBVersionFromOutput();
    userInput("Found this DB version from output: $currentEGDBVersionNum");
    my $previousGitBranch = checkoutEGMatchingGitVersion($currentEGDBVersionNum);
    populateDBFromCurrentGitBranch( $restoreDBName, 0 );

    # now we have a temp database full of our concerto set
    # created by the version of Evergreen that origainally made the dataset
    # Now, swtich the repo back to the original branch that the user had
    gitCheckoutBranch( $previousGitBranch, 0, 1 );
    loadThisDataset( $restoreDBName, 1 );
    upgradeDB( $restoreDBName, $currentEGDBVersionNum );
    $seedDBName = getNextAvailableDBName();
    populateDBFromCurrentGitBranch( $seedDBName, 0 );

    dbhandler_setupConnection( $restoreDBName, $dbconf{"dbhost"}, $dbconf{"dbuser"}, $dbconf{"dbpass"},
        $dbconf{"port"} );
    dbhandler_setupConnection( $seedDBName, $dbconf{"dbhost"}, $dbconf{"dbuser"}, $dbconf{"dbpass"}, $dbconf{"port"},
        1 );
    start();
    userInput( "Done! If you'd like, you can pause here and take a peek at the generated databases before "
          . "I drop them:\nFull DB: $restoreDBName\nSeed: $seedDBName" );
    $dbHandler->disconnect;
    $dbHandlerSeed->disconnect;
    dropDB($restoreDBName);
    dropDB($seedDBName);
    exit;
}

sub testRestore {
    my $currentEGDBVersionNum = getLastEGDBVersionFromOutput();
    my $previousGitBranch     = checkoutEGMatchingGitVersion($currentEGDBVersionNum);
    my $restoreDB             = checkSeed(1);
    gitCheckoutBranch( $previousGitBranch, 0, 1 );
    loadThisDataset( $restoreDB, 0 );
    print "Created database: $restoreDB from provided output folder: $outputFolder\n";
    exit;
}

sub createSeedDB {
    my $currentEGDBVersionNum = $seedFrom ? $seedFrom : getLastEGDBVersionFromOutput();
    my $restoreDBName         = getNextAvailableDBName( "seed_db_$currentEGDBVersionNum" . "_" );
    print "Using database name: $restoreDBName\n" if $debug;
    my $previousGitBranch = checkoutEGMatchingGitVersion($currentEGDBVersionNum);
    populateDBFromCurrentGitBranch( $restoreDBName, 0 );
    gitCheckoutBranch( $previousGitBranch, 0, 1 );
    print "Created a fresh seed DB from Evergreen Version: $currentEGDBVersionNum\n" . "DB name: $restoreDBName\n";
    exit;
}

sub checkSeed {
    my $forceNewDB = shift || 0;
    my $valid      = 0;
    my $createdDB  = 0;
    if ($seedDBName) {
        my $query = "";

        # a sanity check to make sure we can connect to the database and run a query
        my @res = @{ dbhandler_query( "SELECT MAX(id) FROM biblio.record_entry", undef, 1 ) };
        $valid = 1 if ( $#res > -1 );
    }

    # Seed database is missing, let's create one
    if ( !$valid || $forceNewDB ) {
        $seedDBName = getNextAvailableDBName();
        $createdDB  = $seedDBName;
        populateDBFromCurrentGitBranch( $seedDBName, 0 );
        dbhandler_setupConnection( $seedDBName, $dbconf{"dbhost"}, $dbconf{"dbuser"}, $dbconf{"dbpass"},
            $dbconf{"port"}, 1 );
    }
    return $createdDB;
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

sub loaderDateCarryForward {
    my $ret = <<'splitter';

CREATE OR REPLACE FUNCTION evergreen.concerto_date_carry_tbl_col(tbl TEXT, col TEXT, datecarry INTERVAL)
RETURNS void AS $func$

DECLARE
debug_output TEXT;
squery TEXT;
ucount BIGINT := 1;
current_offset BIGINT := 0;
chunk_size INT := 500;
max_rows BIGINT := 0;

BEGIN

squery := $$SELECT COUNT(*) FROM $$ || tbl;

EXECUTE squery INTO max_rows;

WHILE ucount > 0 LOOP

    squery := $$UPDATE $$ || tbl || $$ o SET $$ || col || $$ = $$ || col || $$ + '$$ || datecarry || $$'::INTERVAL
    FROM (SELECT id FROM $$ || tbl || $$ WHERE $$ || col || $$ IS NOT NULL ORDER BY id LIMIT $$ || chunk_size || $$ OFFSET $$ || current_offset || $$ ) AS j
    WHERE o.id=j.id$$;

    -- Display what we're about to work on
    -- SELECT INTO debug_output $$ $$ || squery || $$ $$
    --  FROM biblio.record_entry LIMIT 1;
    --  RAISE NOTICE '%', debug_output;

    -- work on it
    EXECUTE squery;

    current_offset = current_offset + chunk_size;

    squery := $$ SELECT COUNT(*) FROM (SELECT id FROM $$ || tbl || $$ ORDER BY id LIMIT $$ || chunk_size || $$ OFFSET $$ || current_offset || $$) a $$;

    -- Display squery
    -- SELECT INTO debug_output $$ $$ || squery || $$ $$
    --  FROM biblio.record_entry LIMIT 1;
    --  RAISE NOTICE '%', debug_output;

    EXECUTE squery INTO ucount;
    IF ucount > 0 THEN
        RAISE NOTICE 'date carry forward: %.% % / %', tbl, col, current_offset, max_rows;
    END IF;

END LOOP;

END;
$func$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION evergreen.concerto_date_carry_all( skip_date_carry BOOLEAN DEFAULT FALSE )
RETURNS void AS $$
DECLARE
    datediff INTERVAL;

BEGIN

IF NOT skip_date_carry THEN

    SELECT INTO datediff (SELECT now() - lowdate FROM (SELECT MIN(create_date) lowdate FROM asset.call_number) as a);

    -- acq.claim_event
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.claim_event', 'event_date', datediff);

    -- acq.fund_allocation
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_allocation', 'create_time', datediff);

    -- acq.fund_debit
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_debit', 'create_time', datediff);

    -- acq.fund_transfer
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.fund_transfer', 'transfer_time', datediff);

    -- acq.funding_source_credit
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.funding_source_credit', 'deadline_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.funding_source_credit', 'effective_date', datediff);

    -- acq.invoice
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.invoice', 'recv_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.invoice', 'close_date', datediff);

    -- acq.lineitem
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'expected_recv_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem', 'edit_time', datediff);

    -- acq.lineitem_detail
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.lineitem_detail', 'recv_time', datediff);

    -- acq.purchase_order
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'edit_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('acq.purchase_order', 'order_date', datediff);

    -- action.circulation
    -- relying on action.push_circ_due_time() to take care of the 1 second before midnight logic
    -- Omitting xact_start and xact_finish because those are going to get updated when the parent table is updated
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'due_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'stop_fines_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.circulation', 'checkin_time', datediff);

    -- action.hold_request
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'request_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'capture_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'fulfillment_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'checkin_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'return_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'prev_check_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'expire_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'cancel_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'thaw_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'shelf_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.hold_request', 'shelf_expire_time', datediff);

    -- action.survey
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey', 'end_date', datediff);

    -- action.survey_response
    PERFORM evergreen.concerto_date_carry_tbl_col('action.survey_response', 'effective_date', datediff);

    -- action.unfulfilled_hold_list
    PERFORM evergreen.concerto_date_carry_tbl_col('action.unfulfilled_hold_list', 'fail_time', datediff);

    -- actor.org_unit_closed
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.org_unit_closed', 'close_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.org_unit_closed', 'close_end', datediff);

    -- actor.passwd
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.passwd', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.passwd', 'edit_date', datediff);

    -- actor.usr
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr', 'expire_date', datediff);

    -- actor.usr_activity
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_activity', 'event_time', datediff);

    -- actor.usr_standing_penalty
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_standing_penalty', 'set_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('actor.usr_standing_penalty', 'stop_date', datediff);

    -- asset.call_number
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.call_number', 'create_date', datediff);

    -- asset.copy
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'status_changed_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy', 'active_date', datediff);

    -- asset.copy_note
    PERFORM evergreen.concerto_date_carry_tbl_col('asset.copy_note', 'create_date', datediff);

    -- authority.record_entry
    PERFORM evergreen.concerto_date_carry_tbl_col('authority.record_entry', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('authority.record_entry', 'edit_date', datediff);

    -- biblio.record_entry
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('biblio.record_entry', 'merge_date', datediff);

    -- booking.reservation
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'request_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'start_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'end_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'capture_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'cancel_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'pickup_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('booking.reservation', 'return_time', datediff);

    -- container.biblio_record_entry_bucket
    PERFORM evergreen.concerto_date_carry_tbl_col('container.biblio_record_entry_bucket', 'create_time', datediff);

    -- container.carousel
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'edit_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('container.carousel', 'last_refresh_time', datediff);

    -- container.user_bucket
    PERFORM evergreen.concerto_date_carry_tbl_col('container.user_bucket', 'create_time', datediff);

    -- container.user_bucket_item
    PERFORM evergreen.concerto_date_carry_tbl_col('container.user_bucket', 'create_time', datediff);

    -- money.billable_xact
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billable_xact', 'xact_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billable_xact', 'xact_finish', datediff);

    -- money.billing
    ALTER TABLE money.billing DISABLE TRIGGER maintain_billing_ts_tgr;
    ALTER TABLE money.billing DISABLE TRIGGER mat_summary_upd_tgr;
    ALTER TABLE money.billing DROP CONSTRAINT billing_btype_fkey;

    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'billing_ts', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'void_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'period_start', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('money.billing', 'period_end', datediff);

    ALTER TABLE money.billing ENABLE TRIGGER maintain_billing_ts_tgr;
    ALTER TABLE money.billing ENABLE TRIGGER mat_summary_upd_tgr;
    ALTER TABLE money.billing ADD CONSTRAINT billing_btype_fkey FOREIGN KEY (btype)
      REFERENCES config.billing_type (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

    -- money.payment
    PERFORM evergreen.concerto_date_carry_tbl_col('money.payment', 'payment_ts', datediff);

    -- serial.caption_and_pattern
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.caption_and_pattern', 'end_date', datediff);

    -- serial.issuance
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.issuance', 'date_published', datediff);

    -- serial.item
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'create_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'edit_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'date_expected', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.item', 'date_received', datediff);

    -- serial.subscription
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.subscription', 'start_date', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('serial.subscription', 'end_date', datediff);

    -- vandelay.queued_record
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.queued_record', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.queued_record', 'import_time', datediff);

    -- vandelay.session_tracker
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.session_tracker', 'create_time', datediff);
    PERFORM evergreen.concerto_date_carry_tbl_col('vandelay.session_tracker', 'update_time', datediff);

END IF;
END;
$$ LANGUAGE plpgsql;

\set ON_ERROR_STOP off

CREATE TABLE IF NOT EXISTS evergreen.tvar_carry_date(tvar BOOLEAN);
INSERT INTO evergreen.tvar_carry_date(tvar)
VALUES(:skip_date_carry::boolean);

BEGIN;

DO $$
DECLARE skip BOOLEAN;
BEGIN

    SELECT INTO skip tvar FROM evergreen.tvar_carry_date LIMIT 1;
    IF NOT FOUND THEN skip = FALSE;
    END IF;

    PERFORM evergreen.concerto_date_carry_all(skip);

END;

$$;

COMMIT;

DROP FUNCTION evergreen.concerto_date_carry_all(BOOLEAN);
DROP FUNCTION evergreen.concerto_date_carry_tbl_col(TEXT, TEXT, INTERVAL);

DROP TABLE IF EXISTS evergreen.tvar_carry_date;

splitter

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
        my $perlcode = '$rowCount = ' . $funcHandler . '($table, $tableColumnRef, $fHandle);';
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
        my $include    = 0;
        my $currentCol = $_;
        if ( $tableColumnOverride{$table} && $tableColumnOverride{$table}{'load'} ) {
            foreach ( @{ $tableColumnOverride{$table}{'load'} } ) {
                $include = 1 if ( $_ eq $currentCol );
            }
        }
        else {
            # if the calling code wants to remove some columns, we skip them here
            if ( ( !$omitColumnsRef ) || ( not defined $omitColumn{$currentCol} ) ) {
                $include = 1;
            }
            else {
                print "removing column: $table.$currentCol\n" if $debug;
            }
        }
        if ($include) {
            $query     .= "$currentCol, ";
            $sqlOutTop .= "$currentCol, ";
            $order     .= "$colCount, ";
            $colCount++;
        }
        undef $include;
    }
    $query     = substr( $query,     0, -2 );    # remove the trailing comma+space
    $sqlOutTop = substr( $sqlOutTop, 0, -2 );    # remove the trailing comma+space
    $order     = substr( $order,     0, -2 );    # remove the trailing comma+space
    $query .= " FROM ONLY $table \n$order";

    # makes it possible to not have to quote strings, dates, etc.
    $sqlOutTop .= ") FROM stdin;\n";

    my $offset    = 0;
    my @data      = @{ getDataChunk( $query, $offset ) };
    my $firstTime = 1;
    while ( $#data > 0 )                         #skipping column def metadata at the end of the array
    {
        my $sqlOut              = $sqlOutTop;
        my @differencesFromSeed = @{ removeDuplicateStockData( \@data, $table, $firstTime ) };
        $firstTime = 0;
        my $outCount = 0;
        foreach (@differencesFromSeed) {
            $outCount++;
            $rowCount++;
            my $row = $_;
            foreach ( @{$row} ) {
                if ( !defined $_ ) {
                    $_ = '\N';
                }
                else {
                    # escape reserved tokens
                    $_ =~ s/\\/\\\\/g;    # all backslashes need escaped
                    $_ =~ s/\n/\\n/g;     # newline
                    $_ =~ s/\r/\\r/g;     # carriage return
                    $_ =~ s/\t/\\t/g;     # tab
                    $_ =~ s/\v/\\v/g;     # vertical tab
                    $_ =~ s/\f/\\f/g;     # form feed
                }
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
    my $lines          = standardHandler( $table, $tableColumnRef, $fHandle, undef );
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
        $ret .= "SELECT SETVAL('!!seqname!!', (SELECT MAX(!!colname!!) FROM !!tbname!!));\n";
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

            # special handler for some tables
            if ( $tableColumnOverride{$table} && $tableColumnOverride{$table}{'comp'} ) {
                foreach ( @{ $tableColumnOverride{$table}{'comp'} } ) {
                    my $colname = $_;
                    my $colpos  = $columns{$colname};
                    $select .= "$colname, ";
                    if ( defined @row[$colpos] ) {
                        $pos++;
                        $where .= " AND $colname = \$$pos";
                        push( @vals, @row[$colpos] );
                    }
                    else {
                        $where .= " AND $colname is null";
                    }
                }
            }
            else {
                while ( ( my $colname, my $colpos ) = each(%columns) ) {

                    # compare ID numbers when there is an ID column, otherwise, compare the rest of the columns
                    if ( ( $colname ne 'id' && not defined $columns{'id'} ) || $colname eq 'id' ) {

                        $select .= "$colname, ";

                        # if it's null data, the SQL needs to be "is null", not "="
                        if ( defined @row[$colpos] ) {
                            $pos++;
                            $where .= " AND $colname = \$$pos";
                            push( @vals, @row[$colpos] );
                        }
                        else {
                            $where .= " AND $colname is null";
                        }
                    }
                }
            }

            # remove the trailing comma+space
            $select = substr( $select, 0, -2 );
            $select .= "\nFROM ONLY $table\n$where\n";
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
    my $query   = "SELECT count(*) FROM ONLY $table";
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

sub upgradeDB {
    my $restoreDBName         = shift;
    my $currentEGDBVersionNum = shift;
    print "Upgrading DB: $restoreDBName, starting from stamp: $currentEGDBVersionNum\n" if $debug;
    my @upgradeScripts = @{ findAllUpgradeScriptsAfterSpecifiedVersion($currentEGDBVersionNum) };
    foreach (@upgradeScripts) {
        execPSQLCMD( "-t -v eg_version=\"'enhanced_concerto_script'\" -f '$_'", $restoreDBName );
    }
}

sub dropDB {
    my $dbname = shift;
    execPSQLCMD( "-c 'DROP DATABASE IF EXISTS $dbname'", "postgres" );
}

sub getNextAvailableDBName {
    my $prefDBNamePrefix = shift || "concertoscript";
    my $query            = "SELECT datname FROM pg_database WHERE datistemplate = false";
    my @results          = @{ dbhandler_query($query) };

    # remove column defs, we don't need them here
    pop @results;
    my %names = ();
    foreach (@results) {
        my @row = @{$_};
        $names{ @row[0] } = 1;
    }
    my $loop = 0;
    $loop++ while ( $names{ $prefDBNamePrefix . $loop } );
    return $prefDBNamePrefix . $loop;
}

sub getLastEGDBVersionFromOutput {
    print "Reading previously generated data from $outputFolder/config.upgrade_log.sql\n" if $debug;
    my $file       = $outputFolder . "/config.upgrade_log.sql";
    my @lines      = @{ logfile_readFile($file) };
    my $highestNum = 0;
    my $tableLine  = shift @lines;
    $tableLine =~ s/^[^\(]*?\(([^\)]*?)\).*$/$1/g;

    #Hunt down the column for "version"
    my @cols          = split( /,/, $tableLine );
    my $versionColPOS = 0;
    my $pos           = 0;
    foreach (@cols) {
        my $test = $_;
        $test =~ s/\s+$//g;
        $versionColPOS = $pos if ( lc $test eq 'version' );
        undef $test;
        $pos++;
    }
    foreach (@lines) {
        my @cols        = split( /\t/, $_ );
        my $thisVersion = @cols[$versionColPOS];
        next if ( $thisVersion =~ /\D/ );    # ignore if there are non-numerics
        $highestNum = $thisVersion if ( $thisVersion + 0 > $highestNum );
    }
    print "Result: $highestNum\n" if $debug;
    return $highestNum;
}

sub checkoutEGMatchingGitVersion {
    my $versionNum  = shift;
    my $versionFile = findMatchingUpgradeFile($versionNum);
    print $versionFile . "\n";
    my $commit = findGitCommitForFile($versionFile);
    userInput("Found this Evergreen git commit: $commit");
    return gitCheckoutBranch( $commit, 1, 0 );    # stash anything pending, and don't apply after branch switch
}

sub findMatchingUpgradeFile {
    my $upgradeNum      = shift;
    my $egUpgradeFolder = "Open-ILS/src/sql/Pg/upgrade";
    my $ret             = '';
    my $folder          = $egRepoPath . '/' . $egUpgradeFolder;
    opendir( my $dh, $folder ) || die "Can't open $folder: $!";
    while ( readdir $dh ) {
        if ( $_ =~ /^$upgradeNum.*?\.sql/ ) {
            $ret = $egUpgradeFolder . '/' . $_;
        }
    }
    closedir $dh;
    return $ret;
}

sub findAllUpgradeScriptsAfterSpecifiedVersion {
    my $upgradeNum      = shift;
    my $egUpgradeFolder = "Open-ILS/src/sql/Pg/upgrade";
    my %map             = ();
    my @ret             = ();
    my @sortme          = ();
    my $folder          = $egRepoPath . '/' . $egUpgradeFolder;
    opendir( my $dh, $folder ) || die "Can't open $folder: $!";
    while ( readdir $dh ) {
        if ( $_ ne '.' && $_ ne '..' && $_ =~ /^\d+\..*/ ) {
            my $thisStamp = $_;
            $thisStamp =~ s/^([^\.]*)\..*$/$1/g;
            if ( $thisStamp + 0 > $upgradeNum + 0 ) {
                push( @sortme, $thisStamp );
                $map{$thisStamp} = $egRepoPath . '/' . $egUpgradeFolder . '/' . $_;
            }
        }
    }
    closedir $dh;
    @sortme = sort { $a <=> $b } @sortme;
    push( @ret, $map{$_} ) foreach (@sortme);
    return \@ret;
}

sub findGitCommitForFile {
    my $file = shift;
    my $ret  = '';
    my $exec = "cd '$egRepoPath' && git log $file";

    my $return   = execSystemCMDWithReturn($exec);
    my @retLines = split( /\n/, $return );
    foreach (@retLines) {
        if ( $_ =~ /^\s*commit\s+[^\s]*$/ ) {
            $ret = $_;
            $ret =~ s/^\s*commit\s+([^\s]*)$/$1/g;
        }
    }
    print "Found commit: $ret\n" if $debug;
    return $ret;
}

sub gitCheckoutBranch {
    print "Headed into gitCheckoutBranch()\n" if $debug;
    my $branch       = shift;
    my $stash        = shift || 0;
    my $restoreStash = shift || 0;

    # get the current branch so we can switch back
    my $exec = "cd '$egRepoPath' && git rev-parse --abbrev-ref HEAD";
    my $ret  = execSystemCMDWithReturn($exec);
    $exec = "cd '$egRepoPath'";
    $exec .= " && git stash" if $stash;
    $exec .= " && git checkout $branch";
    $exec .= " && git stash apply" if $restoreStash;
    userInput("Executing: '$exec'");
    execSystemCMD( $exec, 1 );
    userInput("Done Executing: '$exec'");
    print "Done with gitCheckoutBranch()\n" if $debug;
    return $ret;
}

sub populateDBFromCurrentGitBranch {
    my $db                 = shift;
    my $loadConcerto       = shift || 0;
    my $eg_db_config_stock = "Open-ILS/src/support-scripts/eg_db_config.in";
    my $eg_db_config_temp  = "Open-ILS/src/support-scripts/eg_db_config";
    my $eg_config_stock    = "Open-ILS/src/extras/eg_config.in";
    my $eg_config_temp     = "Open-ILS/src/extras/eg_config";
    fix_eg_config( $egRepoPath . "/$eg_db_config_stock", $egRepoPath . "/$eg_db_config_temp" );
    fix_eg_config( $egRepoPath . "/$eg_config_stock",    $egRepoPath . "/$eg_config_temp" );
    my $exec = "cd '$egRepoPath' && perl '$eg_db_config_temp'";
    $exec .= " --create-database --create-schema";
    $exec .= " --user " . $dbconf{"dbuser"};
    $exec .= " --password " . $dbconf{"dbpass"};
    $exec .= " --hostname " . $dbconf{"dbhost"};
    $exec .= " --port " . $dbconf{"port"};
    $exec .= " --database $db";
    execSystemCMD($exec);
    loadThisDataset( $db, 1 ) if $loadConcerto;
}

sub loadThisDataset {
    my $db            = shift;
    my $skipDateCarry = shift || 0;
    $skipDateCarry = $skipDateCarry ? "-v skip_date_carry='1'" : '';

    chdir($outputFolder);
    print "LOADING DATA\nThis can take a few minutes...\n";
    execPSQLCMD( "$skipDateCarry -f load_all.sql", $db );
    chdir($cwd);
}

sub fix_eg_config {
    my $inFile     = shift;
    my $outputFile = shift;

    unlink $outputFile if -e $outputFile;
    my $outHandle;
    open( $outHandle, '>> ' . $outputFile );
    binmode( $outHandle, ":utf8" );

    my @lines      = @{ logfile_readFile($inFile) };
    my %replaceMap = (
        '\@prefix\@'                => '/openils',
        '\@datarootdir\@'           => '${prefix}/share',
        '\@BUILDILSCORE_TRUE\@'     => '',
        '\@BUILDILSWEB_TRUE\@'      => '',
        '\@BUILDILSREPORTER_TRUE\@' => '',
        '\@BUILDILSCLIENT_TRUE\@'   => '',
        '\@PACKAGE_STRING\@'        => '',
        '\@bindir\@'                => '${exec_prefix}/bin',
        '\@libdir\@'                => '${exec_prefix}/lib',
        '\@TMP\@'                   => '/tmp',
        '\@includedir\@'            => '${prefix}/include',
        '\@APXS2\@'                 => '',
        '\@sysconfdir\@'            => '/openils/conf',
        '\@LIBXML2_HEADERS\@'       => '',
        '\@APR_HEADERS\@'           => '',
        '\@APACHE2_HEADERS\@'       => '',
        '\@localstatedir\@'         => '',
        '\@docdir\@'                => '',
    );

    foreach (@lines) {
        my $line = $_;

        # this file has some placeholders. We're not going to make use of
        # this feature in the script, but it won't run unless those are populated
        while ( ( my $key, my $value ) = each(%replaceMap) ) {
            $line =~ s/$key/$value/g;
        }
        print $outHandle $line;
    }
    chmod( 0755, $outHandle );
    close($outHandle);
}

sub execSystemCMD {
    my $cmd          = shift;
    my $ignoreErrors = shift;
    print "executing $cmd\n" if $debug;
    system($cmd) == 0;
    if ( !$ignoreErrors && ( $? == -1 ) ) {
        die "system '$cmd' failed: $?";
    }
    print "Done executing $cmd\n" if $debug;
}

sub execSystemCMDWithReturn {
    my $cmd       = shift;
    my $dont_trim = shift;
    my $ret;
    print "executing $cmd\n" if $debug;
    open( DATA, $cmd . '|' );
    my $read;
    while ( $read = <DATA> ) {
        $ret .= $read;
    }
    close(DATA);
    return 0 unless $ret;
    $ret = substr( $ret, 0, -1 ) unless $dont_trim;    #remove the last character of output.
    print "Done executing $cmd\n" if $debug;
    return $ret;
}

sub execPSQLCMD {
    my $cmd = shift;
    my $db  = shift;
    $ENV{'PGUSER'}     = $dbconf{"dbuser"};
    $ENV{'PGPASSWORD'} = $dbconf{"dbpass"};
    $ENV{'PGPORT'}     = $dbconf{"port"};
    $ENV{'PGHOST'}     = $dbconf{"dbhost"};
    $ENV{'PGDATABASE'} = $db;
    my $pcmd = "psql $cmd";    #2>&1";
    print "Running:\n$pcmd\n";
    `$pcmd`;
}

sub dbhandler_setupConnection {
    my $dbname = shift;
    my $host   = shift;
    my $login  = shift;
    my $pass   = shift;
    my $port   = shift;
    my $seed   = shift;
    if ($seed) {
        undef $dbHandlerSeed;
        our $dbHandlerSeed = DBI->connect(
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
        undef $dbHandler;
        our $dbHandler = DBI->connect(
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
    %dbconf = (
        'dbuser' => $dbuser,
        'dbpass' => $dbpass,
        'port'   => $dbport,
        'dbhost' => $dbhost,
        'db'     => $databaseName,
    );
    dbhandler_setupConnection( $dbconf{"db"}, $dbconf{"dbhost"}, $dbconf{"dbuser"}, $dbconf{"dbpass"},
        $dbconf{"port"} );

    dbhandler_setupConnection( $seedDBName, $dbconf{"dbhost"}, $dbconf{"dbuser"}, $dbconf{"dbpass"}, $dbconf{"port"},
        1 );
}

sub checkCMDArgs {
    print "Checking command line arguments...\n" if ($debug);

    if ( !$dbhost ) {
        print "Please provide the postgres database hostname/IP via --db-host\n";
        exit 1;
    }

    if ( !$dbuser ) {
        print "Please provide the postgres database username via --db-user\n";
        exit 1;
    }

    if ( !$dbpass ) {
        print "Please provide the postgres database password via --db-pass\n";
        exit 1;
    }

    if ( !$dbport ) {
        print "Please provide the postgres database port via --db-port\n";
        exit 1;
    }

    if ( !$databaseName && ( !$doUpgrade || !$doTestRestore ) ) {
        print "Please provide the postgres database name via --db-name\n";
        exit 1;
    }

    if ( $outputFolder eq '' ) {
        print "Output folder not provided. Please pass in a command line path argument with --output-folder\n";
        exit 1;
    }
    if ( !$egRepoPath ) {
        print "You didn't include a path to the Evergreen repository --evergreen-repo\n";
        exit 1;
    }
    if ( !-e $egRepoPath ) {
        print "The path to the Evergreen repository --evergreen-repo does not exist\n";
        exit 1;
    }
    if ( !-e ( $egRepoPath . '/.git' ) ) {
        print "The path to the Evergreen repository is not a git repository\n";
        exit 1;
    }
    if ( $doUpgrade && ( !-e ( $outputFolder . '/config.upgrade_log.sql' ) ) ) {
        print
          "You've spcified the upgrade option but the output folder doesn't contain a previously generated dataset. "
          . "I need to know what version of Evergreen this dataset was created from. I use 'config.upgrade_log.sql' to figure that out\n";
        exit 1;
    }
    if ( !$seedDBName && ( !-e ( $outputFolder . '/config.upgrade_log.sql' ) ) ) {
        print
"Please provide the name of the Evergreen seed database and/or an output folder that contains a previously generated dataset. "
          . "Please pass in a command line path argument with --seed-db-name\n";
        exit 1;
    }
    if ($doUpgrade) {
        userInput(
"You've chosen to perform an upgrade. FYI, the output folder SQL files will get overwritten with the upgraded version\n"
        );
    }

    # Trim any trailing / on path
    $outputFolder =~ s/\/$//g;
    $egRepoPath   =~ s/\/$//g;
}

sub userInput {
    my $prompt = shift;
    my $answer;
    if ( !$nonInteractive ) {
        print $prompt. "\n";
        print "Press Enter to continue or CTRL+C to stop now\n";
        $answer = <STDIN>;
    }
    return $answer;
}

sub printHelp {
    print $help;
    exit 0;
}

exit;
