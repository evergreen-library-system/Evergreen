package OpenILS::Application::Actor::Carousel;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::JSON;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

__PACKAGE__->register_method(
    method  => "get_carousel_contents",
    api_name    => "open-ils.actor.carousel.get_contents",
    authoritative => 1,
    notes        => <<"    NOTES");
        Given a carousel ID, returns the carousel name and any publicly-visible
        bibs from the associated bucket
        PARAMS(carousel_id)
    NOTES

sub get_carousel_contents {
    my($self, $client, $id) = @_;
    my $e = new_editor();
    my $carousel = $e->retrieve_container_carousel($id);
    my $ret = {
        id   => $id,
        name => $carousel->name
    };
    my $q = {
        select => { bre => ['id'], rmsr => ['title','author'] },
        from   => {
            cbrebi => {
                cbreb => {
                    join => { cc => {} }
                },
                bre => {
                    join => { rmsr => { fkey => 'id', field => 'id' } }
                }
            }
        },
        where  => {
            '+cc' => { id => $id },
            '+bre' => { deleted => 'f' }
        },
        order_by => {cbrebi => ['pos','create_time']}
    };
    my $r = $e->json_query($q);
    $ret->{bibs} = $r;
    return $ret;
}

__PACKAGE__->register_method(
    method  => "retrieve_carousels_at_org",
    api_name    => "open-ils.actor.carousel.retrieve_by_org",
    authoritative => 1,
    notes        => <<"    NOTES");
        Retrieves the IDs and override names of all carousels visible
        at the specified org unit sorted by their sequence number at
        that library
        PARAMS(OrgId)
    NOTES

sub retrieve_carousels_at_org {
    my($self, $client, $org_id) = @_;
    my $e = new_editor();

    my $carousels = $e->json_query({
        select => { ccou => ['carousel','override_name','seq'], cc => ['name'] },
        distinct => 'true',
        from => { ccou => 'cc' } ,
        where => {
            '+ccou' => { org_unit => $org_id },
            '+cc'   => { active => 't' }
        },
        order_by => {
            'ccou' => ['seq']
        }
    });

    return $carousels;
}

__PACKAGE__->register_method(
    method  => "retrieve_manual_carousels_for_staff",
    api_name    => "open-ils.actor.carousel.retrieve_manual_by_staff",
    authoritative => 1,
    notes        => <<"    NOTES");
        Retrieves the IDs, buckets, and names of all manually-maintained
        carousels visible at any of the staff members working
        locations.
        PARAMS(authtoken)
    NOTES

sub retrieve_manual_carousels_for_staff {
    my($self, $client, $auth) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $orgs = [];
    if ($e->requestor->super_user eq 't') {
        # super users can act/see at all OUs
        my $ous = $e->json_query({
            select => { aou => ['id'] },
            from => 'aou'
        });
        $orgs = [ map { $_->{id} } @$ous ];
    } else {
        my $ous = $e->json_query({
            select => { puwoum => ['work_ou'] },
            from => 'puwoum',
            where => {
                '+puwoum' => { usr => $e->requestor->id }
            }
        });
        $orgs = [ map { $_->{work_ou} } @$ous ];
    }

    my $carousels = $e->json_query({
        select => { cc => ['id','name','bucket'] },
        distinct => 'true',
        from => { cc => 'ccou' },
        where => {
            '+ccou' => { org_unit => $orgs },
            '+cc'   => { type => 1, active => 't' }, # FIXME
        },
        order_by => {
            'cc' => ['name']
        }
    });

    return $carousels;
}

__PACKAGE__->register_method(
    method  => "refresh_carousel",
    api_name    => "open-ils.actor.carousel.refresh",
    authoritative => 1,
    notes        => <<"    NOTES");
        Refreshes the specified carousel
        PARAMS(authtoken, carousel_id)
    NOTES

sub refresh_carousel {
    my ($self, $client, $auth, $carousel_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('REFRESH_CAROUSEL');

    my $carousel;
    $carousel = $e->retrieve_container_carousel($carousel_id) or return $e->event;

    return $e->event unless $e->allowed('REFRESH_CAROUSEL', $carousel->owner, $carousel);

    my $ctype;
    $ctype = $e->retrieve_config_carousel_type($carousel->type) or return $e->event;
    return new OpenILS::Event('CANNOT_REFRESH_MANUAL_CAROUSEL') unless $ctype->automatic eq 't';

    my $orgs = [];
    my $locs = [];
    if (defined($carousel->owning_lib_filter)) {
        my $ou_filter = $carousel->owning_lib_filter;
        $ou_filter =~ s/[{}]//g;
        @$orgs = split /,/, $ou_filter;
    }
    if (defined($carousel->copy_location_filter)) {
        my $loc_filter = $carousel->copy_location_filter;
        $loc_filter =~ s/[{}]//g;
        @$locs = split /,/, $loc_filter;
    }

    my $num_updated = $U->simplereq(
        'open-ils.storage',
        'open-ils.storage.container.refresh_from_carousel',
        $carousel->bucket,
        $carousel->type,
        $carousel->age_filter,
        $orgs,
        $locs,
        $carousel->max_items,
    );

    $carousel->last_refresh_time('now');
    $e->xact_begin;
    $e->update_container_carousel($carousel) or return $e->event;
    $e->xact_commit or return $e->event;

    return $num_updated;
}

__PACKAGE__->register_method(
    method  => "add_carousel_from_bucket",
    api_name    => "open-ils.actor.carousel.create.from_bucket",
    authoritative => 1,
    notes        => <<"    NOTES");
        Creates new carousel and its container by copying the
        contents of an existing bucket.
        PARAMS(authtoken, carousel_name, bucket_id)
    NOTES

sub add_carousel_from_bucket {
    my ($self, $client, $auth, $carousel_name, $bucket_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('ADMIN_CAROUSEL');

    $e->xact_begin;

    # gather old entries to get a count and set max_items appropriately
    my $entries = $e->search_container_biblio_record_entry_bucket_item({ bucket => $bucket_id });

    my $carousel = Fieldmapper::container::carousel->new;
    $carousel->name($carousel_name);
    $carousel->type(1); # manual
    $carousel->owner($e->requestor->ws_ou);
    $carousel->creator($e->requestor->id);
    $carousel->editor($e->requestor->id);
    $carousel->max_items(scalar(@$entries));
    $carousel->bucket($bucket_id);
    $e->create_container_carousel($carousel) or return $e->event;

    $e->xact_commit or return $e->event;

    return $carousel->id;
}

__PACKAGE__->register_method(
    method => "create_carousel_from_items",
    api_name => "open-ils.actor.carousel.create_carousel_from_items",
    signature => {
        desc => q/Create a new carousel populated with the records connected to the requested items/,
        params => [
            { name => 'authtoken',
              desc => 'A user authtoken',
              type => 'string' },
            { name => 'carousel_name',
              desc => 'A name for the new carousel',
              type => 'string' },
            { name => 'items',
              desc => 'Array of copy locations to filter copies by, optional and can be undef.',
              type => 'array' }
        ],
        return => {
            type => 'int',
            desc => q/The id of the new carousel/
        }
    }
);

sub create_carousel_from_items {
    my ($self, $client, $auth, $carousel_name, $item_ids) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('ADMIN_CAROUSEL');

    $e->xact_begin;
    my $bucket = Fieldmapper::container::biblio_record_entry_bucket->new;
    $bucket->owner($e->requestor->id);
    $bucket->name('New bucket created from items by ' . $e->requestor->id . ' on ' . localtime());
    $bucket->btype('carousel');
    $bucket->pub('t');
    $bucket->owning_lib($e->requestor->ws_ou);
    $e->create_container_biblio_record_entry_bucket($bucket) or return $e->event;

    my $bre_ids = _acp_ids_to_bre_ids($e, $item_ids);

    my $carousel = Fieldmapper::container::carousel->new;
    $carousel->name($carousel_name);
    $carousel->type(1); # manual
    $carousel->owner($e->requestor->ws_ou);
    $carousel->creator($e->requestor->id);
    $carousel->editor($e->requestor->id);
    $carousel->max_items(scalar(@$bre_ids));
    $carousel->bucket($bucket->id);
    $e->create_container_carousel($carousel) or return $e->event;

    foreach my $bre_id (@$bre_ids) {
        my $entry = Fieldmapper::container::biblio_record_entry_bucket_item->new;
        $entry->target_biblio_record_entry($bre_id);
        $entry->bucket($bucket->id);
        $entry->create_time('now');
        $e->create_container_biblio_record_entry_bucket_item($entry) or return $e->event;
    }

    $e->xact_commit or return $e->event;

    return $carousel->id;
}

sub _acp_ids_to_bre_ids {
    my ($e, $item_ids) = @_;
    my $items = $e->search_asset_copy([
        {id => $item_ids},
        {flesh => 1, flesh_fields => {acp => ['call_number']}}
    ]);
    my @bre_ids = map { $_->call_number->record } @$items;
    return \@bre_ids;
}

1;
