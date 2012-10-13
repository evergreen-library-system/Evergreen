use strict;
use warnings;
use File::Find;
use File::Spec;
use Locale::Maketext::Extract;
use Test::More;
use Test::Output;

my $num_tests = 0;

my $ext = Locale::Maketext::Extract->new(
    plugins => { tt2  => ['tt2'] },
    warnings => 1,
    verbose => 0
);

sub template_checker {
    return unless /.tt2$/;
    my $tt2 = $_;
    $num_tests++;
    stderr_is {$ext->extract_file($tt2)} '', "Parse TT2 - $File::Find::name";
}

my ($vol, $dir, $file) = File::Spec->splitpath(__FILE__);
chdir("$dir/../..");
find(\&template_checker, ('templates'));

done_testing($num_tests);
