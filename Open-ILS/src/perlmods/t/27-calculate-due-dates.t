#!perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::MockModule;

use_ok('OpenILS::Application::Circ::Circulate');

my $tz = 'America/Chicago';
my $utils = Test::MockModule->new('OpenILS::Application::AppUtils')
                ->redefine(ou_ancestor_setting_value => sub { return $tz; });

my $duration = '21 days';

my $circ = {};
bless $circ, 'OpenILS::Application::Circ::Circulator';

sub test_due_date {
    my %args = @_;

    my $due_date;
    $tz = $args{tz};
    eval {
        $due_date = $circ->create_due_date($args{duration}, undef, 0, $args{start_time});
    };
    if ($@) {
        fail("create_due_date() crashed with error $@");
    } else {
        is($due_date, $args{expected}, $args{success});
    }
}

# this one is a regression test with the values chosen
# have the raw due date fall during a transition to DST
test_due_date(
    duration   => '21 days',
    start_time => '2026-02-15T02:15:00-0600',
    expected   => '2026-03-08T03:15:00-0500',
    tz         => 'America/Chicago',
    success    => 'LP#2142518: due date falling on DST transition gets expected value',
);

test_due_date(
    duration   => '21 days',
    start_time => '2026-01-01T07:15:00-0600',
    expected   => '2026-01-22T07:15:00-0600',
    tz         => 'America/Chicago',
    success    => 'due date not falling on DST transition gets expected value',
);
test_due_date(
    duration   => '2 hours',
    start_time => '2026-01-01T07:15:00-0600',
    expected   => '2026-01-01T09:15:00-0600',
    tz         => 'America/Chicago',
    success    => 'hourly loan duration gets expected due time',
);
test_due_date(
    duration   => '2 hours',
    start_time => '2026-01-01T13:15:00-0000',
    expected   => '2026-01-01T10:15:00-0500',
    tz         => 'America/New_York',
    success    => 'hourly loan duration gets expected due time even if start time has a different TZ',
);
