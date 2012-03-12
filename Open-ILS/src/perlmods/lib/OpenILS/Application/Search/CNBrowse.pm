package OpenILS::Application::Search::CNBrowse;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use Data::Dumper;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenSRF::AppSession;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
	method	=> "cn_browse_start",
	api_name	=> "open-ils.search.callnumber.browse.target",
	notes		=> "Starts a callnumber browse"
	);

__PACKAGE__->register_method(
	method	=> "cn_browse_up",
	api_name	=> "open-ils.search.callnumber.browse.page_up",
	notes		=> "Returns the previous page of callnumbers", 
	);

__PACKAGE__->register_method(
	method	=> "cn_browse_down",
	api_name	=> "open-ils.search.callnumber.browse.page_down",
	notes		=> "Returns the next page of callnumbers", 
	);

# XXX Deprecate me

sub cn_browse_start {
	my( $self, $client, @params ) = @_;
	my $method;
	$method = 'open-ils.storage.asset.call_number.browse.target.atomic' 
		if( $self->api_name =~ /target/ );
	$method = 'open-ils.storage.asset.call_number.browse.page_up'
		if( $self->api_name =~ /page_up/ );
	$method = 'open-ils.storage.asset.call_number.browse.page_down'
		if( $self->api_name =~ /page_down/ );

	return $U->simplereq( 'open-ils.storage', $method, @params );
}


__PACKAGE__->register_method(
	method => "cn_browse",
	api_name => "open-ils.search.callnumber.browse",
    signature => {
        desc => q/Paged call number browse/,
        params => [
            { name => 'label',
              desc => 'The target call number lable',
              type => 'string' },
            { name => 'org_unit',
              desc => 'The org unit shortname (or "-" or undef for global) to browse',
              type => 'string' },
            { name => 'page_size',
              desc => 'Count of call numbers to retrieve, default is 9',
              type => 'number' },
            { name => 'offset',
              desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
              type => 'number' },
            { name => 'statuses',
              desc => 'Array of statuses to filter copies by, optional and can be undef.',
              type => 'array' },
            { name => 'locations',
              desc => 'Array of copy locations to filter copies by, optional and can be undef.',
              type => 'array' },
        ],
        return => {
            type => 'array',
            desc => q/List of callnumber (acn) and record (mvr) objects/
        }
    }
);

sub cn_browse {
	my( $self, $conn, $cn, $orgid, $size, $offset, $copy_statuses, $copy_locations ) = @_;
	my $ses = OpenSRF::AppSession->create('open-ils.supercat');

	my $tree = $U->get_org_tree;
	my $name = _find_shortname($orgid, $tree);

	$logger->debug("cn browse found or name $name");

	my $data = $ses->request(
		'open-ils.supercat.call_number.browse', 
		$cn, $name, $size, $offset, $copy_statuses, $copy_locations )->gather(1);

	return [] unless $data;

	my @res;
	for my $d (@$data) {
		my $mods = $U->record_to_mvr($d->record);
		$d->owning_lib( $d->owning_lib->id );
		$d->record($mods->doc_id);
		push( @res, { cn	=> $d, mods	=> $mods });
	}

	return \@res;
}


sub _find_shortname {
	my $id = shift;
	my $node = shift;
	return undef unless $node;
	return $node->shortname if $node->id == $id;
	if( $node->children ) {
		for my $c (@{$node->children()}) {
			my $d = _find_shortname($id, $c);
			return $d if $d;
		}
	}
	return undef;
}

1;

