#!perl -T

use strict;
use warnings;

use Test::More tests => 3;
use Test::MockModule;
use Test::MockObject;

use_ok( 'OpenILS::Application::Actor::Carousel' );

my $fm_carousel = Test::MockObject->new();
$fm_carousel->set_true('bucket', 'name', 'type', 'owner', 'creator', 'editor', 'max_items');
$fm_carousel->set_always('id', 35);
$fm_carousel->fake_new( 'Fieldmapper::container::carousel' );

my $record_bucket = Test::MockObject->new();
$record_bucket->set_true('btype', 'id', 'name', 'owner', 'owning_lib', 'pub');
$record_bucket->fake_new( 'Fieldmapper::container::biblio_record_entry_bucket' );

my $editor = Test::MockModule->new('OpenILS::Utils::CStoreEditor')
	->redefine(authtoken => 1)
	->redefine(checkauth => 1)
	->redefine(allowed => 1)
	->redefine(xact_begin => 1)
	->redefine(xact_commit => 1)
	->redefine(requestor => _fake_requestor())
	->mock(create_container_carousel => 1)
	->mock(create_container_biblio_record_entry_bucket => 1)
	->mock(create_container_biblio_record_entry_bucket_item => 1)
	->mock(retrieve_container_carousel => $fm_carousel)
	->mock(update_container_carousel => 1)
	->mock(search_asset_copy => [])
	->mock(search_container_biblio_record_entry_bucket_item => _fake_bucket_items());

# -----------------------------------------------------------------------------
# method under test:    create_carousel_from_items
#
# test case:            authtoken is valid and user has the ADMIN_CAROUSEL permission
#
# expected outcome:     Returns the ID provided by a mocked Cstore call
# -----------------------------------------------------------------------------

is(OpenILS::Application::Actor::Carousel->create_carousel_from_items(
	'client', 'AUTH', 'My new bucket', [1, 2, 3]),
    35, 'returns the ID of the carousel');


# -----------------------------------------------------------------------------
# method under test:    create_carousel_from_items
#
# test case:            user does not have the ADMIN_CAROUSEL permission
#
# expected outcome:     Returns the ID provided by a mocked Cstore call
# -----------------------------------------------------------------------------

$editor->redefine(allowed => 0)
	->redefine(event => 'Permissions are bad');

is(OpenILS::Application::Actor::Carousel->create_carousel_from_items(
	'client', 'AUTH', 'My new bucket', [1, 2, 3]),
   'Permissions are bad', 'returns the event');


sub _fake_bucket_items {
	my $item = Test::MockObject->new;
	$item->set_true('bucket', 'clear_id', 'create_time');
	return [$item, $item, $item];
}

sub _fake_requestor {
	my $user = Test::MockObject->new;
	$user->set_true('id', 'ws_ou');
	return $user;
}
