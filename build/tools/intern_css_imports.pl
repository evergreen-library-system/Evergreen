#!/usr/bin/perl
my $in_comment = 0;
while (<>) {
    chomp;
    if (/^\s*\@import\s+url\((['"])([^'"]+)\1\)/) {
        print `$0 $2`
    } else {
        s#(/\*).*?(\*/|$)##g;
        $in_comment = 1 if ($1 && !$2);
        s#(/\*|^).*?(\*/)##g;
        $in_comment = 0 if ($2);
        s/\s+$//;
        s/^\s+//;
        print "$_\n" unless ($in_comment || /^\s*$/)
    }
}
