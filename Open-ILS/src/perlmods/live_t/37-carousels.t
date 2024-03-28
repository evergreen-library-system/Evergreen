#!perl

use strict; use warnings;
use Test::More tests => 3;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use Digest::SHA qw(sha1);

diag('Test carousels');

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

# we need auth to access protected APIs
$script->authenticate({
    username => 'admin', # local administrator at BR1
    password => 'demo123',
    type => 'staff'});

my $authtoken = $script->authtoken;
ok($authtoken, 'Have an authtoken');

my $e = new_editor(xact => 1);
$e->init;

use constant {
    BUCKET_NAME => sha1(time)
};

subtest 'can associate a carousel with an existing record bucket' => sub {
    plan tests => 5;
    my $bucket = Fieldmapper::container::biblio_record_entry_bucket->new;
    $bucket->name(BUCKET_NAME);
    $bucket->owner(1);
    $bucket->btype('staff_client');
    $bucket->pub('t');
    $bucket->owning_lib(1);

    my $bucket_id = $apputils->simplereq('open-ils.actor',
                                         'open-ils.actor.container.create',
                                         $authtoken, 'biblio', $bucket);

    my @record_ids = ( 1, 2 );
    $apputils->simplereq('open-ils.actor',
                         'open-ils.actor.container.item.create.batch',
                         $authtoken, 'biblio_record_entry',
                         $bucket_id, \@record_ids );

    my $carousel_id = $apputils->simplereq('open-ils.actor',
                                           'open-ils.actor.carousel.create.from_bucket',
                                           $authtoken, 'My nice carousel', $bucket_id);

    my $carousel_contents = $apputils->simplereq('open-ils.actor',
                                                 'open-ils.actor.carousel.get_contents',
                                                 $carousel_id);
    my $bibs = $carousel_contents->{'bibs'};
    is(scalar(@{ $bibs }), 2, 'Both records made it into the carousel');
    is(@{ $bibs }[0]->{'id'}, 1, 'Carousel can find the first record in our bucket');
    is(@{ $bibs }[1]->{'id'}, 2, 'Carousel can find the other record in our bucket');

    # Cleanup
    my $carousel_object = $e->retrieve_container_carousel($carousel_id);
    $e->xact_begin;
    $e->delete_container_carousel($carousel_object);
    $e->xact_commit;

    $apputils->simplereq('open-ils.actor',
                         'open-ils.actor.container.full_delete',
                         $authtoken, 'biblio', $bucket_id);

    my $results = $e->search_container_carousel({id => $carousel_id});
    is(scalar(@{ $results }), 0, 'Successfully deleted carousel');

    $results = $e->search_container_biblio_record_entry_bucket({id => $bucket_id});
    is(scalar(@{ $results }), 0, 'Successfully deleted bucket');
};

subtest('creating carousel from items', sub {
    plan tests => 1;

    subtest('when items are attached to the same bib record', sub {
        plan tests => 1;
        my @item_ids = ( 1, 101, 201, 501 ); # 4 items that are all attached to the same bib record
        my $carousel_id = $apputils->simplereq('open-ils.actor',
                                               'open-ils.actor.carousel.create_carousel_from_items',
                                               $authtoken,
                                               'Here is my new carousel',
                                               \@item_ids);
        my $carousel = $e->retrieve_container_carousel($carousel_id);
        my $bucket = $apputils->simplereq('open-ils.actor',
                                          'open-ils.actor.container.flesh.authoritative',
                                          $authtoken,
                                          'biblio',
                                          $carousel->bucket);
        is(scalar(@{ $bucket->items }), 1, 'duplicate records are only added once');
    });
});

my $carousel = $e->search_container_carousel({name => 'Here is my new carousel'})->[0];
$apputils->simplereq('open-ils.actor',
                        'open-ils.actor.container.full_delete',
                        $authtoken,
                        'biblio',
                        $carousel->bucket);
$e->xact_begin;
$e->delete_container_carousel($carousel);
$e->xact_commit;
