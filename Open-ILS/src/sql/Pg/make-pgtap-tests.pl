#!/usr/bin/perl
# vim:et:ts=4:
use strict;
use warnings;
use Getopt::Long;

my ($db_name, $db_host, $db_port, $db_user, $db_pw) =
    ( 'evergreen', 'localhost', '5432', 'evergreen', 'evergreen' );

GetOptions(
    'db_name=s' => \$db_name,
    'db_host=s' => \$db_host,
    'db_port=s' => \$db_port,
    'db_user=s' => \$db_user,
    'db_pw=s' => \$db_pw,
);

#----------------------------------------------------------
# Database connection
#----------------------------------------------------------

use DBI;

my $dsn = "dbi:Pg:dbname=$db_name;host=$db_host;port=$db_port";
my $dbh = DBI->connect($dsn, $db_user, $db_pw);

# Short-circuit if we didn't connect successfully
unless($dbh) {
    warn "* Unable to connect to database $dsn, user=$db_user, password=$db_pw\n";
    exit 1;
}

#----------------------------------------------------------
# Main logic
#----------------------------------------------------------

print pgtap_sql_header();
handle_schemas(
    sub {
        my $schema = shift;

        sub handle_table_things {
            my $schema = shift;
            my $table_or_view = shift;
            handle_columns(
                $schema,
                $table_or_view,
                undef
            );
            handle_triggers(
                $schema,
                $table_or_view,
                undef
            );
        }

        handle_tables(
            $schema,
            \&handle_table_things
        );
        handle_views(
            $schema,
            \&handle_table_things
        );

        handle_routines(
            $schema,
            undef
        );
    }
);
print pgtap_sql_footer();

$dbh->disconnect;
exit 0;

#----------------------------------------------------------
# subroutines
#----------------------------------------------------------

sub pgtap_sql_header {
    return q^
\set ECHO none
\set QUIET 1
-- Turn off echo and keep things quiet.

-- Format the output for nice TAP.
\pset format unaligned
\pset tuples_only true
\pset pager

-- Revert all changes on failure.
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true
\set QUIET 1

-- Load the TAP functions.
BEGIN;

-- Plan the tests.
SELECT no_plan();

-- Run the tests.
^;
}

sub pgtap_sql_footer {
    return q^
-- Finish the tests and clean up.
SELECT * FROM finish();
ROLLBACK;
^;
}

sub fetch_schemas {
    my $sth = $dbh->prepare("
        SELECT schema_name FROM information_schema.schemata
            WHERE catalog_name = ?
            AND schema_name NOT IN ('information_schema','migration_tools','public')
            AND schema_name !~ '^pg_';
    ");
    $sth->execute(($db_name));
    my $schemas = $sth->fetchall_arrayref([0]);
    $sth->finish;
    return sort map { $_->[0] } @{ $schemas };
}

sub fetch_tables {
    my $schema = shift;
    my $sth = $dbh->prepare("
        SELECT table_name FROM information_schema.tables
            WHERE table_catalog = ?
            AND table_schema = ?
            AND table_type = 'BASE TABLE'
    ");
    $sth->execute(($db_name,$schema));
    my $tables = $sth->fetchall_arrayref([0]);
    $sth->finish;
    return sort map { $_->[0] } @{ $tables };
}

sub fetch_views {
    my $schema = shift;
    my $sth = $dbh->prepare("
        SELECT table_name FROM information_schema.tables
            WHERE table_catalog = ?
            AND table_schema = ?
            AND table_type = 'VIEW'
    ");
    $sth->execute(($db_name,$schema));
    my $tables = $sth->fetchall_arrayref([0]);
    $sth->finish;
    return sort map { $_->[0] } @{ $tables };
}

sub fetch_columns {
    my ($schema,$table) = (shift,shift);
    my $sth = $dbh->prepare("
        SELECT
            column_name,
            data_type,
            is_nullable,
            column_default,
            numeric_precision,
            numeric_scale,
            udt_schema,
            udt_name,
            character_maximum_length
        FROM information_schema.columns
            WHERE table_catalog = ?
            AND table_schema = ?
            AND table_name = ?
    ");
    $sth->execute(($db_name,$schema,$table));
    my $columns = $sth->fetchall_hashref('column_name');
    $sth->finish;
    return $columns;
}

sub fetch_triggers {
    my ($schema,$table) = (shift,shift);
    my $sth = $dbh->prepare("
        SELECT DISTINCT
            trigger_schema,
            trigger_name,
            event_object_schema,
            event_object_table
        FROM information_schema.triggers
            WHERE event_object_catalog = ?
            AND event_object_schema = ?
            AND event_object_table = ?
            AND trigger_schema = event_object_schema -- I don't think pgTAP can handle it otherwise
    ");
    $sth->execute(($db_name,$schema,$table));
    my $triggers = $sth->fetchall_hashref('trigger_name');
    $sth->finish;
    return $triggers;
}

sub fetch_routines {
    my $schema = shift;
    my $sth = $dbh->prepare("
        SELECT
            *
        FROM information_schema.routines
            WHERE routine_catalog = ?
            AND routine_schema = ?
    ");
    $sth->execute(($db_name,$schema));
    my $routines = $sth->fetchall_hashref('routine_name');
    $sth->finish;
    return $routines;
}

sub fetch_pg_routines { # uses pg_catalog.pg_proc instead of information_schema.routines
    my $name = shift;
    my $nargs = shift;
    my $src = shift;
    my $sth = $dbh->prepare("
        SELECT
            *
        FROM pg_catalog.pg_proc
            WHERE proname = ?
            AND pronargs = ?
            AND prosrc = ?
    ");
    $sth->execute(($name,$nargs,$src));
    my $routines = $sth->fetchall_hashref([ qw(proname proargtypes pronamespace) ]);
    $sth->finish;
    my @rows = ();
    foreach my $proname ( keys %{ $routines } ) {
        foreach my $proargtypes ( keys %{ $routines->{$proname} } ) {
            foreach my $pronamespace ( keys %{ $routines->{$proname}->{$proargtypes} } ) {
                push @rows, $routines->{$proname}->{$proargtypes}->{$pronamespace};
            }
        }
    }

    return @rows;
}

sub fetch_parameters {
    my $schema = shift;
    my $specific_routine = shift;
    my $sth = $dbh->prepare("
        SELECT
            *
        FROM information_schema.parameters
            WHERE specific_catalog = ?
            AND specific_schema = ?
            AND specific_name = ?
            AND parameter_mode = 'IN'
    ");
    $sth->execute(($db_name,$schema,$specific_routine));
    my $parameters = $sth->fetchall_hashref('ordinal_position');
    $sth->finish;
    return $parameters;
}

sub handle_schemas {
    my $callback = shift;

    my @schemas = fetch_schemas();
    foreach my $schema ( @schemas ) {
        print "\n-- schema " . $dbh->quote($schema) . "\n\n";
        print "SELECT has_schema(\n";
        print "\t" . $dbh->quote($schema) . ",\n";
        print "\t" . $dbh->quote("Has schema $schema") . "\n);\n";
        $callback->($schema) if $callback;
    }
}

sub handle_tables {
    my $schema = shift;
    my $callback = shift;

    my @tables = fetch_tables($schema);
    if (scalar @tables == 0) {
        return;
    }

    print "SELECT tables_are(\n";
    print "\t" . $dbh->quote($schema) . ",\n";
    print "\tARRAY[\n\t\t";
    print join(
        ",\n\t\t",
        map { $dbh->quote($_) } @tables
    );
    print "\n\t],\t" . $dbh->quote("Found expected tables for schema $schema");
    print "\n);\n";

    foreach my $table ( @tables ) {
        print "\n-- -- table " . $dbh->quote("$schema.$table") . "\n\n";
        $callback->($schema,$table) if $callback;
    }
}

sub handle_views {
    my $schema = shift;
    my $callback = shift;

    my @views = fetch_views($schema);
    if (scalar @views == 0) {
        return;
    }

    print "SELECT views_are(\n";
    print "\t" . $dbh->quote($schema) . ",\n";
    print "\tARRAY[\n\t\t";
    print join(
        ",\n\t\t",
        map { $dbh->quote($_) } @views
    );
    print "\n\t],\t" . $dbh->quote("Found expected views for schema $schema");
    print "\n);\n";

    foreach my $view ( @views ) {
        print "\n-- -- view " . $dbh->quote("$schema.$view") . "\n\n";
        $callback->($schema,$view) if $callback;
    }
}

sub handle_columns {
    my ($schema,$table,$callback) = (shift,shift,shift);
    my $columns = fetch_columns($schema,$table);
    if (!%{ $columns }) {
        return;
    }

    print "SELECT columns_are(\n";
    print "\t" . $dbh->quote($schema) . ",\n";
    print "\t" . $dbh->quote($table) . ",\n";
    print "\tARRAY[\n\t\t";
    print join(
        ",\n\t\t",
        map { $dbh->quote($_) } sort keys %{ $columns }
    );
    print "\n\t],\t" . $dbh->quote("Found expected columns for $schema.$table");
    print "\n);\n";

    foreach my $column ( sort keys %{ $columns } ) {

        $callback->($schema,$table,$column,undef) if $callback;

        my $col_type_original = $columns->{$column}->{data_type};
        my $col_type = $col_type_original;
        my $col_nullable = $columns->{$column}->{is_nullable};
        my $col_default = $columns->{$column}->{column_default};
        my $col_numeric_precision = $columns->{$column}->{numeric_precision};
        my $col_numeric_scale = $columns->{$column}->{numeric_scale};
        my $col_udt_schema = $columns->{$column}->{udt_schema};
        my $col_udt_name = $columns->{$column}->{udt_name};
        my $col_character_maximum_length = $columns->{$column}->{character_maximum_length};

        if (defined $col_default && $col_default =~ /::text/) {
            $col_default =~ s/^'(.*)'::text$/$1/;
        }
        if (defined $col_default && $col_default =~ /::bpchar/) {
            $col_default =~ s/^'(.*)'::bpchar$/$1/;
        }
        if ($col_type eq 'numeric' && defined $col_numeric_precision) {
            $col_type .= "($col_numeric_precision";
            if (defined $col_numeric_scale) {
                $col_type .= ",$col_numeric_scale";
            }
            $col_type .= ')';
        }
        if ($col_type eq 'USER-DEFINED' && defined $col_udt_schema) {
            $col_type = "$col_udt_schema.$col_udt_name";
            if ($col_type eq 'public.hstore') {
                $col_type = 'hstore'; # an exception
            }
        }
        if ($col_type eq 'character' && defined $col_character_maximum_length) {
            $col_type .= "($col_character_maximum_length)";
        }
        if ($col_type eq 'ARRAY' && defined $col_udt_name) {
            $col_type = substr($col_udt_name,1) . '[]';
        }

        print "\n-- -- -- column " . $dbh->quote("$schema.$table.$column") . "\n\n";
        print "SELECT col_type_is(\n";
        print "\t" . $dbh->quote($schema) . ",\n";
        print "\t" . $dbh->quote($table) . ",\n";
        print "\t" . $dbh->quote($column) . ",\n";
        print "\t" . $dbh->quote($col_type) . ",\n";
        print "\t" . $dbh->quote("Column $schema.$table.$column is type $col_type");
        print "\n);\n";
        if ($col_nullable eq 'YES') {
            print "SELECT col_is_null(\n";
            print "\t" . $dbh->quote($schema) . ",\n";
            print "\t" . $dbh->quote($table) . ",\n";
            print "\t" . $dbh->quote($column) . ",\n";
            print "\t" . $dbh->quote("Column $schema.$table.$column is nullable");
            print "\n);\n";
        } else {
            print "SELECT col_not_null(\n";
            print "\t" . $dbh->quote($schema) . ",\n";
            print "\t" . $dbh->quote($table) . ",\n";
            print "\t" . $dbh->quote($column) . ",\n";
            print "\t" . $dbh->quote("Column $schema.$table.$column is not nullable");
            print "\n);\n";
        }
        if (defined $col_default) {
            my $fixme = '';
            if ($col_type eq 'interval') {
                # FIXME - ERROR:  invalid input syntax for type interval: "'1 day'::interval"
                $fixme = '-- FIXME type 1 -- ';
            } elsif ($col_type eq 'time without time zone') {
                # FIXME - ERROR:  invalid input syntax for type time: "'17:00:00'::time without time zone"
                $fixme = '-- FIXME type 2 -- ';
            } elsif ($col_default =~ 'org_unit_custom_tree_purpose') {
                # FIXME - ERROR:  invalid input value for enum actor.org_unit_custom_tree_purpose: "'opac'::actor.org_unit_custom_tree_purpose"
                $fixme = '-- FIXME type 3 -- ';
            } elsif ($col_type eq 'integer' && $col_default =~ '\(-?\d+\)') {
                # FIXME - ERROR:  invalid input syntax for integer: "(-1)"
                $fixme = '-- FIXME type 4 -- ';
            } elsif ($col_type_original eq 'USER-DEFINED'
                && (
                    $col_udt_name eq 'hstore'
                    || $col_udt_name eq 'authority_queue_queue_type'
                    || $col_udt_name eq 'bib_queue_queue_type'
                )
            ) {
                # FIXME - ERROR:  Unexpected end of string
                $fixme = '-- FIXME type 5 -- ';
            }
            # I would love to SELECT todo past these, but they cause hard failures
            print $fixme . "SELECT col_default_is(\n";
            print $fixme . "\t" . $dbh->quote($schema) . ",\n";
            print $fixme . "\t" . $dbh->quote($table) . ",\n";
            print $fixme . "\t" . $dbh->quote($column) . ",\n";
            print $fixme . "\t" . $dbh->quote($col_default) . ",\n";
            print $fixme . "\t" . $dbh->quote("Column $schema.$table.$column has default value: $col_default");
            print "\n$fixme);\n";
        } else {
            print "SELECT col_hasnt_default(\n";
            print "\t" . $dbh->quote($schema) . ",\n";
            print "\t" . $dbh->quote($table) . ",\n";
            print "\t" . $dbh->quote($column) . ",\n";
            print "\t" . $dbh->quote("Column $schema.$table.$column has no default value");
            print "\n);\n";
        }
    }
}

sub handle_triggers {
    my ($schema,$table,$callback) = (shift,shift,shift);
    my $triggers = fetch_triggers($schema,$table);
    if (!%{ $triggers }) {
        return;
    }

    print "\n-- -- -- triggers on " . $dbh->quote("$schema.$table") . "\n";
    print "SELECT triggers_are(\n";
    print "\t" . $dbh->quote($schema) . ",\n";
    print "\t" . $dbh->quote($table) . ",\n";
    print "\tARRAY[\n\t\t";
    print join(
        ",\n\t\t",
        map { $dbh->quote($_) } sort keys %{ $triggers }
    );
    print "\n\t],\t" . $dbh->quote("Found expected triggers for $schema.$table");
    print "\n);\n";

    foreach my $trigger ( sort keys %{ $triggers } ) {
        $callback->($schema,$table,$trigger,undef) if $callback;
    }

}

sub handle_routines {
    my ($schema,$callback) = (shift,shift);
    if ($schema eq 'evergreen') {
        return; # TODO: Being the first schema in the search path, evergreen
                #       gets too polluted with non-EG stuff.  Should maybe
                #       hand-add evergreen routines once we get going with pgTAP
    }
    my $routines = fetch_routines($schema);
    if (!%{ $routines }) {
        return;
    }

    print "\n-- -- routines in schema " . $dbh->quote($schema) . "\n";
    print "SELECT functions_are(\n";
    print "\t" . $dbh->quote($schema) . ",\n";
    print "\tARRAY[\n\t\t";
    print join(
        ",\n\t\t",
        map { $dbh->quote($_) } sort keys %{ $routines }
    );
    print "\n\t],\t" . $dbh->quote("Found expected stored procedures for $schema");
    print "\n);\n";

    foreach my $routine ( sort keys %{ $routines } ) {

        print "\n-- -- routine " . $dbh->quote("$schema.$routine") . "\n";

        my $parameters = fetch_parameters(
            $schema,
            $routines->{$routine}->{specific_name}
        );
        my @params_array = (); # for trusted order and convenience
        if (%{ $parameters }) {
            foreach my $ord ( sort keys %{ $parameters } ) { 
                $params_array[$ord-1] = $parameters->{$ord}
            }
        }

        my $troublesome_parameter = 0;
        my $args_sig = 'ARRAY[]::TEXT[]';
        if (scalar(@params_array) > 0) {
            $args_sig = 'ARRAY[';
            for (my $i = 0; $i < scalar(@params_array); $i++) {
                $args_sig .= ($i ? ',' : '') . $dbh->quote( $params_array[$i]->{data_type} );
                if ( $params_array[$i]->{data_type} eq 'ARRAY' ) {
                    $troublesome_parameter = 1;
                }
                if ( $params_array[$i]->{data_type} eq 'USER-DEFINED' ) {
                    $troublesome_parameter = 1;
                }
            }
            $args_sig .= ']';
        }
        if ($troublesome_parameter) {
            $args_sig = ''; # this is optional in the assertion functions
                            # but not sure how it handles similarly named
                            # routines with different parameter signatures
        }

        print "SELECT function_lang_is(\n";
        print "\t" . $dbh->quote($schema) . ",\n";
        print "\t" . $dbh->quote($routine) . ",\n";
        print "\t$args_sig,\n" if $args_sig;
        print "\t" . $dbh->quote(lc($routines->{$routine}->{external_language})) . ",\n";
        print "\t" . $dbh->quote("$schema.$routine written in $routines->{$routine}->{external_language}") . "\n";
        print ");\n";


        my $data_type = $routines->{$routine}->{data_type};
        # The following datatype munging is voodoo/heuristic to just work with
        # the current schema.  No promises that it'll always work, but the point
        # of this script is just to create an initial set of tests; we may never
        # use it again afterward, though I could see it being useful for seeding
        # tests against whole new schemas/tables as they appear.
        if ($data_type eq 'USER-DEFINED') {
            $data_type = $routines->{$routine}->{type_udt_schema} . "."
                . $routines->{$routine}->{type_udt_name};
            if ($data_type eq 'public.hstore') {
                $data_type = 'hstore'; # an exception
            }
        }
        if ($data_type eq 'ARRAY') {
            if ($routines->{$routine}->{type_udt_name} eq '_int4') {
                $data_type = 'integer[]';
            } elsif ($routines->{$routine}->{type_udt_name} eq '_text') {
                $data_type = 'text[]';
            } else {
                $data_type = $routines->{$routine}->{type_udt_name} . '[]';
            }
        }
        my @extra_data = fetch_pg_routines(
            $routine,
            scalar(@params_array),
            $routines->{$routine}->{routine_definition}
        );
        my $expect_set = 0;
        if (scalar(@extra_data) == 1) {
           $expect_set = $extra_data[0]->{proretset};
        }
        $data_type = "setof $data_type" if $expect_set && $data_type ne 'void';

        print "SELECT function_returns(\n";
        print "\t" . $dbh->quote($schema) . ",\n";
        print "\t" . $dbh->quote($routine) . ",\n";
        print "\t$args_sig,\n" if $args_sig;
        print "\t" . $dbh->quote($data_type) . ",\n";
        print "\t" . $dbh->quote("$schema.$routine returns $data_type") . "\n";
        print ");\n";

        for (my $i = 0; $i < scalar(@params_array); $i++) {
            print '-- -- -- param ' . $dbh->quote( $params_array[$i]->{parameter_name} ) . "\n";
        }

        $callback->($schema,$routine,undef) if $callback;
    }
}


