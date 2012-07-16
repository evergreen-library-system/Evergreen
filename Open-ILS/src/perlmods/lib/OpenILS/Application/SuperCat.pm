# We'll be working with XML, so...
use XML::LibXML;
use XML::LibXSLT;
use Unicode::Normalize;

# ... and this has some handy common methods
use OpenILS::Application::AppUtils;

my $parser = new XML::LibXML;
my $U = 'OpenILS::Application::AppUtils';


package OpenILS::Application::SuperCat;

use strict;
use warnings;
use OpenILS::Utils::Normalize qw( naco_normalize );

# All OpenSRF applications must be based on OpenSRF::Application or
# a subclass thereof.  Makes sense, eh?
use OpenILS::Application;
use base qw/OpenILS::Application/;

# This is the client class, used for connecting to open-ils.storage
use OpenSRF::AppSession;

# This is an extension of Error.pm that supplies some error types to throw
use OpenSRF::EX qw(:try);

# This is a helper class for querying the OpenSRF Settings application ...
use OpenSRF::Utils::SettingsClient;

# ... and here we have the built in logging helper ...
use OpenSRF::Utils::Logger qw($logger);

# ... and this is our OpenILS object (en|de)coder and psuedo-ORM package.
use OpenILS::Utils::Fieldmapper;

use OpenILS::Utils::CStoreEditor q/:funcs/;


our (
  $_parser,
  $_xslt,
  %record_xslt,
  %metarecord_xslt,
  %holdings_data_cache,
  %authority_browse_axis_cache,
);

sub child_init {
	# we need an XML parser
	$_parser = new XML::LibXML;

	# and an xslt parser
	$_xslt = new XML::LibXSLT;

	# parse the MODS xslt ...
	my $mods33_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS33.xsl"
	);
	# and stash a transformer
	$record_xslt{mods33}{xslt} = $_xslt->parse_stylesheet( $mods33_xslt );
	$record_xslt{mods33}{namespace_uri} = 'http://www.loc.gov/mods/v3';
	$record_xslt{mods33}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods33}{schema_location} = 'http://www.loc.gov/standards/mods/v3/mods-3-3.xsd';

	# parse the MODS xslt ...
	my $mods32_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS32.xsl"
	);
	# and stash a transformer
	$record_xslt{mods32}{xslt} = $_xslt->parse_stylesheet( $mods32_xslt );
	$record_xslt{mods32}{namespace_uri} = 'http://www.loc.gov/mods/v3';
	$record_xslt{mods32}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods32}{schema_location} = 'http://www.loc.gov/standards/mods/v3/mods-3-2.xsd';

	# parse the MODS xslt ...
	my $mods3_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS3.xsl"
	);
	# and stash a transformer
	$record_xslt{mods3}{xslt} = $_xslt->parse_stylesheet( $mods3_xslt );
	$record_xslt{mods3}{namespace_uri} = 'http://www.loc.gov/mods/v3';
	$record_xslt{mods3}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods3}{schema_location} = 'http://www.loc.gov/standards/mods/v3/mods-3-1.xsd';

	# parse the MODS xslt ...
	my $mods_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS.xsl"
	);
	# and stash a transformer
	$record_xslt{mods}{xslt} = $_xslt->parse_stylesheet( $mods_xslt );
	$record_xslt{mods}{namespace_uri} = 'http://www.loc.gov/mods/';
	$record_xslt{mods}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods}{schema_location} = 'http://www.loc.gov/standards/mods/mods.xsd';

	# parse the ATOM entry xslt ...
	my $atom_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2ATOM.xsl"
	);
	# and stash a transformer
	$record_xslt{atom}{xslt} = $_xslt->parse_stylesheet( $atom_xslt );
	$record_xslt{atom}{namespace_uri} = 'http://www.w3.org/2005/Atom';
	$record_xslt{atom}{docs} = 'http://www.ietf.org/rfc/rfc4287.txt';

	# parse the RDFDC xslt ...
	my $rdf_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2RDFDC.xsl"
	);
	# and stash a transformer
	$record_xslt{rdf_dc}{xslt} = $_xslt->parse_stylesheet( $rdf_dc_xslt );
	$record_xslt{rdf_dc}{namespace_uri} = 'http://purl.org/dc/elements/1.1/';
	$record_xslt{rdf_dc}{schema_location} = 'http://purl.org/dc/elements/1.1/';

	# parse the SRWDC xslt ...
	my $srw_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2SRWDC.xsl"
	);
	# and stash a transformer
	$record_xslt{srw_dc}{xslt} = $_xslt->parse_stylesheet( $srw_dc_xslt );
	$record_xslt{srw_dc}{namespace_uri} = 'info:srw/schema/1/dc-schema';
	$record_xslt{srw_dc}{schema_location} = 'http://www.loc.gov/z3950/agency/zing/srw/dc-schema.xsd';

	# parse the OAIDC xslt ...
	my $oai_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2OAIDC.xsl"
	);
	# and stash a transformer
	$record_xslt{oai_dc}{xslt} = $_xslt->parse_stylesheet( $oai_dc_xslt );
	$record_xslt{oai_dc}{namespace_uri} = 'http://www.openarchives.org/OAI/2.0/oai_dc/';
	$record_xslt{oai_dc}{schema_location} = 'http://www.openarchives.org/OAI/2.0/oai_dc.xsd';

	# parse the RSS xslt ...
	my $rss_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2RSS2.xsl"
	);
	# and stash a transformer
	$record_xslt{rss2}{xslt} = $_xslt->parse_stylesheet( $rss_xslt );

	# parse the FGDC xslt ...
	my $fgdc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2FGDC.xsl"
	);
	# and stash a transformer
	$record_xslt{fgdc}{xslt} = $_xslt->parse_stylesheet( $fgdc_xslt );
	$record_xslt{fgdc}{docs} = 'http://www.fgdc.gov/metadata/csdgm/index_html';
	$record_xslt{fgdc}{schema_location} = 'http://www.fgdc.gov/metadata/fgdc-std-001-1998.xsd';

	register_record_transforms();

	register_new_authorities_methods();

	return 1;
}

sub register_record_transforms {
	for my $type ( keys %record_xslt ) {
		__PACKAGE__->register_method(
			method    => 'retrieve_record_transform',
			api_name  => "open-ils.supercat.record.$type.retrieve",
			api_level => 1,
			argc      => 1,
			signature =>
				{ desc     => "Returns the \U$type\E representation ".
				              "of the requested bibliographic record",
				  params   =>
			  		[
						{ name => 'bibId',
						  desc => 'An OpenILS biblio::record_entry id',
						  type => 'number' },
					],
			  	'return' =>
		  			{ desc => "The bib record in \U$type\E",
					  type => 'string' }
				}
		);

		__PACKAGE__->register_method(
			method    => 'retrieve_isbn_transform',
			api_name  => "open-ils.supercat.isbn.$type.retrieve",
			api_level => 1,
			argc      => 1,
			signature =>
				{ desc     => "Returns the \U$type\E representation ".
				              "of the requested bibliographic record",
				  params   =>
			  		[
						{ name => 'isbn',
						  desc => 'An ISBN',
						  type => 'string' },
					],
			  	'return' =>
		  			{ desc => "The bib record in \U$type\E",
					  type => 'string' }
				}
		);
	}
}

sub register_new_authorities_methods {
    my %register_args = (
        method    => "generic_new_authorities_method",
        api_level => 1,
        argc      => 1,
        signature => {
            desc => q/Generated method/,
            params => [
                {name => "what",
                    desc => "An axis, an authority tag number, or a bibliographic tag number, depending on invocation",
                    type => "string"},
                {name => "term",
                    desc => "A search term",
                    type => "string"},
                {name => "page",
                    desc => "zero-based page number of results",
                    type => "number"},
                {name => "page size",
                    desc => "number of results per page",
                    type => "number"}
            ],
            return => {
                desc => "A list of authority record IDs", type => "array"
            }
        }
    );

    foreach my $how (qw/axis atag btag/) {
        foreach my $action (qw/browse_center browse_top
            search_rank search_heading/) {

            $register_args{api_name} =
                "open-ils.supercat.authority.$action.by_$how";
            __PACKAGE__->register_method(%register_args);

            $register_args{api_name} =
                "open-ils.supercat.authority.$action.by_$how.refs";
            __PACKAGE__->register_method(%register_args);

        }
    }
}

sub generic_new_authorities_method {
    my $self = shift;
    my $client = shift;

    # We want to be extra careful with these arguments, since the next
    # thing we're doing with them is passing them to a DB procedure.
    my $what = ''.shift;
    my $term = ''.shift;
    my $page = int(shift || 0);
    my $page_size = shift;

    # undef ok, but other non numbers not ok
    $page_size = int($page_size) if defined $page_size;

    # Figure out how we were called and what DB procedure we'll call in turn.
    $self->api_name =~ /\.by_(\w+)($|\.)/;
    my $metaaxis = $1;
    my $refs = $2;

    $self->api_name =~ /authority\.(\w+)\./;
    my $action = $1;

    my $method = "${metaaxis}_$action";
    $method .= "_refs" if $refs;

    # Match authority.full_rec normalization
    # XXX don't know whether we need second arg 'subfield'?
    $term = naco_normalize($term);

    my $storage = create OpenSRF::AppSession("open-ils.storage");
    my $list = $storage->request(
        "open-ils.storage.authority.in_db.browse_or_search",
        $method, $what, $term, $page, $page_size
    )->gather(1);

    $storage->kill_me;

    return $list;
}


sub tree_walker {
	my $tree = shift;
	my $field = shift;
	my $filter = shift;

	return unless ($tree && ref($tree->$field));

	my @things = $filter->($tree);
	for my $v ( @{$tree->$field} ){
		push @things, $filter->($v);
		push @things, tree_walker($v, $field, $filter);
	}
	return @things
}

# find a label_sortkey for a call number with a label which is equal
# (or close to) a given label value
sub _label_sortkey_from_label {
	my ($label, $_storage, $ou_ids, $cp_filter) = @_;

	my $closest_cn = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label      => { ">=" => { transform => "oils_text_as_bytea", value => ["oils_text_as_bytea", $label] } },
			  owning_lib => $ou_ids,
			  deleted    => 'f',
			  @$cp_filter
			},
			{ limit     => 1,
			  order_by  => { acn => "oils_text_as_bytea(label), id" }
			}
		)->gather(1);
	if (@$closest_cn) {
		return $closest_cn->[0]->label_sortkey;
	} else {
		return '~~~'; #fallback to high ascii value, we are at the end
	}
}

sub cn_browse {
	my $self = shift;
	my $client = shift;

	my $label = shift;
	my $ou = shift;
	my $page_size = shift || 9;
	my $page = shift || 0;
	my $statuses = shift || [];
	my $copy_locations = shift || [];

	my ($before_limit,$after_limit) = (0,0);
	my ($before_offset,$after_offset) = (0,0);

	if (!$page) {
		$before_limit = $after_limit = int($page_size / 2);
		$after_limit += 1 if ($page_size % 2);
	} else {
		$before_offset = $after_offset = int($page_size / 2);
		$before_offset += 1 if ($page_size % 2);
		$before_limit = $after_limit = $page_size;
	}

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $o_search = { shortname => $ou };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

	my $orgs = $_storage->request(
		"open-ils.cstore.direct.actor.org_unit.search",
		$o_search,
		{ flesh		=> 100,
		  flesh_fields	=> { aou	=> [qw/children/] }
		}
	)->gather(1);

	my @ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;

	$logger->debug("Searching for CNs at orgs [".join(',',@ou_ids)."], based on $ou");

	my @list = ();

    my @cp_filter = ();
    if (@$statuses || @$copy_locations) {
        @cp_filter = (
            '-exists' => {
                from  => 'acp',
				where => {
                    call_number => { '=' => { '+acn' => 'id' } },
                    deleted     => 'f',
                    ((@$statuses)       ? ( status   => $statuses)       : ()),
				    ((@$copy_locations) ? ( location => $copy_locations) : ())
                }
            }
        );
    }

	my $label_sortkey = _label_sortkey_from_label($label, $_storage, \@ou_ids, \@cp_filter);

	if ($page <= 0) {
		my $before = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label_sortkey	=> { "<" => { transform => "oils_text_as_bytea", value => ["oils_text_as_bytea", $label_sortkey] } },
			  owning_lib	=> \@ou_ids,
              deleted => 'f',
              @cp_filter
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib prefix suffix/] },
			  order_by	=> { acn => "oils_text_as_bytea(label_sortkey) desc, oils_text_as_bytea(label) desc, id desc, owning_lib desc" },
			  limit		=> $before_limit,
			  offset	=> abs($page) * $page_size - $before_offset,
			}
		)->gather(1);
		push @list, reverse(@$before);
	}

	if ($page >= 0) {
		my $after = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label_sortkey	=> { ">=" => { transform => "oils_text_as_bytea", value => ["oils_text_as_bytea", $label_sortkey] } },
			  owning_lib	=> \@ou_ids,
              deleted => 'f',
              @cp_filter
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib prefix suffix/] },
			  order_by	=> { acn => "oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib" },
			  limit		=> $after_limit,
			  offset	=> abs($page) * $page_size - $after_offset,
			}
		)->gather(1);
		push @list, @$after;
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'cn_browse',
	api_name  => 'open-ils.supercat.call_number.browse',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'label',
				  desc => 'The target call number label',
				  type => 'string' },
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to browse',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
				{ name => 'statuses',
				  desc => 'Array of statuses to filter copies by, optional and can be undef.',
				  type => 'array' },
				{ name => 'locations',
				  desc => 'Array of copy locations to filter copies by, optional and can be undef.',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Call numbers with owning_lib and record fleshed',
			  type => 'array' }
		}
);

sub cn_startwith {
	my $self = shift;
	my $client = shift;

	my $label = shift;
	my $ou = shift;
	my $limit = shift || 10;
	my $page = shift || 0;
	my $statuses = shift || [];
	my $copy_locations = shift || [];


	my $offset = abs($page) * $limit;
	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $o_search = { shortname => $ou };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

	my $orgs = $_storage->request(
		"open-ils.cstore.direct.actor.org_unit.search",
		$o_search,
		{ flesh		=> 100,
		  flesh_fields	=> { aou	=> [qw/children/] }
		}
	)->gather(1);

	my @ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;

	$logger->debug("Searching for CNs at orgs [".join(',',@ou_ids)."], based on $ou");

	my @list = ();

    my @cp_filter = ();
    if (@$statuses || @$copy_locations) {
        @cp_filter = (
            '-exists' => {
                from  => 'acp',
				where => {
                    call_number => { '=' => { '+acn' => 'id' } },
                    deleted     => 'f',
                    ((@$statuses)       ? ( status   => $statuses)       : ()),
				    ((@$copy_locations) ? ( location => $copy_locations) : ())
                }
            }
        );
    }

	my $label_sortkey = _label_sortkey_from_label($label, $_storage, \@ou_ids, \@cp_filter);

	if ($page < 0) {
		my $before = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label_sortkey	=> { "<" => { transform => "oils_text_as_bytea", value => ["oils_text_as_bytea", $label_sortkey] } },
			  owning_lib	=> \@ou_ids,
              deleted => 'f',
              @cp_filter
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib prefix suffix/] },
			  order_by	=> { acn => "oils_text_as_bytea(label_sortkey) desc, oils_text_as_bytea(label) desc, id desc, owning_lib desc" },
			  limit		=> $limit,
			  offset	=> $offset,
			}
		)->gather(1);
		push @list, reverse(@$before);
	}

	if ($page >= 0) {
		my $after = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label_sortkey	=> { ">=" => { transform => "oils_text_as_bytea", value => ["oils_text_as_bytea", $label_sortkey] } },
			  owning_lib	=> \@ou_ids,
              deleted => 'f',
              @cp_filter
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib prefix suffix/] },
			  order_by	=> { acn => "oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib" },
			  limit		=> $limit,
			  offset	=> $offset,
			}
		)->gather(1);
		push @list, @$after;
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'cn_startwith',
	api_name  => 'open-ils.supercat.call_number.startwith',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'label',
				  desc => 'The target call number label',
				  type => 'string' },
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to browse',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
				{ name => 'statuses',
				  desc => 'Array of statuses to filter copies by, optional and can be undef.',
				  type => 'array' },
				{ name => 'locations',
				  desc => 'Array of copy locations to filter copies by, optional and can be undef.',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Call numbers with owning_lib and record fleshed',
			  type => 'array' }
		}
);


sub new_books_by_item {
	my $self = shift;
	my $client = shift;

	my $ou = shift;
	my $page_size = shift || 10;
	my $page = shift || 1;
	my $statuses = shift || [];
	my $copy_locations = shift || [];

    my $offset = $page_size * ($page - 1);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my @ou_ids;
	if ($ou && $ou ne '-') {
		my $orgs = $_storage->request(
			"open-ils.cstore.direct.actor.org_unit.search",
			{ shortname => $ou },
			{ flesh		=> 100,
			  flesh_fields	=> { aou	=> [qw/children/] }
			}
		)->gather(1);
		@ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;
	}

	$logger->debug("Searching for records with new copies at orgs [".join(',',@ou_ids)."], based on $ou");
	my $cns = $_storage->request(
		"open-ils.cstore.json_query.atomic",
		{ select	=> { acn => ['record'],
                         acp => [{ aggregate => 1 => transform => max => column => create_date => alias => 'create_date'}]
                       },
		  from		=> { 'acn' => { 'acp' => { field => call_number => fkey => 'id' } } },
		  where		=>
			{ '+acp' =>
				{ deleted => 'f',
				  ((@ou_ids)          ? ( circ_lib => \@ou_ids)        : ()),
				  ((@$statuses)       ? ( status   => $statuses)       : ()),
				  ((@$copy_locations) ? ( location => $copy_locations) : ())
				}, 
			  '+acn' => { record => { '>' => 0 } },
			}, 
		  order_by	=> { acp => { create_date => { transform => 'max', direction => 'desc' } } },
		  limit		=> $page_size,
		  offset	=> $offset
		}
	)->gather(1);

	return [ map { $_->{record} } @$cns ];
}
__PACKAGE__->register_method(
	method    => 'new_books_by_item',
	api_name  => 'open-ils.supercat.new_book_list',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to list',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of records to retrieve, default is 10',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of records to retrieve, calculated based on page_size.  Starts at 1.',
				  type => 'number' },
				{ name => 'statuses',
				  desc => 'Array of statuses to filter copies by, optional and can be undef.',
				  type => 'array' },
				{ name => 'locations',
				  desc => 'Array of copy locations to filter copies by, optional and can be undef.',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Record IDs',
			  type => 'array' }
		}
);


sub general_browse {
	my $self = shift;
	my $client = shift;
    return tag_sf_browse($self, $client, $self->{tag}, $self->{subfield}, @_);
}
__PACKAGE__->register_method(
	method    => 'general_browse',
	api_name  => 'open-ils.supercat.title.browse',
	tag       => 'tnf', subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_browse',
	api_name  => 'open-ils.supercat.author.browse',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_browse',
	api_name  => 'open-ils.supercat.subject.browse',
	tag       => [qw/600 610 611 630 648 650 651 653 655 656 662 690 691 696 697 698 699/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_browse',
	api_name  => 'open-ils.supercat.topic.browse',
	tag       => [qw/650 690/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_browse',
	api_name  => 'open-ils.supercat.series.browse',
	tag       => [qw/440 490 800 810 811 830/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target series', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);


sub tag_sf_browse {
	my $self = shift;
	my $client = shift;

	my $tag = shift;
	my $subfield = shift;
	my $value = shift;
	my $ou = shift;
	my $page_size = shift || 9;
	my $page = shift || 0;
	my $statuses = shift || [];
	my $copy_locations = shift || [];

	my ($before_limit,$after_limit) = (0,0);
	my ($before_offset,$after_offset) = (0,0);

	if (!$page) {
		$before_limit = $after_limit = int($page_size / 2);
		$after_limit += 1 if ($page_size % 2);
	} else {
		$before_offset = $after_offset = int($page_size / 2);
		$before_offset += 1 if ($page_size % 2);
		$before_limit = $after_limit = $page_size;
	}

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my @ou_ids;
	if ($ou && $ou ne '-') {
		my $orgs = $_storage->request(
			"open-ils.cstore.direct.actor.org_unit.search",
			{ shortname => $ou },
			{ flesh		=> 100,
			  flesh_fields	=> { aou	=> [qw/children/] }
			}
		)->gather(1);
		@ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;
	}

	$logger->debug("Searching for records at orgs [".join(',',@ou_ids)."], based on $ou");

	my @list = ();

	if ($page <= 0) {
		my $before = $_storage->request(
			"open-ils.cstore.json_query.atomic",
			{ select	=> { mfr => [qw/record value/] },
			  from		=> 'mfr',
			  where		=>
				{ '+mfr'	=>
					{ tag	=> $tag,
					  subfield => $subfield,
					  value => { '<' => lc($value) }
					},
                  '-or' => [
		    		{ '-exists'	=>
	    				{ select=> { acp => [ 'id' ] },
    					  from	=> { acn => { acp => { field => 'call_number', fkey => 'id' } } },
					      where	=>
				    		{ '+acn' => { record => { '=' => { '+mfr' => 'record' } } },
			    			  '+acp' =>
								{ deleted => 'f',
								  ((@ou_ids)          ? ( circ_lib => \@ou_ids)        : ()),
								  ((@$statuses)       ? ( status   => $statuses)       : ()),
								  ((@$copy_locations) ? ( location => $copy_locations) : ())
								}
		    				},
	    				  limit => 1
    					}
                    },
                    { '-exists'	=>
    					{ select=> { auri => [ 'id' ] },
	    				  from	=> { acn => { auricnm => { field => 'call_number', fkey => 'id', join => { auri => { field => 'id', fkey => 'uri' } } } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } }, (@ou_ids) ? ( owning_lib => \@ou_ids) : () },
				    		  '+auri' => { active => 't' }
					    	},
    					  limit => 1
	    				}
                    }
                  ]
				}, 
			  order_by	=> { mfr => { value => 'desc' } },
			  limit		=> $before_limit,
			  offset	=> abs($page) * $page_size - $before_offset,
			}
		)->gather(1);
		push @list, map { $_->{record} } reverse(@$before);
	}

	if ($page >= 0) {
		my $after = $_storage->request(
			"open-ils.cstore.json_query.atomic",
			{ select	=> { mfr => [qw/record value/] },
			  from		=> 'mfr',
			  where		=>
				{ '+mfr'	=>
					{ tag	=> $tag,
					  subfield => $subfield,
					  value => { '>=' => lc($value) }
					},
				  '-or' => [
                    { '-exists'	=>
    					{ select=> { acp => [ 'id' ] },
	    				  from	=> { acn => { acp => { field => 'call_number', fkey => 'id' } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } } },
			    			  '+acp' =>
								{ deleted => 'f',
								  ((@ou_ids)          ? ( circ_lib => \@ou_ids)        : ()),
								  ((@$statuses)       ? ( status   => $statuses)       : ()),
								  ((@$copy_locations) ? ( location => $copy_locations) : ())
								}
					    	},
    					  limit => 1
	    				}
                    },
                    { '-exists'	=>
    					{ select=> { auri => [ 'id' ] },
	    				  from	=> { acn => { auricnm => { field => 'call_number', fkey => 'id', join => { auri => { field => 'id', fkey => 'uri' } } } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } }, (@ou_ids) ? ( owning_lib => \@ou_ids) : () },
				    		  '+auri' => { active => 't' }
					    	},
    					  limit => 1
	    				},
                    }
                  ]
				}, 
			  order_by	=> { mfr => { value => 'asc' } },
			  limit		=> $after_limit,
			  offset	=> abs($page) * $page_size - $after_offset,
			}
		)->gather(1);
		push @list, map { $_->{record} } @$after;
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'tag_sf_browse',
	api_name  => 'open-ils.supercat.tag.browse',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a list of the requested org-scoped record IDs held
		  DESC
		  params   =>
		  	[
				{ name => 'tag',
				  desc => 'The target MARC tag',
				  type => 'string' },
				{ name => 'subfield',
				  desc => 'The target MARC subfield',
				  type => 'string' },
				{ name => 'value',
				  desc => 'The target string',
				  type => 'string' },
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to browse',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
				{ name => 'statuses',
				  desc => 'Array of statuses to filter copies by, optional and can be undef.',
				  type => 'array' },
				{ name => 'locations',
				  desc => 'Array of copy locations to filter copies by, optional and can be undef.',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Record IDs that have copies at the relevant org units',
			  type => 'array' }
		}
);

sub grab_authority_browse_axes {
    my ($self, $client, $full) = @_;

    unless(scalar(keys(%authority_browse_axis_cache))) {
        my $axes = new_editor->search_authority_browse_axis([
            { code => { '<>' => undef } },
            { flesh => 2, flesh_fields => { aba => ['fields'], acsaf => ['bib_fields','sub_entries'] } }
        ]);
        $authority_browse_axis_cache{$_->code} = $_ for (@$axes);
    }

    if ($full) {
        return [
            map { $authority_browse_axis_cache{$_} } sort keys %authority_browse_axis_cache
        ];
    } else {
        return [keys %authority_browse_axis_cache];
    }
}
__PACKAGE__->register_method(
	method    => 'grab_authority_browse_axes',
	api_name  => 'open-ils.supercat.authority.browse_axis_list',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of valid authority browse/startswith axes",
		  params   => [
              { name => 'full', desc => 'Optional. If true, return array containing the full object for each axis, sorted by code. Otherwise just return an array of the codes.', type => 'number' }
          ],
		  'return' => { desc => 'Axis codes or whole axes, see "full" param', type => 'array' }
		}
);

sub axis_authority_browse {
	my $self = shift;
	my $client = shift;
    my $axis = shift;

    $axis =~ s/^authority\.//;
    $axis =~ s/(\.refs)$//;
    my $refs = $1;

    return undef unless ( grep { /$axis/ } @{ grab_authority_browse_axes() } );

    my @tags;
    for my $f (@{$authority_browse_axis_cache{$axis}->fields}) {
        push @tags, $f->tag;
        if ($refs) {
            push @tags, $_->tag for @{$f->sub_entries};
        }
    }

    return authority_tag_sf_browse($self, $client, \@tags, 'a', @_); # XXX TODO figure out something more correct for the subfield param
}
__PACKAGE__->register_method(
	method    => 'axis_authority_browse',
	api_name  => 'open-ils.supercat.authority.browse.by_axis',
	api_level => 1,
	argc      => 2,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'axis', desc => 'The target axis', type => 'string' },
		  	  { name => 'value', desc => 'The target value', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);

=pod

sub general_authority_browse {
	my $self = shift;
	my $client = shift;
    return authority_tag_sf_browse($self, $client, $self->{tag}, $self->{subfield}, @_);
}
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.title.browse',
	tag       => ['130'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.author.browse',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.subject.browse',
	tag       => [qw/148 150 151 155/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.topic.browse',
	tag       => ['150'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.title.refs.browse',
	tag       => ['130'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.author.refs.browse',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.subject.refs.browse',
	tag       => [qw/148 150 151 155/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_browse',
	api_name  => 'open-ils.supercat.authority.topic.refs.browse',
	tag       => ['150'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);

=cut

sub authority_tag_sf_browse {
    my $self = shift;
    my $client = shift;

    my $tag = shift;
    my $subfield = shift;
    my $value = shift;
    my $page_size = shift || 9;
    my $page = shift || 0;

    # Match authority.full_rec normalization
    $value = naco_normalize($value, $subfield);

    my ($before_limit,$after_limit) = (0,0);
    my ($before_offset,$after_offset) = (0,0);

    if (!$page) {
        $before_limit = $after_limit = int($page_size / 2);
        $after_limit += 1 if ($page_size % 2);
    } else {
        $before_offset = $after_offset = int($page_size / 2);
        $before_offset += 1 if ($page_size % 2);
        $before_limit = $after_limit = $page_size;
    }

    my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

    # .refs variant includes 4xx and 5xx variants for see / see also
    my @ref_tags = ();
    foreach my $tagname (@$tag) {
        push(@ref_tags, $tagname);
        if ($self->api_name =~ /\.refs\./) {
            push(@ref_tags, '4' . substr($tagname, 1, 2));
            push(@ref_tags, '5' . substr($tagname, 1, 2));
        }
    }
    my @list = ();

    if ($page <= 0) {
        my $before = $_storage->request(
            "open-ils.cstore.json_query.atomic",
            { select    => { afr => [qw/record value/] },
              from      => 'afr',
              where     => { tag => \@ref_tags, subfield => $subfield, value => { '<' => $value } },
              order_by  => { afr => { value => 'desc' } },
              limit     => $before_limit,
              offset    => abs($page) * $page_size - $before_offset,
            }
        )->gather(1);
        push @list, map { $_->{record} } reverse(@$before);
    }

    if ($page >= 0) {
        my $after = $_storage->request(
            "open-ils.cstore.json_query.atomic",
            { select    => { afr => [qw/record value/] },
              from      => 'afr',
              where     => { tag => \@ref_tags, subfield => $subfield, value => { '>=' => $value } },
              order_by  => { afr => { value => 'asc' } },
              limit     => $after_limit,
              offset    => abs($page) * $page_size - $after_offset,
            }
        )->gather(1);
        push @list, map { $_->{record} } @$after;
    }

    # If we're not pulling in see/see also references, just return the raw list
    if ($self->api_name !~ /\.refs\./) {
        return \@list;
    } 

    # Remove dupe record IDs that turn up due to 4xx and 5xx matches
    my @retlist = ();
    my %seen;
    foreach my $record (@list) {
        next if exists $seen{$record};
        push @retlist, int($record);
        $seen{$record} = 1;
    }

    return \@retlist;
}
__PACKAGE__->register_method(
	method    => 'authority_tag_sf_browse',
	api_name  => 'open-ils.supercat.authority.tag.browse',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a list of the requested authority record IDs held
		  DESC
		  params   =>
		  	[
				{ name => 'tag',
				  desc => 'The target Authority MARC tag',
				  type => 'string' },
				{ name => 'subfield',
				  desc => 'The target Authority MARC subfield',
				  type => 'string' },
				{ name => 'value',
				  desc => 'The target string',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'Authority Record IDs that are near the target string',
			  type => 'array' }
		}
);

sub general_startwith {
	my $self = shift;
	my $client = shift;
    return tag_sf_startwith($self, $client, $self->{tag}, $self->{subfield}, @_);
}
__PACKAGE__->register_method(
	method    => 'general_startwith',
	api_name  => 'open-ils.supercat.title.startwith',
	tag       => 'tnf', subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_startwith',
	api_name  => 'open-ils.supercat.author.startwith',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_startwith',
	api_name  => 'open-ils.supercat.subject.startwith',
	tag       => [qw/600 610 611 630 648 650 651 653 655 656 662 690 691 696 697 698 699/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_startwith',
	api_name  => 'open-ils.supercat.topic.startwith',
	tag       => [qw/650 690/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_startwith',
	api_name  => 'open-ils.supercat.series.startwith',
	tag       => [qw/440 490 800 810 811 830/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested org-scoped record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target series', type => 'string' },
			  { name => 'org_unit', desc => 'The org unit shortname (or "-" or undef for global) to browse', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 9', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' },
			  { name => 'statuses', desc => 'Array of statuses to filter copies by, optional and can be undef.', type => 'array' },
			  { name => 'locations', desc => 'Array of copy locations to filter copies by, optional and can be undef.', type => 'array' }, ],
		  'return' => { desc => 'Record IDs that have copies at the relevant org units', type => 'array' }
		}
);


sub tag_sf_startwith {
	my $self = shift;
	my $client = shift;

	my $tag = shift;
	my $subfield = shift;
	my $value = shift;
	my $ou = shift;
	my $limit = shift || 10;
	my $page = shift || 0;
	my $statuses = shift || [];
	my $copy_locations = shift || [];

	my $offset = $limit * abs($page);
	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my @ou_ids;
	if ($ou && $ou ne '-') {
		my $orgs = $_storage->request(
			"open-ils.cstore.direct.actor.org_unit.search",
			{ shortname => $ou },
			{ flesh		=> 100,
			  flesh_fields	=> { aou	=> [qw/children/] }
			}
		)->gather(1);
		@ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;
	}

	$logger->debug("Searching for records at orgs [".join(',',@ou_ids)."], based on $ou");

	my @list = ();

	if ($page < 0) {
		my $before = $_storage->request(
			"open-ils.cstore.json_query.atomic",
			{ select	=> { mfr => [qw/record value/] },
			  from		=> 'mfr',
			  where		=>
				{ '+mfr'	=>
					{ tag	=> $tag,
					  subfield => $subfield,
					  value => { '<' => lc($value) }
					},
                  '-or' => [
		    		{ '-exists'	=>
	    				{ select=> { acp => [ 'id' ] },
    					  from	=> { acn => { acp => { field => 'call_number', fkey => 'id' } } },
					      where	=>
				    		{ '+acn' => { record => { '=' => { '+mfr' => 'record' } } },
			    			  '+acp' =>
								{ deleted => 'f',
								  ((@ou_ids)          ? ( circ_lib => \@ou_ids)        : ()),
								  ((@$statuses)       ? ( status   => $statuses)       : ()),
								  ((@$copy_locations) ? ( location => $copy_locations) : ())
								}
		    				},
	    				  limit => 1
    					}
                    },
                    { '-exists'	=>
    					{ select=> { auri => [ 'id' ] },
	    				  from	=> { acn => { auricnm => { field => 'call_number', fkey => 'id', join => { auri => { field => 'id', fkey => 'uri' } } } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } }, (@ou_ids) ? ( owning_lib => \@ou_ids) : () },
				    		  '+auri' => { active => 't' }
					    	},
    					  limit => 1
	    				}
                    }
                  ]
				}, 
			  order_by	=> { mfr => { value => 'desc' } },
			  limit		=> $limit,
			  offset	=> $offset
			}
		)->gather(1);
		push @list, map { $_->{record} } reverse(@$before);
	}

	if ($page >= 0) {
		my $after = $_storage->request(
			"open-ils.cstore.json_query.atomic",
			{ select	=> { mfr => [qw/record value/] },
			  from		=> 'mfr',
			  where		=>
				{ '+mfr'	=>
					{ tag	=> $tag,
					  subfield => $subfield,
					  value => { '>=' => lc($value) }
					},
				  '-or' => [
                    { '-exists'	=>
    					{ select=> { acp => [ 'id' ] },
	    				  from	=> { acn => { acp => { field => 'call_number', fkey => 'id' } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } } },
			    			  '+acp' =>
								{ deleted => 'f',
								  ((@ou_ids)          ? ( circ_lib => \@ou_ids)        : ()),
								  ((@$statuses)       ? ( status   => $statuses)       : ()),
								  ((@$copy_locations) ? ( location => $copy_locations) : ())
								}
					    	},
    					  limit => 1
	    				}
                    },
                    { '-exists'	=>
    					{ select=> { auri => [ 'id' ] },
	    				  from	=> { acn => { auricnm => { field => 'call_number', fkey => 'id', join => { auri => { field => 'id', fkey => 'uri' } } } } },
		    			  where	=>
			    			{ '+acn' => { record => { '=' => { '+mfr' => 'record' } }, (@ou_ids) ? ( owning_lib => \@ou_ids) : () },
				    		  '+auri' => { active => 't' }
					    	},
    					  limit => 1
	    				},
                    }
                  ]
				}, 
			  order_by	=> { mfr => { value => 'asc' } },
			  limit		=> $limit,
			  offset	=> $offset
			}
		)->gather(1);
		push @list, map { $_->{record} } @$after;
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'tag_sf_startwith',
	api_name  => 'open-ils.supercat.tag.startwith',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a list of the requested org-scoped record IDs held
		  DESC
		  params   =>
		  	[
				{ name => 'tag',
				  desc => 'The target MARC tag',
				  type => 'string' },
				{ name => 'subfield',
				  desc => 'The target MARC subfield',
				  type => 'string' },
				{ name => 'value',
				  desc => 'The target string',
				  type => 'string' },
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to browse',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
				{ name => 'statuses',
				  desc => 'Array of statuses to filter copies by, optional and can be undef.',
				  type => 'array' },
				{ name => 'locations',
				  desc => 'Array of copy locations to filter copies by, optional and can be undef.',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Record IDs that have copies at the relevant org units',
			  type => 'array' }
		}
);

sub axis_authority_startwith {
	my $self = shift;
	my $client = shift;
    my $axis = shift;

    $axis =~ s/^authority\.//;
    $axis =~ s/(\.refs)$//;
    my $refs = $1;

    return undef unless ( grep { /$axis/ } @{ grab_authority_browse_axes() } );

    my @tags;
    for my $f (@{$authority_browse_axis_cache{$axis}->fields}) {
        push @tags, $f->tag;
        if ($refs) {
            push @tags, $_->tag for @{$f->sub_entries};
        }
    }

    return authority_tag_sf_startwith($self, $client, \@tags, 'a', @_); # XXX TODO figure out something more correct for the subfield param
}
__PACKAGE__->register_method(
	method    => 'axis_authority_startwith',
	api_name  => 'open-ils.supercat.authority.startwith.by_axis',
	api_level => 1,
	argc      => 2,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'axis', desc => 'The target axis', type => 'string' },
		  	  { name => 'value', desc => 'The target value', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);

=pod

sub general_authority_startwith {
	my $self = shift;
	my $client = shift;
    return authority_tag_sf_startwith($self, $client, $self->{tag}, $self->{subfield}, @_);
}
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.title.startwith',
	tag       => ['130'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.author.startwith',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.subject.startwith',
	tag       => [qw/148 150 151 155/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.topic.startwith',
	tag       => ['150'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.title.refs.startwith',
	tag       => ['130'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target title', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.author.refs.startwith',
	tag       => [qw/100 110 111/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target author', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.subject.refs.startwith',
	tag       => [qw/148 150 151 155/], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'general_authority_startwith',
	api_name  => 'open-ils.supercat.authority.topic.refs.startwith',
	tag       => ['150'], subfield => 'a',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => "Returns a list of the requested authority record IDs held, including see (4xx) and see also (5xx) references",
		  params   =>
		  	[ { name => 'value', desc => 'The target topical subject', type => 'string' },
			  { name => 'page_size', desc => 'Count of records to retrieve, default is 10', type => 'number' },
			  { name => 'page', desc => 'The page of records retrieved, calculated based on page_size.  Can be positive, negative or 0.', type => 'number' }, ],
		  'return' => { desc => 'Authority Record IDs that are near the target string', type => 'array' }
		}
);

=cut

sub authority_tag_sf_startwith {
    my $self = shift;
    my $client = shift;

    my $tag = shift;
    my $subfield = shift;

    my $value = shift;
    my $limit = shift || 10;
    my $page = shift || 0;

    # Match authority.full_rec normalization
    $value = naco_normalize($value, $subfield);

    my $ref_limit = $limit;
    my $offset = $limit * abs($page);
    my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

    my @ref_tags = ();
    # .refs variant includes 4xx and 5xx variants for see / see also
    foreach my $tagname (@$tag) {
        push(@ref_tags, $tagname);
        if ($self->api_name =~ /\.refs\./) {
            push(@ref_tags, '4' . substr($tagname, 1, 2));
            push(@ref_tags, '5' . substr($tagname, 1, 2));
        }
    }

    my @list = ();

    if ($page < 0) {
        # Don't skip the first actual page of results in descending order
        $offset = $offset - $limit;

        my $before = $_storage->request(
            "open-ils.cstore.json_query.atomic",
            { select    => { afr => [qw/record value/] },
              from      => 'afr',
              where     => { tag => \@ref_tags, subfield => $subfield, value => { '<' => $value } },
              order_by  => { afr => { value => 'desc' } },
              limit     => $ref_limit,
              offset    => $offset,
            }
        )->gather(1);
        push @list, map { $_->{record} } reverse(@$before);
    }

    if ($page >= 0) {
        my $after = $_storage->request(
            "open-ils.cstore.json_query.atomic",
            { select    => { afr => [qw/record value/] },
              from      => 'afr',
              where     => { tag => \@ref_tags, subfield => $subfield, value => { '>=' => $value } },
              order_by  => { afr => { value => 'asc' } },
              limit     => $ref_limit,
              offset    => $offset,
            }
        )->gather(1);
        push @list, map { $_->{record} } @$after;
    }

    # If we're not pulling in see/see also references, just return the raw list
    if ($self->api_name !~ /\.refs\./) {
        return \@list;
    }

    # Remove dupe record IDs that turn up due to 4xx and 5xx matches
    my @retlist = ();
    my %seen;
    foreach my $record (@list) {
        next if exists $seen{$record};
        push @retlist, int($record);
        $seen{$record} = 1;
    }

    return \@retlist;
}
__PACKAGE__->register_method(
	method    => 'authority_tag_sf_startwith',
	api_name  => 'open-ils.supercat.authority.tag.startwith',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a list of the requested authority record IDs held
		  DESC
		  params   =>
		  	[
				{ name => 'tag',
				  desc => 'The target Authority MARC tag',
				  type => 'string' },
				{ name => 'subfield',
				  desc => 'The target Authority MARC subfield',
				  type => 'string' },
				{ name => 'value',
				  desc => 'The target string',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 10',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'Authority Record IDs that are near the target string',
			  type => 'array' }
		}
);


sub holding_data_formats {
    return [{
        marcxml => {
            namespace_uri	  => 'http://www.loc.gov/MARC21/slim',
			docs		  => 'http://www.loc.gov/marcxml/',
			schema_location => 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd',
		}
	}];
}
__PACKAGE__->register_method( method => 'holding_data_formats', api_name => 'open-ils.supercat.acn.formats', api_level => 1 );
__PACKAGE__->register_method( method => 'holding_data_formats', api_name => 'open-ils.supercat.acp.formats', api_level => 1 );
__PACKAGE__->register_method( method => 'holding_data_formats', api_name => 'open-ils.supercat.auri.formats', api_level => 1 );


__PACKAGE__->register_method(
	method    => 'retrieve_uri',
	api_name  => 'open-ils.supercat.auri.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a fleshed call number object
		  DESC
		  params   =>
		  	[
				{ name => 'uri_id',
				  desc => 'An OpenILS asset::uri id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'fleshed uri',
			  type => 'object' }
		}
);
sub retrieve_uri {
	my $self = shift;
	my $client = shift;
	my $cpid = shift;
	my $args = shift || {};

    return OpenILS::Application::SuperCat::unAPI
        ->new(OpenSRF::AppSession
            ->create( 'open-ils.cstore' )
            ->request(
    	    	"open-ils.cstore.direct.asset.uri.retrieve",
	    	    $cpid,
    		    { flesh		=> 10,
        		  flesh_fields	=> {
	        	  			auri    => [qw/call_number_maps/],
	        	  			auricnm	=> [qw/call_number/],
	        	  			acn	    => [qw/owning_lib record prefix suffix/],
    				}
	    	    })
            ->gather(1))
        ->as_xml($args);
}

__PACKAGE__->register_method(
	method    => 'retrieve_copy',
	api_name  => 'open-ils.supercat.acp.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a fleshed call number object
		  DESC
		  params   =>
		  	[
				{ name => 'cn_id',
				  desc => 'An OpenILS asset::copy id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'fleshed copy',
			  type => 'object' }
		}
);
sub retrieve_copy {
	my $self = shift;
	my $client = shift;
	my $cpid = shift;
	my $args = shift || {};

    return OpenILS::Application::SuperCat::unAPI
        ->new(OpenSRF::AppSession
            ->create( 'open-ils.cstore' )
            ->request(
    	    	"open-ils.cstore.direct.asset.copy.retrieve",
	    	    $cpid,
    		    { flesh		=> 2,
        		  flesh_fields	=> {
	        	  			acn	=> [qw/owning_lib record prefix suffix/],
		        			acp	=> [qw/call_number location status circ_lib stat_cat_entries notes parts/],
    				}
	    	    })
            ->gather(1))
        ->as_xml($args);
}

__PACKAGE__->register_method(
	method    => 'retrieve_callnumber',
	api_name  => 'open-ils.supercat.acn.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	stream    => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a fleshed call number object
		  DESC
		  params   =>
		  	[
				{ name => 'cn_id',
				  desc => 'An OpenILS asset::call_number id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'call number with copies',
			  type => 'object' }
		}
);
sub retrieve_callnumber {
	my $self = shift;
	my $client = shift;
	my $cnid = shift;
	my $args = shift || {};

    return OpenILS::Application::SuperCat::unAPI
        ->new(OpenSRF::AppSession
            ->create( 'open-ils.cstore' )
            ->request(
    	    	"open-ils.cstore.direct.asset.call_number.retrieve",
	    	    $cnid,
    		    { flesh		=> 5,
        		  flesh_fields	=> {
	        	  			acn	=> [qw/owning_lib record copies uri_maps prefix suffix/],
	        	  			auricnm	=> [qw/uri/],
		        			acp	=> [qw/location status circ_lib stat_cat_entries notes parts/],
    				}
	    	    })
            ->gather(1))
        ->as_xml($args);

}

__PACKAGE__->register_method(
	method    => 'basic_record_holdings',
	api_name  => 'open-ils.supercat.record.basic_holdings.retrieve',
	api_level => 1,
	argc      => 1,
	stream    => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns a basic hash representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'bibId',
				  desc => 'An OpenILS biblio::record_entry id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'Hash of bib record holdings hierarchy (call numbers and copies)',
			  type => 'string' }
		}
);
sub basic_record_holdings {
	my $self = shift;
	my $client = shift;
	my $bib = shift;
	my $ou = shift;

	#  holdings hold an array of call numbers, which hold an array of copies
	#  holdings => [ label: { library, [ copies: { barcode, location, status, circ_lib } ] } ]
	my %holdings;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $tree = $_storage->request(
		"open-ils.cstore.direct.biblio.record_entry.retrieve",
		$bib,
		{ flesh		=> 5,
		  flesh_fields	=> {
					bre	=> [qw/call_numbers/],
		  			acn	=> [qw/copies owning_lib prefix suffix/],
					acp	=> [qw/location status circ_lib parts/],
				}
		}
	)->gather(1);

	my $o_search = { shortname => uc($ou) };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

	my $orgs = $_storage->request(
		"open-ils.cstore.direct.actor.org_unit.search",
		$o_search,
		{ flesh		=> 100,
		  flesh_fields	=> { aou	=> [qw/children/] }
		}
	)->gather(1);

	my @ou_ids = tree_walker($orgs, 'children', sub {shift->id}) if $orgs;

	$logger->debug("Searching for holdings at orgs [".join(',',@ou_ids)."], based on $ou");

	for my $cn (@{$tree->call_numbers}) {
        next unless ( $cn->deleted eq 'f' || $cn->deleted == 0 );

		my $found = 0;
		for my $c (@{$cn->copies}) {
			next unless grep {$c->circ_lib->id == $_} @ou_ids;
			next unless _cp_is_visible($cn, $c);
			$found = 1;
			last;
		}
		next unless $found;

		$holdings{$cn->label}{'owning_lib'} = $cn->owning_lib->shortname;

		for my $cp (@{$cn->copies}) {

			next unless grep { $cp->circ_lib->id == $_ } @ou_ids;
			next unless _cp_is_visible($cn, $cp);

			push @{$holdings{$cn->label}{'copies'}}, {
                barcode => $cp->barcode,
                status => $cp->status->name,
                location => $cp->location->name,
                circlib => $cp->circ_lib->shortname
            };

		}
	}

	return \%holdings;
}

sub _cp_is_visible {
    my $cn = shift;
    my $cp = shift;

    my $visible = 0;
    if ( ($cp->deleted eq 'f' || $cp->deleted == 0) &&
         $cp->location->opac_visible eq 't' && 
         $cp->status->opac_visible eq 't' &&
         $cp->opac_visible eq 't' &&
         $cp->circ_lib->opac_visible eq 't' &&
         $cn->owning_lib->opac_visible eq 't'
    ) {
        $visible = 1;
    }

    return $visible;
}

#__PACKAGE__->register_method(
#	method    => 'new_record_holdings',
#	api_name  => 'open-ils.supercat.record.holdings_xml.retrieve',
#	api_level => 1,
#	argc      => 1,
#	stream    => 1,
#	signature =>
#		{ desc     => <<"		  DESC",
#Returns the XML representation of the requested bibliographic record's holdings
#		  DESC
#		  params   =>
#		  	[
#				{ name => 'bibId',
#				  desc => 'An OpenILS biblio::record_entry id',
#				  type => 'number' },
#			],
#		  'return' =>
#		  	{ desc => 'Stream of bib record holdings hierarchy in XML',
#			  type => 'string' }
#		}
#);
#

sub new_record_holdings {
	my $self = shift;
	my $client = shift;
	my $bib = shift;
	my $ou = shift;
	my $depth = shift;
	my $flesh = shift;
	my $paging = shift;

    $paging = [-1,0] if (!$paging or !ref($paging) or @$paging == 0);
    my $limit = $$paging[0];
    my $offset = $$paging[1] || 0;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
	my $_search = OpenSRF::AppSession->create( 'open-ils.search' );

	my $o_search = { shortname => uc($ou) };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

    my $one_org = $_storage->request(
        "open-ils.cstore.direct.actor.org_unit.search",
        $o_search
    )->gather(1);

    my $count_req = $_search->request('open-ils.search.biblio.record.copy_count' => $one_org->id => $bib);
    my $staff_count_req = $_search->request('open-ils.search.biblio.record.copy_count.staff' => $one_org->id => $bib);

    my $orgs = $_storage->request(
        'open-ils.cstore.json_query.atomic',
        { from => [ 'actor.org_unit_descendants', defined($depth) ? ( $one_org->id, $depth ) :  ( $one_org->id ) ] }
    )->gather(1);


	my @ou_ids = map { $_->{id} } @$orgs;

	$logger->info("Searching for holdings at orgs [".join(',',@ou_ids)."], based on $ou");

    my %subselect = ( '-or' => [
        { owning_lib => \@ou_ids },
        { '-exists'  =>
            { from  => 'acp',
              where => {
                call_number => { '=' => {'+acn'=>'id'} },
                deleted => 'f',
                circ_lib => \@ou_ids
              }
            }
        }
    ]);

    # we are dealing with -full or -uris, so we need to flesh things out
    if ($flesh) {

        # either way we're going to need uris
        # get all the uris up the tree (see also ba47ecc6196)

        my $uri_orgs = $_storage->request(
            'open-ils.cstore.json_query.atomic',
            { from => [ 'actor.org_unit_ancestors', $one_org->id ] }
        )->gather(1);

        my @uri_ou_ids = map { $_->{id} } @$uri_orgs;

        # we have a -uris, just get the uris
        if ($flesh == 2) {
            %subselect = (
                owning_lib => \@uri_ou_ids,
                '-exists'  => {
                    from  => { auricnm => 'auri' },
                    where => {
                        call_number => { '=' => {'+acn'=>'id'} },
                        '+auri' => { active => 't' }
                    }
                }
            );
        # we have a -full, get all the things
        } elsif ($flesh == 1) {
            %subselect = ( '-or' => [
                { owning_lib => \@ou_ids },
                { '-exists'  =>
                    { from  => 'acp',
                      where => {
                        call_number => { '=' => {'+acn'=>'id'} },
                        deleted => 'f',
                        circ_lib => \@ou_ids
                      }
                    }
                },
                { '-and' => [
                    { owning_lib => \@uri_ou_ids },
                    { '-exists'  => {
                        from  => { auricnm => 'auri' },
                        where => {
                            call_number => { '=' => {'+acn'=>'id'} },
                            '+auri' => { active => 't' }
                        }
                    }}
                ]}
            ]);
        }
    }

	my $cns = $_storage->request(
		"open-ils.cstore.direct.asset.call_number.search.atomic",
		{ record  => $bib,
          deleted => 'f',
          %subselect
        },
		{ flesh		=> 5,
		  flesh_fields	=> {
		  			acn	=> [qw/copies owning_lib uri_maps prefix suffix/],
		  			auricnm	=> [qw/uri/],
					acp	=> [qw/circ_lib location status stat_cat_entries notes parts/],
					asce	=> [qw/stat_cat/],
				},
          ( $limit > -1 ? ( limit  => $limit  ) : () ),
          ( $offset     ? ( offset => $offset ) : () ),
          order_by  => { acn => { label_sortkey => {} } }
		}
	)->gather(1);

	my ($year,$month,$day) = reverse( (localtime)[3,4,5] );
	$year += 1900;
	$month += 1;

	$client->respond("<holdings xmlns='http://open-ils.org/spec/holdings/v1'><counts>\n");

	my $copy_counts = $count_req->gather(1);
	my $staff_copy_counts = $staff_count_req->gather(1);

	for my $c (@$copy_counts) {
		$$c{transcendant} ||= 0;
		my $out = "<count type='public'";
		$out .= " $_='$$c{$_}'" for (qw/count available unshadow transcendant org_unit depth/);
		$client->respond("$out/>\n")
	}

	for my $c (@$staff_copy_counts) {
		$$c{transcendant} ||= 0;
		my $out = "<count type='staff'";
		$out .= " $_='$$c{$_}'" for (qw/count available unshadow transcendant org_unit depth/);
		$client->respond("$out/>\n")
	}

    $client->respond("</counts><volumes>\n");
    
	for my $cn (@$cns) {
		next unless (@{$cn->copies} > 0 or (ref($cn->uri_maps) and @{$cn->uri_maps}));

		# We don't want O:A:S:unAPI::acn to return the record, we've got that already
		# In the context of BibTemplate, copies aren't necessary because we pull those
		# in a separate call
        $client->respond(
            OpenILS::Application::SuperCat::unAPI::acn
                ->new( $cn )
                ->as_xml( {no_record => 1, no_copies => ($flesh ? 0 : 1)} )
        );
	}

	$client->respond("</volumes><subscriptions>\n");

	$logger->info("Searching for serial holdings at orgs [".join(',',@ou_ids)."], based on $ou");

    %subselect = ( '-or' => [
        { owning_lib => \@ou_ids },
        { '-exists'  =>
            { from  => 'sdist',
              where => { holding_lib => \@ou_ids }
            }
        }
    ]);

	my $ssubs = $_storage->request(
		"open-ils.cstore.direct.serial.subscription.search.atomic",
		{ record_entry  => $bib,
          %subselect
        },
		{ flesh		=> 7,
		  flesh_fields	=> {
		  			ssub	=> [qw/distributions issuances scaps owning_lib/],
		  			sdist	=> [qw/basic_summary supplement_summary index_summary streams holding_lib/],
					sstr	=> [qw/items/],
					sitem	=> [qw/notes unit/],
					sunit	=> [qw/notes location status circ_lib stat_cat_entries call_number/],
					acn	=> [qw/owning_lib prefix suffix/],
				},
          ( $limit > -1 ? ( limit  => $limit  ) : () ),
          ( $offset     ? ( offset => $offset ) : () ),
          order_by  => {
			ssub => {
				start_date => {},
				owning_lib => {},
				id => {}
			},
			sdist => {
				label => {},
				owning_lib => {},
			},
			sunit => {
				date_expected => {},
			}
		  }
		}
	)->gather(1);


	for my $ssub (@$ssubs) {
		next unless (@{$ssub->distributions} or @{$ssub->issuances} or @{$ssub->scaps});

		# We don't want O:A:S:unAPI::ssub to return the record, we've got that already
		# In the context of BibTemplate, copies aren't necessary because we pull those
		# in a separate call
        $client->respond(
            OpenILS::Application::SuperCat::unAPI::ssub
                ->new( $ssub )
                ->as_xml( {no_record => 1, no_items => ($flesh ? 0 : 1)} )
        );
	}


	return "</subscriptions></holdings>\n";
}
__PACKAGE__->register_method(
	method    => 'new_record_holdings',
	api_name  => 'open-ils.supercat.record.holdings_xml.retrieve',
	api_level => 1,
	argc      => 1,
	stream    => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'bibId',
				  desc => 'An OpenILS biblio::record_entry ID',
				  type => 'number' },
				{ name => 'orgUnit',
				  desc => 'An OpenILS actor::org_unit short name that limits the scope of returned holdings',
				  type => 'text' },
				{ name => 'depth',
				  desc => 'An OpenILS actor::org_unit_type depththat limits the scope of returned holdings',
				  type => 'number' },
				{ name => 'hideCopies',
				  desc => 'Flag that prevents the inclusion of copies in the returned holdings',
				  type => 'boolean' },
				{ name => 'paging',
				  desc => 'Arry of limit and offset for holdings paging',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'Stream of bib record holdings hierarchy in XML',
			  type => 'string' }
		}
);

sub isbn_holdings {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $recs = $_storage->request(
			'open-ils.cstore.direct.metabib.full_rec.search.atomic',
			{ tag => { like => '02%'}, value => {like => "$isbn\%"}}
	)->gather(1);

	return undef unless (@$recs);

	return ($self->method_lookup( 'open-ils.supercat.record.holdings_xml.retrieve')->run( $recs->[0]->record ))[0];
}
__PACKAGE__->register_method(
	method    => 'isbn_holdings',
	api_name  => 'open-ils.supercat.isbn.holdings_xml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'isbn',
				  desc => 'An isbn',
				  type => 'string' },
			],
		  'return' =>
		  	{ desc => 'The bib record holdings hierarchy in XML',
			  type => 'string' }
		}
);

sub escape {
	my $self = shift;
	my $text = shift;
    return '' unless $text;
	$text =~ s/&/&amp;/gsom;
	$text =~ s/</&lt;/gsom;
	$text =~ s/>/&gt;/gsom;
	$text =~ s/"/&quot;/gsom;
	$text =~ s/'/&apos;/gsom;
	return $text;
}

sub recent_changes {
	my $self = shift;
	my $client = shift;
	my $when = shift || '1-01-01';
	my $limit = shift;

	my $type = 'biblio';
	my $hint = 'bre';

	if ($self->api_name =~ /authority/o) {
		$type = 'authority';
		$hint = 'are';
	}

	my $axis = 'create_date';
	$axis = 'edit_date' if ($self->api_name =~ /edit/o);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	return $_storage->request(
		"open-ils.cstore.direct.$type.record_entry.id_list.atomic",
		{ $axis => { ">" => $when }, id => { '>' => 0 }, deleted => 'f', active => 't' },
		{ order_by => { $hint => "$axis desc" }, limit => $limit }
	)->gather(1);
}

for my $t ( qw/biblio authority/ ) {
	for my $a ( qw/import edit/ ) {

		__PACKAGE__->register_method(
			method    => 'recent_changes',
			api_name  => "open-ils.supercat.$t.record.$a.recent",
			api_level => 1,
			argc      => 0,
			signature =>
				{ desc     => "Returns a list of recently ${a}ed $t records",
		  		  params   =>
		  			[
						{ name => 'when',
				  		  desc => "Date to start looking for ${a}ed records",
				  		  default => '1-01-01',
				  		  type => 'string' },

						{ name => 'limit',
				  		  desc => "Maximum count to retrieve",
				  		  type => 'number' },
					],
		  		  'return' =>
		  			{ desc => "An id list of $t records",
			  		  type => 'array' }
				},
		);
	}
}


sub retrieve_authority_marcxml {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $record = $_storage->request( 'open-ils.cstore.direct.authority.record_entry.retrieve' => $rid )->gather(1);
	return $U->entityize( $record->marc ) if ($record);
	return undef;
}

__PACKAGE__->register_method(
	method    => 'retrieve_authority_marcxml',
	api_name  => 'open-ils.supercat.authority.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MARCXML representation of the requested authority record
		  DESC
		  params   =>
		  	[
				{ name => 'authorityId',
				  desc => 'An OpenILS authority::record_entry id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The authority record in MARCXML',
			  type => 'string' }
		}
);

sub retrieve_record_marcxml {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $record = $_storage->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rid )->gather(1);
	return $U->entityize( $record->marc ) if ($record);
	return undef;
}

__PACKAGE__->register_method(
	method    => 'retrieve_record_marcxml',
	api_name  => 'open-ils.supercat.record.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MARCXML representation of the requested bibliographic record
		  DESC
		  params   =>
		  	[
				{ name => 'bibId',
				  desc => 'An OpenILS biblio::record_entry id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The bib record in MARCXML',
			  type => 'string' }
		}
);

sub retrieve_isbn_marcxml {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $recs = $_storage->request(
			'open-ils.cstore.direct.metabib.full_rec.search.atomic',
			{ tag => { like => '02%'}, value => {like => "$isbn\%"}}
	)->gather(1);

	return undef unless (@$recs);

	my $record = $_storage->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $recs->[0]->record )->gather(1);
	return $U->entityize( $record->marc ) if ($record);
	return undef;
}

__PACKAGE__->register_method(
	method    => 'retrieve_isbn_marcxml',
	api_name  => 'open-ils.supercat.isbn.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MARCXML representation of the requested ISBN
		  DESC
		  params   =>
		  	[
				{ name => 'ISBN',
				  desc => 'An ... um ... ISBN',
				  type => 'string' },
			],
		  'return' =>
		  	{ desc => 'The bib record in MARCXML',
			  type => 'string' }
		}
);

sub retrieve_record_transform {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	(my $transform = $self->api_name) =~ s/^.+record\.([^\.]+)\.retrieve$/$1/o;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
	#$_storage->connect;

	my $record = $_storage->request(
		'open-ils.cstore.direct.biblio.record_entry.retrieve',
		$rid
	)->gather(1);

	return undef unless ($record);

	return $U->entityize($record_xslt{$transform}{xslt}->transform( $_parser->parse_string( $record->marc ) )->toString);
}

sub retrieve_isbn_transform {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $recs = $_storage->request(
			'open-ils.cstore.direct.metabib.full_rec.search.atomic',
			{ tag => { like => '02%'}, value => {like => "$isbn\%"}}
	)->gather(1);

	return undef unless (@$recs);

	(my $transform = $self->api_name) =~ s/^.+isbn\.([^\.]+)\.retrieve$/$1/o;

	my $record = $_storage->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $recs->[0]->record )->gather(1);

	return undef unless ($record);

	return $U->entityize($record_xslt{$transform}{xslt}->transform( $_parser->parse_string( $record->marc ) )->toString);
}

sub retrieve_record_objects {
	my $self = shift;
	my $client = shift;
	my $ids = shift;

	my $type = 'biblio';

	if ($self->api_name =~ /authority/) {
		$type = 'authority';
	}

	$ids = [$ids] unless (ref $ids);
	$ids = [grep {$_} @$ids];

	return [] unless (@$ids);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
	return $_storage->request("open-ils.cstore.direct.$type.record_entry.search.atomic" => { id => [grep {$_} @$ids] })->gather(1);
}
__PACKAGE__->register_method(
	method    => 'retrieve_record_objects',
	api_name  => 'open-ils.supercat.record.object.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the Fieldmapper object representation of the requested bibliographic records
		  DESC
		  params   =>
		  	[
				{ name => 'bibIds',
				  desc => 'OpenILS biblio::record_entry ids',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'The bib records',
			  type => 'array' }
		}
);

__PACKAGE__->register_method(
	method    => 'retrieve_record_objects',
	api_name  => 'open-ils.supercat.authority.object.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the Fieldmapper object representation of the requested authority records
		  DESC
		  params   =>
		  	[
				{ name => 'authIds',
				  desc => 'OpenILS authority::record_entry ids',
				  type => 'array' },
			],
		  'return' =>
		  	{ desc => 'The authority records',
			  type => 'array' }
		}
);

sub retrieve_isbn_object {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	return undef unless ($isbn);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
	my $recs = $_storage->request(
			'open-ils.cstore.direct.metabib.full_rec.search.atomic',
			{ tag => { like => '02%'}, value => {like => "$isbn\%"}}
	)->gather(1);

	return undef unless (@$recs);

	return $_storage->request(
		'open-ils.cstore.direct.biblio.record_entry.search.atomic',
		{ id => $recs->[0]->record }
	)->gather(1);
}
__PACKAGE__->register_method(
	method    => 'retrieve_isbn_object',
	api_name  => 'open-ils.supercat.isbn.object.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the Fieldmapper object representation of the requested bibliographic record
		  DESC
		  params   =>
		  	[
				{ name => 'isbn',
				  desc => 'an ISBN',
				  type => 'string' },
			],
		  'return' =>
		  	{ desc => 'The bib record',
			  type => 'object' }
		}
);



sub retrieve_metarecord_mods {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	my $_storage = OpenSRF::AppSession->connect( 'open-ils.cstore' );

	# Get the metarecord in question
	my $mr =
	$_storage->request(
		'open-ils.cstore.direct.metabib.metarecord.retrieve' => $rid
	)->gather(1);

	# Now get the map of all bib records for the metarecord
	my $recs =
	$_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{metarecord => $rid}
	)->gather(1);

	$logger->debug("Adding ".scalar(@$recs)." bib record to the MODS of the metarecord");

	# and retrieve the lead (master) record as MODS
	my ($master) =
		$self	->method_lookup('open-ils.supercat.record.mods.retrieve')
			->run($mr->master_record);
	my $master_mods = $_parser->parse_string($master)->documentElement;
	$master_mods->setNamespace( "http://www.loc.gov/mods/", "mods" );
	$master_mods->setNamespace( "http://www.loc.gov/mods/", undef, 1 );

	# ... and a MODS clone to populate, with guts removed.
	my $mods = $_parser->parse_string($master)->documentElement;
	$mods->setNamespace( "http://www.loc.gov/mods/", "mods" ); # modsCollection element
	$mods->setNamespace('http://www.loc.gov/mods/', undef, 1);
	($mods) = $mods->findnodes('//mods:mods');
	#$mods->setNamespace( "http://www.loc.gov/mods/", "mods" ); # mods element
	$mods->removeChildNodes;
	$mods->setNamespace('http://www.loc.gov/mods/', undef, 1);

	# Add the metarecord ID as a (locally defined) info URI
	my $recordInfo = $mods
		->ownerDocument
		->createElement("recordInfo");

	my $recordIdentifier = $mods
		->ownerDocument
		->createElement("recordIdentifier");

	my ($year,$month,$day) = reverse( (localtime)[3,4,5] );
	$year += 1900;
	$month += 1;

	my $id = $mr->id;
	$recordIdentifier->appendTextNode(
		sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:metabib-metarecord/$id", $month, $day)
	);

	$recordInfo->appendChild($recordIdentifier);
	$mods->appendChild($recordInfo);

	# Grab the title, author and ISBN for the master record and populate the metarecord
	my ($title) = $master_mods->findnodes( './mods:titleInfo[not(@type)]' );
	
	if ($title) {
		$title->setNamespace( "http://www.loc.gov/mods/", "mods" );
		$title->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
		$title = $mods->ownerDocument->importNode($title);
		$mods->appendChild($title);
	}

	my ($author) = $master_mods->findnodes( './mods:name[mods:role/mods:text[text()="creator"]]' );
	if ($author) {
		$author->setNamespace( "http://www.loc.gov/mods/", "mods" );
		$author->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
		$author = $mods->ownerDocument->importNode($author);
		$mods->appendChild($author);
	}

	my ($isbn) = $master_mods->findnodes( './mods:identifier[@type="isbn"]' );
	if ($isbn) {
		$isbn->setNamespace( "http://www.loc.gov/mods/", "mods" );
		$isbn->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
		$isbn = $mods->ownerDocument->importNode($isbn);
		$mods->appendChild($isbn);
	}

	# ... and loop over the constituent records
	for my $map ( @$recs ) {

		# get the MODS
		my ($rec) =
			$self	->method_lookup('open-ils.supercat.record.mods.retrieve')
				->run($map->source);

		my $part_mods = $_parser->parse_string($rec);
		$part_mods->documentElement->setNamespace( "http://www.loc.gov/mods/", "mods" );
		$part_mods->documentElement->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
		($part_mods) = $part_mods->findnodes('//mods:mods');

		for my $node ( ($part_mods->findnodes( './mods:subject' )) ) {
			$node->setNamespace( "http://www.loc.gov/mods/", "mods" );
			$node->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
			$node = $mods->ownerDocument->importNode($node);
			$mods->appendChild( $node );
		}

		my $relatedItem = $mods
			->ownerDocument
			->createElement("relatedItem");

		$relatedItem->setAttribute( type => 'constituent' );

		my $identifier = $mods
			->ownerDocument
			->createElement("identifier");

		$identifier->setAttribute( type => 'uri' );

		my $subRecordInfo = $mods
			->ownerDocument
			->createElement("recordInfo");

		my $subRecordIdentifier = $mods
			->ownerDocument
			->createElement("recordIdentifier");

		my $subid = $map->source;
		$subRecordIdentifier->appendTextNode(
			sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:biblio-record_entry/$subid",
				$month,
				$day
			)
		);
		$subRecordInfo->appendChild($subRecordIdentifier);

		$relatedItem->appendChild( $subRecordInfo );

		my ($tor) = $part_mods->findnodes( './mods:typeOfResource' );
		$tor->setNamespace( "http://www.loc.gov/mods/", "mods" );
		$tor->setNamespace( "http://www.loc.gov/mods/", undef, 1 ) if ($tor);
		$tor = $mods->ownerDocument->importNode($tor) if ($tor);
		$relatedItem->appendChild($tor) if ($tor);

		if ( my ($part_isbn) = $part_mods->findnodes( './mods:identifier[@type="isbn"]' ) ) {
			$part_isbn->setNamespace( "http://www.loc.gov/mods/", "mods" );
			$part_isbn->setNamespace( "http://www.loc.gov/mods/", undef, 1 );
			$part_isbn = $mods->ownerDocument->importNode($part_isbn);
			$relatedItem->appendChild( $part_isbn );

			if (!$isbn) {
				$isbn = $mods->appendChild( $part_isbn->cloneNode(1) );
			}
		}

		$mods->appendChild( $relatedItem );

	}

	$_storage->disconnect;

	return $U->entityize($mods->toString);

}
__PACKAGE__->register_method(
	method    => 'retrieve_metarecord_mods',
	api_name  => 'open-ils.supercat.metarecord.mods.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MODS representation of the requested metarecord
		  DESC
		  params   =>
		  	[
				{ name => 'metarecordId',
				  desc => 'An OpenILS metabib::metarecord id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The metarecord in MODS',
			  type => 'string' }
		}
);

sub list_metarecord_formats {
	my @list = (
		{ mods =>
			{ namespace_uri	  => 'http://www.loc.gov/mods/',
			  docs		  => 'http://www.loc.gov/mods/',
			  schema_location => 'http://www.loc.gov/standards/mods/mods.xsd',
			}
		}
	);

	for my $type ( keys %metarecord_xslt ) {
		push @list,
			{ $type => 
				{ namespace_uri	  => $metarecord_xslt{$type}{namespace_uri},
				  docs		  => $metarecord_xslt{$type}{docs},
				  schema_location => $metarecord_xslt{$type}{schema_location},
				}
			};
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'list_metarecord_formats',
	api_name  => 'open-ils.supercat.metarecord.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid metarecord formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);


sub list_authority_formats {
	my @list = (
		{ marcxml =>
			{ namespace_uri	  => 'http://www.loc.gov/MARC21/slim',
			  docs		  => 'http://www.loc.gov/marcxml/',
			  schema_location => 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd',
			}
		}
	);

#	for my $type ( keys %record_xslt ) {
#		push @list,
#			{ $type => 
#				{ namespace_uri	  => $record_xslt{$type}{namespace_uri},
#				  docs		  => $record_xslt{$type}{docs},
#				  schema_location => $record_xslt{$type}{schema_location},
#				}
#			};
#	}
#
	return \@list;
}
__PACKAGE__->register_method(
	method    => 'list_authority_formats',
	api_name  => 'open-ils.supercat.authority.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid authority formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);

sub list_record_formats {
	my @list = (
		{ marcxml =>
			{ namespace_uri	  => 'http://www.loc.gov/MARC21/slim',
			  docs		  => 'http://www.loc.gov/marcxml/',
			  schema_location => 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd',
			}
		}
	);

	for my $type ( keys %record_xslt ) {
		push @list,
			{ $type => 
				{ namespace_uri	  => $record_xslt{$type}{namespace_uri},
				  docs		  => $record_xslt{$type}{docs},
				  schema_location => $record_xslt{$type}{schema_location},
				}
			};
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'list_record_formats',
	api_name  => 'open-ils.supercat.record.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid record formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);
__PACKAGE__->register_method(
	method    => 'list_record_formats',
	api_name  => 'open-ils.supercat.isbn.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid record formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);


sub oISBN {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	$isbn =~ s/-//gso;

	throw OpenSRF::EX::InvalidArg ('I need an ISBN please')
		unless (length($isbn) >= 10);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	# Create a storage session, since we'll be making muliple requests.
	$_storage->connect;

	# Find the record that has that ISBN.
	my $bibrec = $_storage->request(
		'open-ils.cstore.direct.metabib.full_rec.search.atomic',
		{ tag => '020', subfield => 'a', value => { like => lc($isbn).'%'} }
	)->gather(1);

	# Go away if we don't have one.
	return {} unless (@$bibrec);

	# Find the metarecord for that bib record.
	my $mr = $_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{source => $bibrec->[0]->record}
	)->gather(1);

	# Find the other records for that metarecord.
	my $records = $_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{metarecord => $mr->[0]->metarecord}
	)->gather(1);

	# Just to be safe.  There's currently no unique constraint on sources...
	my %unique_recs = map { ($_->source, 1) } @$records;
	my @rec_list = sort keys %unique_recs;

	# And now fetch the ISBNs for thos records.
	my $recs = [];
	push @$recs,
		$_storage->request(
			'open-ils.cstore.direct.metabib.full_rec.search',
			{ tag => '020', subfield => 'a', record => $_ }
		)->gather(1) for (@rec_list);

	# We're done with the storage server session.
	$_storage->disconnect;

	# Return the oISBN data structure.  This will be XMLized at a higher layer.
	return
		{ metarecord => $mr->[0]->metarecord,
		  record_list => { map { $_ ? ($_->record, $_->value) : () } @$recs } };

}
__PACKAGE__->register_method(
	method    => 'oISBN',
	api_name  => 'open-ils.supercat.oisbn',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the ISBN list for the metarecord of the requested isbn
		  DESC
		  params   =>
		  	[
				{ name => 'isbn',
				  desc => 'An ISBN.  Duh.',
				  type => 'string' },
			],
		  'return' =>
		  	{ desc => 'record to isbn map',
			  type => 'object' }
		}
);

sub return_bib_search_aliases {
    my %aliases;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $cmsa = $_storage->request(
		'open-ils.cstore.direct.config.metabib_search_alias.search.atomic',
		{ alias => { '!=' => undef } }
	)->gather(1);

    foreach (@$cmsa) {
        if ($_->alias =~ /\./) {
            my ($qualifier, $name) = $_->alias =~ m/^(.+?)\.(.+)$/;
            $aliases{$qualifier}{$name}{'index'} = $_->alias;
            # We will add a 'title' property in a subsequent schema
            $aliases{$qualifier}{$name}{'title'} = $name;
        } else {
            # au/kw/se/su/ti go into the default 'eg' qualifier
            $aliases{'eg'}{$_->alias}{'index'} = $_->alias;
            $aliases{'eg'}{$_->alias}{'title'} = $_->alias;
        }
    }

    return \%aliases;
}

__PACKAGE__->register_method(
	method    => 'return_bib_search_aliases',
	api_name  => 'open-ils.supercat.biblio.search_aliases',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the set of qualified search aliases in the system
		  DESC
		  params   => [ ],
		  'return' =>
		  	{ desc => 'Hash of qualified search aliases',
			  type => 'object' }
		}
);


package OpenILS::Application::SuperCat::unAPI;
use base qw/OpenILS::Application::SuperCat/;

sub as_xml {
    die "dummy superclass, use a real class";
}

sub new {
    my $class = shift;
    my $obj = shift;
    return unless ($obj);

    $class = ref($class) || $class;

    if ($class eq __PACKAGE__) {
        return unless (ref($obj));
        $class .= '::' . $obj->json_hint;
    }

    return bless { obj => $obj } => $class;
}

sub obj {
    my $self = shift;
    return $self->{obj};
}

package OpenILS::Application::SuperCat::unAPI::auri;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '      <uri xmlns="http://open-ils.org/spec/holdings/v1" ';
    $xml .= 'id="tag:open-ils.org:asset-uri/' . $self->obj->id . '" ';
    $xml .= 'use_restriction="' . $self->escape( $self->obj->use_restriction ) . '" ';
    $xml .= 'label="' . $self->escape( $self->obj->label ) . '" ';
    $xml .= 'href="' . $self->escape( $self->obj->href ) . '">';

    if (!$args->{no_volumes}) {
        if (ref($self->obj->call_number_maps) && @{ $self->obj->call_number_maps }) {
            $xml .= "      <volumes>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_->call_number )
                        ->as_xml({ %$args, no_uris=>1, no_copies=>1 })
                } @{ $self->obj->call_number_maps }
            ) . "      </volumes>\n";

        } else {
            $xml .= "      <volumes/>\n";
        }
    }

    $xml .= "      </uri>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::acn;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '    <volume xmlns="http://open-ils.org/spec/holdings/v1" ';

    $xml .= 'id="tag:open-ils.org:asset-call_number/' . $self->obj->id . '" ';
    $xml .= 'lib="' . $self->escape( $self->obj->owning_lib->shortname ) . '" ';
    $xml .= 'opac_visible="' . $self->obj->owning_lib->opac_visible . '" ';
    $xml .= 'deleted="' . $self->obj->deleted . '" ';
    $xml .= 'label="' . $self->escape( $self->obj->label ) . '">';
    $xml .= "\n";

    if (!$args->{no_copies}) {
        if (ref($self->obj->copies) && @{ $self->obj->copies }) {
            $xml .= "      <copies>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_volume=>1 })
                } @{ $self->obj->copies }
            ) . "      </copies>\n";

        } else {
            $xml .= "      <copies/>\n";
        }
    }

    if (!$args->{no_uris}) {
        if (ref($self->obj->uri_maps) && @{ $self->obj->uri_maps }) {
            $xml .= "      <uris>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_->uri )
                        ->as_xml({ %$args, no_volumes=>1 })
                } @{ $self->obj->uri_maps }
            ) . "      </uris>\n";

        } else {
            $xml .= "      <uris/>\n";
        }
    }


    $xml .= '      <prefix ';
    $xml .= 'ident="' . $self->obj->prefix->id . '" ';
    $xml .= 'id="tag:open-ils.org:asset-call_number_prefix/' . $self->obj->prefix->id . '" ';
    $xml .= 'label_sortkey="'.$self->escape( $self->obj->prefix->label_sortkey ) .'">';
    $xml .= $self->escape( $self->obj->prefix->label ) .'</prefix>';
    $xml .= "\n";

    $xml .= '      <suffix ';
    $xml .= 'ident="' . $self->obj->suffix->id . '" ';
    $xml .= 'id="tag:open-ils.org:asset-call_number_suffix/' . $self->obj->suffix->id . '" ';
    $xml .= 'label_sortkey="'.$self->escape( $self->obj->suffix->label_sortkey ) .'">';
    $xml .= $self->escape( $self->obj->suffix->label ) .'</suffix>';
    $xml .= "\n";

    $xml .= '      <owning_lib xmlns="http://open-ils.org/spec/actors/v1" ';
    $xml .= 'id="tag:open-ils.org:actor-org_unit/' . $self->obj->owning_lib->id . '" ';
    $xml .= 'shortname="'.$self->escape( $self->obj->owning_lib->shortname ) .'" ';
    $xml .= 'name="'.$self->escape( $self->obj->owning_lib->name ) .'"/>';
    $xml .= "\n";

    unless ($args->{no_record}) {
        my $rec_tag = "tag:open-ils.org:biblio-record_entry/".$self->obj->record->id.'/'.$self->escape( $self->obj->owning_lib->shortname ) ;

        my $r_doc = $parser->parse_string($self->obj->record->marc);
        $r_doc->documentElement->setAttribute( id => $rec_tag );
        $xml .= $U->entityize($r_doc->documentElement->toString);
    }

    $xml .= "    </volume>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::ssub;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '    <subscription xmlns="http://open-ils.org/spec/holdings/v1" ';

    $xml .= 'id="tag:open-ils.org:serial-subscription/' . $self->obj->id . '" ';
    $xml .= 'start="' . $self->escape( $self->obj->start_date ) . '" ';
    $xml .= 'end="' . $self->escape( $self->obj->end_date ) . '" ';
    $xml .= 'expected_date_offset="' . $self->escape( $self->obj->expected_date_offset ) . '">';
    $xml .= "\n";

    if (!$args->{no_distributions}) {
        if (ref($self->obj->distributions) && @{ $self->obj->distributions }) {
            $xml .= "      <distributions>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_subscription=>1, no_issuance=>1 })
                } @{ $self->obj->distributions }
            ) . "      </distributions>\n";

        } else {
            $xml .= "      <distributions/>\n";
        }
    }

    if (!$args->{no_captions_and_patterns}) {
        if (ref($self->obj->scaps) && @{ $self->obj->scaps }) {
            $xml .= "      <captions_and_patterns>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_subscription=>1 })
                } @{ $self->obj->scaps }
            ) . "      </captions_and_patterns>\n";

        } else {
            $xml .= "      <captions_and_patterns/>\n";
        }
    }

    if (!$args->{no_issuances}) {
        if (ref($self->obj->issuances) && @{ $self->obj->issuances }) {
            $xml .= "      <issuances>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_subscription=>1, no_items=>1 })
                } @{ $self->obj->issuances }
            ) . "      </issuances>\n";

        } else {
            $xml .= "      <issuances/>\n";
        }
    }


    $xml .= '      <owning_lib xmlns="http://open-ils.org/spec/actors/v1" ';
    $xml .= 'id="tag:open-ils.org:actor-org_unit/' . $self->obj->owning_lib->id . '" ';
    $xml .= 'shortname="'.$self->escape( $self->obj->owning_lib->shortname ) .'" ';
    $xml .= 'name="'.$self->escape( $self->obj->owning_lib->name ) .'"/>';
    $xml .= "\n";

    unless ($args->{no_record}) {
        my $rec_tag = "tag:open-ils.org:biblio-record_entry/".$self->obj->record->id.'/'.$self->escape( $self->obj->owning_lib->shortname ) ;

        my $r_doc = $parser->parse_string($self->obj->record_entry->marc);
        $r_doc->documentElement->setAttribute( id => $rec_tag );
        $xml .= $U->entityize($r_doc->documentElement->toString);
    }

    $xml .= "    </subscription>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::ssum_base;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    (my $type = ref($self)) =~ s/^.+([^:]+)$/$1/;

    my $xml = "    <serial_summary xmlns=\"http://open-ils.org/spec/holdings/v1\" type=\"$type\" ";

    $xml .= "id=\"tag:open-ils.org:serial-summary-$type/" . $self->obj->id . '" ';
    $xml .= 'generated_coverage="' . $self->escape( $self->obj->generated_coverage ) . '" ';
    $xml .= 'show_generated="' . $self->escape( $self->obj->show_generated ) . '" ';
    $xml .= 'textual_holdings="' . $self->escape( $self->obj->textual_holdings ) . '">';
    $xml .= "\n";

	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->distribution )->as_xml({ %$args, no_summaries=>1 }) if (!$args->{no_distribution});

    $xml .= "    </serial_summary>\n";

    return $xml;
}


package OpenILS::Application::SuperCat::unAPI::sssum;
use base qw/OpenILS::Application::SuperCat::unAPI::ssum_base/;

package OpenILS::Application::SuperCat::unAPI::sbsum;
use base qw/OpenILS::Application::SuperCat::unAPI::ssum_base/;

package OpenILS::Application::SuperCat::unAPI::sisum;
use base qw/OpenILS::Application::SuperCat::unAPI::ssum_base/;

package OpenILS::Application::SuperCat::unAPI::sdist;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '    <distribution xmlns="http://open-ils.org/spec/holdings/v1" ';

    $xml .= 'id="tag:open-ils.org:serial-distribution/' . $self->obj->id . '" ';
    $xml .= 'label="' . $self->escape( $self->obj->label ) . '" ';
    $xml .= 'unit_label_prefix="' . $self->escape( $self->obj->unit_label_prefix ) . '" ';
    $xml .= 'unit_label_suffix="' . $self->escape( $self->obj->unit_label_suffix ) . '">';
    $xml .= "\n";

    if (!$args->{no_distributions}) {
        if (ref($self->obj->streams) && @{ $self->obj->streams }) {
            $xml .= "      <streams>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_distribution=>1 })
                } @{ $self->obj->streams }
            ) . "      </streams>\n";

        } else {
            $xml .= "      <streams/>\n";
        }
    }

    if (!$args->{no_summaries}) {
        $xml .= "      <summaries>\n";
        $xml .= join ('',
        map {
            defined $_ ?
                OpenILS::Application::SuperCat::unAPI
                ->new( $_ )
                ->as_xml({ %$args, no_distribution=>1 }) : ""
        } ($self->obj->basic_summary, $self->obj->supplement_summary, $self->obj->index_summary)
        );

        $xml .= "      </summaries>\n";
    }


    $xml .= '      <holding_lib xmlns="http://open-ils.org/spec/actors/v1" ';
    $xml .= 'id="tag:open-ils.org:actor-org_unit/' . $self->obj->holding_lib->id . '" ';
    $xml .= 'shortname="'.$self->escape( $self->obj->holding_lib->shortname ) .'" ';
    $xml .= 'name="'.$self->escape( $self->obj->holding_lib->name ) .'"/>';
    $xml .= "\n";

	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->subscription )->as_xml({ %$args, no_distributions=>1 }) if (!$args->{no_subscription});

    if (!$args->{no_record} && $self->obj->record_entry) {
        my $rec_tag = "tag:open-ils.org:serial-record_entry/".$self->obj->record_entry->id ;

        my $r_doc = $parser->parse_string($self->obj->record_entry->marc);
        $r_doc->documentElement->setAttribute( id => $rec_tag );
        $xml .= $U->entityize($r_doc->documentElement->toString);
    }

    $xml .= "    </distribution>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::sstr;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '    <stream xmlns="http://open-ils.org/spec/holdings/v1" ';

    $xml .= 'id="tag:open-ils.org:serial-stream/' . $self->obj->id . '" ';
    $xml .= 'routing_label="' . $self->escape( $self->obj->routing_label ) . '">';
    $xml .= "\n";

    if (!$args->{no_items}) {
        if (ref($self->obj->items) && @{ $self->obj->items }) {
            $xml .= "      <items>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_stream=>1 })
                } @{ $self->obj->items }
            ) . "      </items>\n";

        } else {
            $xml .= "      <items/>\n";
        }
    }

	#XXX routing_list_user's?

	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->distribution )->as_xml({ %$args, no_streams=>1 }) if (!$args->{no_distribution});

    $xml .= "    </stream>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::sitem;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '    <serial_item xmlns="http://open-ils.org/spec/holdings/v1" ';

    $xml .= 'id="tag:open-ils.org:serial-item/' . $self->obj->id . '" ';
    $xml .= 'date_expected="' . $self->escape( $self->obj->date_expected ) . '"';
    $xml .= ' date_received="' . $self->escape( $self->obj->date_received ) .'"'if ($self->obj->date_received);

	if ($args->{no_issuance}) {
		my $siss = ref($self->obj->issuance) ? $self->obj->issuance->id : $self->obj->issuance;
	    $xml .= ' issuance="tag:open-ils.org:serial-issuance/' . $siss . '"';
	}

    $xml .= ">\n";

	if (ref($self->obj->notes) && $self->obj->notes) {
		$xml .= "        <notes>\n";
		for my $note ( @{$self->obj->notes} ) {
			next unless ( $note->pub eq 't' );
			$xml .= sprintf('        <note date="%s" title="%s">%s</note>',$note->create_date, $self->escape($note->title), $self->escape($note->value));
			$xml .= "\n";
		}
		$xml .= "        </notes>\n";
    } else {
        $xml .= "      <notes/>\n";
	}

	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->issuance )->as_xml({ %$args, no_items=>1 }) if (!$args->{no_issuance});
	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->stream )->as_xml({ %$args, no_items=>1 }) if (!$args->{no_stream});
	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->unit )->as_xml({ %$args, no_items=>1, no_volumes=>1 }) if ($self->obj->unit && !$args->{no_unit});
	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->uri )->as_xml({ %$args, no_items=>1, no_volumes=>1 }) if ($self->obj->uri && !$args->{no_uri});

    $xml .= "    </serial_item>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::sunit;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '      <serial_unit xmlns="http://open-ils.org/spec/holdings/v1" '.
        'id="tag:open-ils.org:serial-unit/' . $self->obj->id . '" ';

    $xml .= $_ . '="' . $self->escape( $self->obj->$_  ) . '" ' for (qw/
        create_date edit_date copy_number circulate deposit ref holdable deleted
        deposit_amount price barcode circ_modifier circ_as_type opac_visible cost
	status_changed_time floating mint_condition detailed_contents sort_key summary_contents
    /);

    $xml .= ">\n";

    $xml .= '        <status ident="' . $self->obj->status->id . '" opac_visible="' . $self->obj->status->opac_visible . '">' . $self->escape( $self->obj->status->name  ) . "</status>\n";
    $xml .= '        <location ident="' . $self->obj->location->id . '">' . $self->escape( $self->obj->location->name  ) . "</location>\n";
    $xml .= '        <circlib ident="' . $self->obj->circ_lib->id . '">' . $self->escape( $self->obj->circ_lib->name  ) . "</circlib>\n";

    $xml .= '        <circ_lib xmlns="http://open-ils.org/spec/actors/v1" ';
    $xml .= 'id="tag:open-ils.org:actor-org_unit/' . $self->obj->circ_lib->id . '" ';
    $xml .= 'shortname="'.$self->escape( $self->obj->circ_lib->shortname ) .'" ';
    $xml .= 'name="'.$self->escape( $self->obj->circ_lib->name ) .'"/>';
    $xml .= "\n";

	$xml .= "        <copy_notes>\n";
	if (ref($self->obj->notes) && $self->obj->notes) {
		for my $note ( @{$self->obj->notes} ) {
			next unless ( $note->pub eq 't' );
			$xml .= sprintf('        <copy_note date="%s" title="%s">%s</copy_note>',$note->create_date, $self->escape($note->title), $self->escape($note->value));
			$xml .= "\n";
		}
	}

	$xml .= "        </copy_notes>\n";
    $xml .= "        <statcats>\n";

	if (ref($self->obj->stat_cat_entries) && $self->obj->stat_cat_entries) {
		for my $sce ( @{$self->obj->stat_cat_entries} ) {
			next unless ( $sce->stat_cat->opac_visible eq 't' );
			$xml .= sprintf('          <statcat name="%s">%s</statcat>',$self->escape($sce->stat_cat->name) ,$self->escape($sce->value));
			$xml .= "\n";
		}
	}
	$xml .= "        </statcats>\n";

    unless ($args->{no_volume}) {
        if (ref($self->obj->call_number)) {
            $xml .= OpenILS::Application::SuperCat::unAPI
                        ->new( $self->obj->call_number )
                        ->as_xml({ %$args, no_copies=>1 });
        } else {
            $xml .= "    <volume/>\n";
        }
    }

    $xml .= "      </serial_unit>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::scap;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '      <caption_and_pattern xmlns="http://open-ils.org/spec/holdings/v1" '.
        'id="tag:open-ils.org:serial-caption_and_pattern/' . $self->obj->id . '" ';

    $xml .= $_ . '="' . $self->escape( $self->obj->$_  ) . '" ' for (qw/
        create_date type active pattern_code enum_1 enum_2 enum_3 enum_4
		enum_5 enum_6 chron_1 chron_2 chron_3 chron_4 chron_5 start_date end_date
    /);
    $xml .= ">\n";
	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->subscription )->as_xml({ %$args, no_captions_and_patterns=>1 }) if (!$args->{no_subscription});
    $xml .= "      </caption_and_pattern>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::siss;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '      <issuance xmlns="http://open-ils.org/spec/holdings/v1" '.
        'id="tag:open-ils.org:serial-issuance/' . $self->obj->id . '" ';

    $xml .= $_ . '="' . $self->escape( $self->obj->$_  ) . '" '
		for (qw/create_date edit_date label date_published holding_code holding_type holding_link_id/);

    $xml .= ">\n";

    if (!$args->{no_items}) {
        if (ref($self->obj->items) && @{ $self->obj->items }) {
            $xml .= "      <items>\n" . join(
                '',
                map {
                    OpenILS::Application::SuperCat::unAPI
                        ->new( $_ )
                        ->as_xml({ %$args, no_stream=>1 })
                } @{ $self->obj->items }
            ) . "      </items>\n";

        } else {
            $xml .= "      <items/>\n";
        }
    }

	$xml .= OpenILS::Application::SuperCat::unAPI->new( $self->obj->subscription )->as_xml({ %$args, no_issuances=>1 }) if (!$args->{no_subscription});
    $xml .= "      </issuance>\n";

    return $xml;
}

package OpenILS::Application::SuperCat::unAPI::acp;
use base qw/OpenILS::Application::SuperCat::unAPI/;

sub as_xml {
    my $self = shift;
    my $args = shift;

    my $xml = '      <copy xmlns="http://open-ils.org/spec/holdings/v1" '.
        'id="tag:open-ils.org:asset-copy/' . $self->obj->id . '" ';

    $xml .= $_ . '="' . $self->escape( $self->obj->$_  ) . '" ' for (qw/
        create_date edit_date copy_number circulate deposit ref holdable deleted
        deposit_amount price barcode circ_modifier circ_as_type opac_visible
    /);

    $xml .= ">\n";

    $xml .= '        <status ident="' . $self->obj->status->id . '" opac_visible="' . $self->obj->status->opac_visible . '">' . $self->escape( $self->obj->status->name  ) . "</status>\n";
    $xml .= '        <location ident="' . $self->obj->location->id . '" opac_visible="'.$self->obj->location->opac_visible.'">' . $self->escape( $self->obj->location->name  ) . "</location>\n";
    $xml .= '        <circlib ident="' . $self->obj->circ_lib->id . '" opac_visible="'.$self->obj->circ_lib->opac_visible.'">' . $self->escape( $self->obj->circ_lib->name  ) . "</circlib>\n";

    $xml .= '        <circ_lib xmlns="http://open-ils.org/spec/actors/v1" ';
    $xml .= 'id="tag:open-ils.org:actor-org_unit/' . $self->obj->circ_lib->id . '" ';
    $xml .= 'shortname="'.$self->escape( $self->obj->circ_lib->shortname ) .'" ';
    $xml .= 'name="'.$self->escape( $self->obj->circ_lib->name ) .'" opac_visible="'.$self->obj->circ_lib->opac_visible.'"/>';
    $xml .= "\n";

	$xml .= "        <monograph_parts>\n";
	if (ref($self->obj->parts) && $self->obj->parts) {
		for my $part ( @{$self->obj->parts} ) {
			$xml .= sprintf('        <monograph_part record="%s" sortkey="%s">%s</monograph_part>',$part->record, $self->escape($part->label_sortkey), $self->escape($part->label));
			$xml .= "\n";
		}
	}

	$xml .= "        </monograph_parts>\n";
	$xml .= "        <copy_notes>\n";
	if (ref($self->obj->notes) && $self->obj->notes) {
		for my $note ( @{$self->obj->notes} ) {
			next unless ( $note->pub eq 't' );
			$xml .= sprintf('        <copy_note date="%s" title="%s">%s</copy_note>',$note->create_date, $self->escape($note->title), $self->escape($note->value));
			$xml .= "\n";
		}
	}

	$xml .= "        </copy_notes>\n";
    $xml .= "        <statcats>\n";

	if (ref($self->obj->stat_cat_entries) && $self->obj->stat_cat_entries) {
		for my $sce ( @{$self->obj->stat_cat_entries} ) {
			next unless ( $sce->stat_cat->opac_visible eq 't' );
			$xml .= sprintf('          <statcat name="%s">%s</statcat>',$self->escape($sce->stat_cat->name) ,$self->escape($sce->value));
			$xml .= "\n";
		}
	}
	$xml .= "        </statcats>\n";

    unless ($args->{no_volume}) {
        if (ref($self->obj->call_number)) {
            $xml .= OpenILS::Application::SuperCat::unAPI
                        ->new( $self->obj->call_number )
                        ->as_xml({ %$args, no_copies=>1 });
        } else {
            $xml .= "    <volume/>\n";
        }
    }

    $xml .= "      </copy>\n";

    return $xml;
}


1;
# vim: et:ts=4:sw=4
