#!perl

use strict; use warnings;
use Test::More tests => 6;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use DateTime;
use Scalar::Util;

diag('Test the booking module.');

my $script = OpenILS::Utils::TestUtils->new();

# we need auth to access protected APIs
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

my $e = new_editor(xact => 1);
$e->init;

use_ok( 'OpenILS::Application::Booking' );

sub _create_test_reservation {
  my ($start_time, $end_time, $desired_resources) = @_;
  return OpenILS::Application::Booking->create_bresv(
    1,
    $authtoken,
    '99999372586', # user barcode
    [$start_time->iso8601().'Z', $end_time->iso8601().'Z'],
    4, # BR1 as the pickup location
    555, # Booking resource type
    $desired_resources,
    [], # Selected attributes
    1, # Email notification
    '### only for testing ###' # Note
  );
}

sub _future_time {
  my $hour = shift;
  return DateTime->now()
                  ->add( years => 10)
                  ->set( month => 5,
                          day => 20,
                          hour => $hour,
                          minute => 0,
                          second => 0);
}

sub _delete_test_reservations {
  my $reservations = $e->search_booking_reservation({note => '### only for testing ###'});
  $e->xact_begin;
  for my $reservation (@{$reservations}) {
      $e->delete_booking_reservation($reservation) or return $e->die_event;
  }
  $e->xact_commit;
  return;
}

subtest 'cannot make an overlapping reservation when requesting a specific resource' => sub {
  plan tests => 2;
  # First, create a new reservation in the future
  my $start_time = _future_time(13);
  my $end_time = _future_time(15);
  my $results = _create_test_reservation($start_time, $end_time, [1]);
  ok(Scalar::Util::looks_like_number($results->[0]->{bresv}),
    'returns the id of the new reservation');

  # Now, attempt to create an overlapping reservation
  $start_time->set( hour => 14 );
  $end_time->set( hour => 16 );
  $results = _create_test_reservation($start_time, $end_time, [1]);

  is($results->{textcode}, 'RESOURCE_IN_USE',
    'returns a helpful event message');

  _delete_test_reservations;
};

subtest 'cannot make a reservation when all resources have overlapping reservations' => sub {
  plan tests => 1;
  # First, create several new reservations in the future
  my $start_time = _future_time(13);
  my $end_time = _future_time(15);
  _create_test_reservation($start_time, $end_time, [1]);
  _create_test_reservation($start_time, $end_time, [2]);
  _create_test_reservation($start_time, $end_time, [3]);

  # Now, attempt to create a reservation that overlaps with all of the above
  $start_time->set( hour => 14 );
  $end_time->set( hour => 16 );
  my $results = _create_test_reservation($start_time, $end_time, undef);
  is($results->{textcode}, 'RESOURCE_IN_USE',
    'returns a helpful event message');

  _delete_test_reservations;
};

subtest 'can make a reservation when only some resources have overlapping reservations' => sub {
  plan tests => 2;
  # First, create reservations for resources 1 and 3 (but not 2)
  my $start_time = _future_time(13);
  my $end_time = _future_time(15);
  _create_test_reservation($start_time, $end_time, [1]);
  _create_test_reservation($start_time, $end_time, [3]);

  # Now, attempt to create a reservation that overlaps with 1 or 3 (but 2 should still be free)
  $start_time->set( hour => 14 );
  $end_time->set( hour => 16 );
  my $results = _create_test_reservation($start_time, $end_time, [2]);
  my $bresv_id = $results->[0]->{bresv};
  ok(Scalar::Util::looks_like_number($results->[0]->{bresv}),
    'the reservation was made successfully');
  my $reservation = $e->retrieve_booking_reservation($bresv_id);
  is($reservation->current_resource, 2,
     'the reservation was made for the resource without overlapping reservations');

  _delete_test_reservations;
};

subtest 'can make a reservation without specifying a resource' => sub {
  plan tests => 1;

  my $start_time = _future_time(13);
  my $end_time = _future_time(15);
  my $results = _create_test_reservation($start_time, $end_time, undef);
  my $bresv_id = $results->[0]->{bresv};
  ok(Scalar::Util::looks_like_number($results->[0]->{bresv}),
    'the reservation was made successfully');

  _delete_test_reservations;
};

