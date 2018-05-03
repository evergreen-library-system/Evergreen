use strict;
use warnings;
use Test::More;
use Test::Output;
use FindBin;

my $num_tests = 0;

my $data;
{
    open(my $fh, "<", "$FindBin::Bin/../../sql/Pg/950.data.seed-values.sql")
        or die "Can't open 950.data.seed-values.sql: $!";
    local $/ = undef;
    $data = <$fh>;
}

my $findi18n = qr/oils_i18n_gettext\((.*?)\'\s*\)/;
my $intkey = qr/\s*(\d+)\s*,\s*E?\'(.+?)\',\s*\'(.+?)\',\s*\'(.+?)$/;
my $textkey = qr/\s*\'(.*?)\'\s*,\s*E?\'(.+?)\',\s*\'(.+?)\',\s*\'(.+?)$/;

my %found;
my @caps = $data =~ m/$findi18n/gms;
foreach my $cap (@caps) {
    my $unique;
    my @matches = $cap =~ m/$intkey/gms;
    if (length($matches[0])) {
        $unique = join('', $matches[0], $matches[2], $matches[3]);
    } else {
        @matches = $cap =~ m/$textkey/gms;
        $unique = join('', $matches[0], $matches[2], $matches[3]);
    }
    isnt(exists($found{$unique}), 1, "oils_18n_gettext duplicate key: $cap'");
    $found{"$unique"} = 1;
    $num_tests++;
    #print "$cap \n";
}
 
done_testing($num_tests);
