#!/usr/bin/perl
use warnings;
use strict;
use List::MoreUtils qw/uniq/;

$| = 1;

my $plen = 6;
my $maxed = 3;

my %dict;
my $etime;
my $secs;

my $class = $ARGV[0];

my $stime = time;
while (my $data = <>) {
    my $line = $.;

    chomp($data); $data=lc($data);

    my @words;
    while( $data =~ m/([\w\d]+'*[\w\d]*)/g ) {
        push @words, $1;
    }

    for my $raw (uniq @words) {
        my $key = $raw;
        $dict{$key} //= [0,[]];
        $dict{$key}[0]++;

        if ($dict{$key}[0] == 1) { # first time we've seen it, need to generate prefix keys
            push @{$dict{$key}[1]}, $raw;

            if (length($raw) > $plen) {
                $key = substr($raw,0,$plen);
                $dict{$key} //= [0,[]];
                push @{$dict{$key}[1]}, $raw;
            }

            for my $edit (symspell_generate_edits($key, 1)) {
                $dict{$edit} //= [0,[]];
                push @{$dict{$edit}[1]}, $raw;
            }
        }
    }

    unless ($line % 10000) {
        $etime = time;
        $secs = $etime - $stime;
        warn "$line lines consumed from input in $secs seconds...\n";
    }
}

$etime = time;
$secs = $etime - $stime;
warn "Dictionary built in $secs seconds, writing...\n";

$stime = time;
my $counter = 0;

print <<"SQL";
CREATE UNLOGGED TABLE search.symspell_dictionary_partial_$class (
    prefix_key TEXT,
    ${class}_count INT,
    ${class}_suggestions TEXT[]
) FROM STDIN;

COPY search.symspell_dictionary_partial_$class FROM STDIN;
SQL

while ( my ($key, $cl_dict) = each %dict ) {
    $counter++;
    print join( "\t", $key, $$cl_dict[0], (scalar(@{$$cl_dict[1]}) ? '{'.join(',', uniq @{$$cl_dict[1]}).'}' : '\N')) . "\n";
    delete $dict{$key};
}

print <<"SQL";
\\.

INSERT INTO search.symspell_dictionary (prefix_key, ${class}_count, ${class}_suggestions)
    SELECT * FROM search.symspell_dictionary_partial_$class
    ON CONFLICT (prefix_key) DO UPDATE
        SET ${class}_count = EXCLUDED.${class}_count,
        ${class}_suggestions = EXCLUDED.${class}_suggestions;

SQL

$etime = time;
$secs = $etime - $stime;
warn "$counter dictionary prefix key entries written in $secs seconds.\n";

sub symspell_generate_edits {
    my $word = shift;
    my $dist = shift;
    my $c = 1;
    my @list;
    my @sublist;
    my $len = length($word);

    while ( $c <= $len ) {
        my $item = substr($word, 0, $c - 1) . substr($word, $c);
        push @list, $item;
        if ($dist < $maxed) {
            push @sublist, symspell_generate_edits($item, $dist + 1);
        }
        $c++;
    }

    push @list, @sublist;

    if ($dist == 1) {
            #warn join(', ', uniq @list) . "\n";
        return uniq(@list);
    }

    return @list;
}

