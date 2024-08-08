package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use File::Spec;
use Time::HiRes qw/time sleep/;
use List::MoreUtils qw(uniq);
use HTML::TreeBuilder;
use HTML::Element;
use HTML::Defang;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::MultiSession;

my $defang = HTML::Defang->new;
my $U = 'OpenILS::Application::AppUtils';

my $ro_object_subs; # cached subs
our %cache = ( # cached data
    map => {en_us => {}},
    list => {en_us => {}},
    search => {en_us => {}},
    org_settings => {en_us => {}},
    search_filter_groups => {en_us => {}},
    aou_tree => {en_us => undef},
    aouct_tree => {},
    eg_cache_hash => undef,
    authority_fields => {en_us => {}}
);

sub child_init {
    my $class = shift;
    my %locales = @_;

    # create a stub object with just enough in place
    # to call init_ro_object_cache()
    my $stub = bless({}, ref($class) || $class);
    my $ctx = {};
    $stub->ctx($ctx);

    foreach my $locale (sort keys %locales) {
        OpenSRF::AppSession->default_locale($locales{$locale});
        $ctx->{locale} = $locale;
        $stub->init_ro_object_cache();

        # pre-cache various sets of objects
        # known to be time-consuming to retrieve
        # the first go around
        $ro_object_subs->{$locale}->{aou_tree}();
        $ro_object_subs->{$locale}->{aouct_tree}();
        $ro_object_subs->{$locale}->{ccvm_list}();
        $ro_object_subs->{$locale}->{crad_list}();
        $ro_object_subs->{$locale}->{get_authority_fields}(1);
    }
}

sub init_ro_object_cache {
    my $self = shift;
    my $ctx = $self->ctx;
    my $memcache ||= OpenSRF::Utils::Cache->new('global');

    # reset org unit setting cache on each page load to avoid the
    # requirement of reloading apache with each org-setting change
    $cache{org_settings} = {};

    if($ro_object_subs->{$ctx->{locale}}) {
        # subs have been built.  insert into the context then move along.
        $ctx->{$_} = $ro_object_subs->{$ctx->{locale}}->{$_} for keys %{ $ro_object_subs->{$ctx->{locale}} };
        return;
    }

    my $locale_subs = {};
    my $locale = $ctx->{locale};

    # Create special-purpose subs

    # aou is special because it's tree-ish
    $locale_subs->{aou_tree} = sub {

        # fetch the org unit tree
        unless($cache{aou_tree}{$locale}) {
            my $e = new_editor();
            my $tree = $e->search_actor_org_unit([
                {   parent_ou => undef},
                {   flesh            => -1,
                    flesh_fields    => {aou =>  ['children']},
                    order_by        => {aou => 'name'}
                }
            ])->[0];

            # flesh the org unit type for each org unit
            # and simultaneously set the id => aou map cache
            sub flesh_aout {
                my $node = shift;
                my $locale_subs = shift;
                my $locale = shift;
                $node->ou_type( $locale_subs->{get_aout}->($node->ou_type) );
                $cache{map}{$locale}{aou}{$node->id} = $node;
                flesh_aout($_, $locale_subs, $locale) foreach @{$node->children};
            };
            flesh_aout($tree, $locale_subs, $locale);
            undef $e;
            $cache{aou_tree}{$locale} = $tree;
        }

        return $cache{aou_tree}{$locale};
    };

    # Add a special handler for the tree-shaped org unit cache
    $locale_subs->{get_aou} = sub {
        my $org_id = shift;
        return undef unless defined $org_id;
        $locale_subs->{aou_tree}->(); # force the org tree to load
        return $cache{map}{$locale}{aou}{$org_id};
    };

    # Returns a flat list of aout objects, sorted by depth and opac_label.
    $locale_subs->{sorted_aout_list} = sub {
        return [ sort { $a->depth() <=> $b->depth() || $a->opac_label() cmp $b->opac_label() } @{$locale_subs->{aout_list}->()} ];
    };

    # Returns a flat list of aou objects.  often easier to manage than a tree.
    $locale_subs->{aou_list} = sub {
        $locale_subs->{aou_tree}->(); # force the org tree to load
        return [ values %{$cache{map}{$locale}{aou}} ];
    };

    # returns the org unit object by shortname
    $locale_subs->{get_aou_by_shortname} = sub {
        my $sn = shift or return undef;
        my $list = $locale_subs->{aou_list}->();
        return (grep {$_->shortname eq $sn} @$list)[0];
    };

    # Defang an HTML string
    $locale_subs->{defang_string} = sub {
        my $html = shift;
        return $defang->defang($html);
    };

    # Turns one string into two for long text strings
    $locale_subs->{split_for_accordion} = sub {
        my $html = shift;
        my $trunc_length = shift;

        return unless defined $html && defined $trunc_length;
        
        my $html_string = "";
        my $trunc_str = "<span class='truncEllipse'>...</span><span class='truncated' style='display:none'>";
        my $current_length = 0;
        my $truncated;
        my @html_strings;

        my $html_tree = HTML::TreeBuilder->new;
        $html_tree->parse($html);
        $html_tree->eof();

        # Navigate #html_tree to determine length of contained strings
        my @nodes = $html_tree->guts();
        foreach my $node(@nodes) {
            my $nref = ref $node;
            if ($nref eq "HTML::Element") {
                $current_length += length $node->as_text();
                my $escaped_html = $defang->defang($node->as_HTML());
                push(@html_strings, $escaped_html);
            } else {
                # Node is whitespace - handling this like regular simple text
                # doesn't like to play nice, so handling separately
                if ($node eq ' ') { 
                    $current_length++;
                    if ($current_length >= $trunc_length and not $truncated) {
                        push(@html_strings, " $trunc_str");
                        $truncated = 1;
                    } else {
                        push(@html_strings, $defang->defang($node));
                    }
                # Node is simple text
                } else {
                    my $new_length += length $node;
                    if ($new_length >= $trunc_length and not $truncated) {
                        my $nshort;
                        my $nrest;
                        my $calc_length = abs($trunc_length - $current_length);
                        if ((substr $node, $calc_length, 1) =~ /\s/) {
                            $nshort = substr $node, 0, $calc_length;
                            $nrest = substr $node, $calc_length;
                        } else {
                            my $nloc = rindex $node, ' ', $calc_length;
                            $nshort = substr $node, 0, $nloc;
                            $nrest = substr $node, $nloc;
                        }
                        $nshort = $defang->defang($nshort);
                        $nrest = $defang->defang($nrest);
                        push(@html_strings, "$nshort $trunc_str $nrest");
                        $truncated = 1;
                    } else {
                        push(@html_strings, $defang->defang($node));
                    }
                    $current_length += length $node;
                }
            }
        }
        if ($truncated) {
            push(@html_strings, "</span>");
        }
 
        if (@html_strings > 1) {
            $html_string = join '', @html_strings;
        } else {
            $html_string = $html_strings[0];
        }

        return ($html_string, $truncated);
    };

    $locale_subs->{aouct_tree} = sub {

        # fetch the org unit tree
        unless(exists $cache{aouct_tree}{$locale}) {
            $cache{aouct_tree}{$locale} = undef;

            my $e = new_editor();
            my $tree_id = $e->search_actor_org_unit_custom_tree(
                {purpose => 'opac', active => 't'},
                {idlist => 1}
            )->[0];

            if ($tree_id) {
                my $node_tree = $e->search_actor_org_unit_custom_tree_node([
                {parent_node => undef, tree => $tree_id},
                {   flesh        => -1,
                    flesh_fields => {aouctn => ['children', 'org_unit']},
                    order_by     => {aouctn => 'sibling_order'}
                }
                ])->[0];

                # tree-ify the org units.  note that since the orgs are fleshed
                # upon retrieval, this org tree will not clobber ctx->{aou_tree}.
                my @nodes = ($node_tree);
                while (my $node = shift(@nodes)) {
                    my $aou = $node->org_unit;
                    $aou->children([]);
                    for my $cnode (@{$node->children}) {
                        my $child_org = $cnode->org_unit;
                        $child_org->parent_ou($aou->id);
                        $child_org->ou_type( $locale_subs->{get_aout}->($child_org->ou_type) );
                        push(@{$aou->children}, $child_org);
                        push(@nodes, $cnode);
                    }
                }

                $cache{aouct_tree}{$locale} = 
                    $node_tree->org_unit if $node_tree;
            }
            undef $e;
        }

        return $cache{aouct_tree}{$locale};
    };

    # turns an ISO date into something TT can understand
    $locale_subs->{parse_datetime} = sub {
        my $date = shift;
        my $context_org = shift; # optional, for setting timezone via YAOUS

        # Calling parse_datetime() with empty $date will lead to Internal Server Error
        return '' if (!defined($date) or $date eq '');

        # Probably an accidental entry like '0212' instead of '2012',
        # but 1) the leading 0 may get stripped in cstore and
        # 2) DateTime::Format::ISO8601 returns an error as years
        # must be 2 or 4 digits
        if ($date =~ m/^\d{3}-/) {
            $logger->warn("Invalid date had a 3-digit year: $date");
            $date = '0' . $date;
        } elsif ($date =~ m/^\d{1}-/) {
            $logger->warn("Invalid date had a 1-digit year: $date");
            $date = '000' . $date;
        }

        my $cleansed_date = clean_ISO8601($date);

        $date = DateTime::Format::ISO8601->new->parse_datetime($cleansed_date);
        if ($context_org) {
            $context_org = $context_org->id if ref($context_org);
            my $tz = $locale_subs->{get_org_setting}->($context_org,'lib.timezone');
            if ($tz) {
                try {
                    $date->set_time_zone($tz);
                } catch Error with {
                    $logger->warn("Invalid timezone: $tz");
                };
            }
        }
        return sprintf(
            "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
            $date->hour,
            $date->minute,
            $date->second,
            $date->day,
            $date->month,
            $date->year
        );
    };

    # retrieve and cache org unit setting values
    $locale_subs->{get_org_setting} = sub {
        my($org_id, $setting) = @_;

        $cache{org_settings}{$locale}{$org_id}{$setting} =
            $U->ou_ancestor_setting_value($org_id, $setting)
                unless exists $cache{org_settings}{$locale}{$org_id}{$setting};

        return $cache{org_settings}{$locale}{$org_id}{$setting};
    };

    # retrieve and cache acsaf values
    $locale_subs->{get_authority_fields} = sub {
        my ($control_set) = @_;

        if (not exists $cache{authority_fields}{$locale}{$control_set}) {
            my $e = new_editor();
            if (my $acs = $e->search_authority_control_set_authority_field(
                                    {control_set => $control_set}
                                )
            ) {
                $cache{authority_fields}{$locale}{$control_set} =
                 +{ map { $_->id => $_ } @$acs };
                undef $e;
            } else {
                undef $e;
                return;
            }
        }

        return $cache{authority_fields}{$locale}{$control_set};
    };

    # make all "field_safe" classes accesible by default in the template context
    my @classes = grep {
        ($Fieldmapper::fieldmap->{$_}->{field_safe} || '') =~ /true/i
    } keys %{ $Fieldmapper::fieldmap };

    for my $class (@classes) {

        my $hint = $Fieldmapper::fieldmap->{$class}->{hint};
        next if $hint eq 'aou'; # handled separately

        my $ident_field =  $Fieldmapper::fieldmap->{$class}->{identity};
        (my $eclass = $class) =~ s/Fieldmapper:://o;
        $eclass =~ s/::/_/g;

        my $list_key = "${hint}_list";
        my $get_key = "get_$hint";
        my $search_key = "search_$hint";

        my $memcache_key = join('.', 'EGWeb',$locale,$hint) . '.';

        # Retrieve the full set of objects with class $hint
        $locale_subs->{$list_key} ||= sub {
            my $from_memcache = 0;
            my $list = $memcache->get_cache($memcache_key.'list');
            if ($list) {
                $cache{list}{$locale}{$hint} = $list;
                $from_memcache = 1;
            }
            my $method = "retrieve_all_$eclass";
            my $e = new_editor();
            $cache{list}{$locale}{$hint} = $e->$method() unless $cache{list}{$locale}{$hint};
            undef $e;
            $memcache->put_cache($memcache_key.'list',$cache{list}{$locale}{$hint}) unless $from_memcache;
            return $cache{list}{$locale}{$hint};
        };

        # locate object of class $hint with Ident field $id
        $cache{map}{$hint} = {};
        $locale_subs->{$get_key} ||= sub {
            my $id = shift;
            return $cache{map}{$locale}{$hint}{$id} if $cache{map}{$locale}{$hint}{$id};
            ($cache{map}{$locale}{$hint}{$id}) = grep { $_->$ident_field eq $id } @{$locale_subs->{$list_key}->()};
            return $cache{map}{$locale}{$hint}{$id};
        };

        # search for objects of class $hint where field=value
        $cache{search}{$hint} = {};
        $locale_subs->{$search_key} ||= sub {
            my ($field, $val, $filterfield, $filterval) = @_;
            my $method = "search_$eclass";
            my $cacheval = $val;
            my $scalar_cacheval = 1;

            if (ref $val) {
                $scalar_cacheval = 0;
                $val = [sort(@$val)] if ref $val eq 'ARRAY';
                $cacheval = OpenSRF::Utils::JSON->perl2JSON($val);
                #$self->apache->log->info("cacheval : $cacheval");
            }

            my $search_obj = {$field => $val};
            if($filterfield) {
                $search_obj->{$filterfield} = $filterval;
                $cacheval .= ':' . $filterfield . ':' . $filterval;
            } elsif (
                $scalar_cacheval
                and $cache{list}{$locale}{$hint}
                and !$cache{search}{$locale}{$hint}{$field}{$cacheval}
            ) {
                return $cache{search}{$locale}{$hint}{$field}{$cacheval} =
                    [ grep { $_->$field() eq $val } @{$cache{list}{$locale}{$hint}} ];
            }

            my $e = new_editor();
            $cache{search}{$locale}{$hint}{$field}{$cacheval} = $e->$method($search_obj)
                unless $cache{search}{$locale}{$hint}{$field}{$cacheval};
            undef $e;
            return $cache{search}{$locale}{$hint}{$field}{$cacheval};
        };
    }

    $ctx->{$_} = $locale_subs->{$_} for keys %$locale_subs;
    $ro_object_subs->{$locale} = $locale_subs;
}

sub generic_redirect {
    my $self = shift;
    my $url = shift;
    my $cookie = shift; # can be an array of cgi.cookie's

    $self->apache->print(
        $self->cgi->redirect(
            -url => $url || 
                $self->cgi->param('redirect_to') || 
                $self->ctx->{referer} || 
                $self->ctx->{home_page},
            -cookie => $cookie
        )
    );

    return Apache2::Const::REDIRECT;
}

my $unapi_cache;
sub get_records_and_facets {
    my ($self, $rec_ids, $facet_key, $unapi_args) = @_;

    # collect the facet data
    my $search = OpenSRF::AppSession->create('open-ils.search');
    my $facet_req;
    if ($facet_key) {
        $facet_req = $search->request(
            'open-ils.search.facet_cache.retrieve', $facet_key
        );
    }

    $unapi_args ||= {};
    $unapi_args->{site} ||= $self->ctx->{aou_tree}->()->shortname;
    $unapi_args->{depth} ||= $self->ctx->{aou_tree}->()->ou_type->depth;
    $unapi_args->{flesh_depth} ||= 5;

    my $is_meta = delete $unapi_args->{metarecord};
    #my $unapi_type = $is_meta ? 'unapi.mmr' : 'unapi.bre';
    my $unapi_type = $is_meta ? 'unapi.metabib_virtual_record_feed' : 'unapi.biblio_record_entry_feed';

    $unapi_cache ||= OpenSRF::Utils::Cache->new('global');
    my $unapi_cache_key_suffix = join(
        '_',
        $is_meta || 0,
        $unapi_args->{site},
        $unapi_args->{depth},
        $unapi_args->{flesh_depth},
        ($unapi_args->{pref_lib} || '')
    );

    my %tmp_data;
    my %hl_tmp_data;
    my $outer_self = $self;

    my $sdepth = $unapi_args->{flesh_depth};
    my $slimit = "acn=>$sdepth,acp=>$sdepth";
    $slimit .= ",bre=>$sdepth" if $is_meta;
    my $flesh = $unapi_args->{flesh} || '';

    # tag the record with the MR id
    $flesh =~ s/}$/,mmr.unapi}/g if $is_meta;

    my $ses = OpenSRF::AppSession->create('open-ils.cstore');
    my $hl_ses = OpenSRF::AppSession->create('open-ils.search');

    my @loop_recs;
    for my $bid (@$rec_ids) {
        my $unapi_cache_key = 'TPAC_unapi_cache_'.$bid.'_'.$unapi_cache_key_suffix;
        my $unapi_data = $unapi_cache->get_cache($unapi_cache_key);

        if (!$unapi_data || $unapi_data->{running}) { #cache entry not done yet, get our own copy
            push(@loop_recs, $bid);
        } else {
            $unapi_data->{marc_xml} = XML::LibXML->new->parse_string($unapi_data->{marc_xml})->documentElement;
            $tmp_data{$unapi_data->{id}} = $unapi_data;
            $unapi_cache->put_cache($unapi_cache_key, { running => $$ }, 5);
        }
    }

    my $hl_req = $hl_ses->request(
        'open-ils.search.fetch.metabib.display_field.highlight.atomic',
        $self->ctx->{query_struct}{additional_data}{highlight_map},
        @$rec_ids
    ) if (!$is_meta);

    if (@loop_recs) {
        my $unapi_req = $ses->request(
            'open-ils.cstore.json_query',
             {from => [
                $unapi_type, '{'.join(',',@loop_recs).'}', 'marcxml', $flesh,
                $unapi_args->{site}, 
                $unapi_args->{depth}, 
                $slimit,
                undef, undef, undef, undef, undef, undef, undef, undef,
                $unapi_args->{pref_lib}
            ]}
        );
    
        my $data = $unapi_req->gather(1);
    
        $outer_self->timelog("get_records_and_facets(): got feed content");
    
        # Protect against requests for non-existent records
        return unless ($data->{$unapi_type});
    
        my $doc = XML::LibXML->new->parse_string($data->{$unapi_type})->documentElement;
    
        $outer_self->timelog("get_records_and_facets(): parsed xml");
        for my $xml ($doc->getElementsByTagName('record')) {
            $xml = XML::LibXML->new->parse_string($xml->toString)->documentElement;
    
            # Protect against legacy invalid MARCXML that might not have a 901c
            my $bre_id;
            my $mmr_id;
            my $bre_id_nodes =  $xml->find('*[@tag="901"]/*[@code="c"]');
            if ($bre_id_nodes) {
                $bre_id =  $bre_id_nodes->[0]->textContent;
            } else {
                $logger->warn("Missing 901 subfield 'c' in " . $xml->toString());
            }
        
            if ($is_meta) {
                # extract metarecord ID from mmr.unapi tag
                for my $node ($xml->getElementsByTagName('abbr')) {
                    my $title = $node->getAttribute('title');
                    ($mmr_id = $title) =~ 
                        s/tag:open-ils.org:U2\@mmr\/(\d+)\/.*/$1/g;
                    last if $mmr_id;
                }
            }
        
            my $rec_id = $mmr_id ? $mmr_id : $bre_id;
            $tmp_data{$rec_id} = {
                id => $rec_id, 
                bre_id => $bre_id, 
                mmr_id => $mmr_id,
                marc_xml => $xml
            };
        
            if ($rec_id) {
                # Let other backends grab our data now that we're done.
                my $key = 'TPAC_unapi_cache_'.$rec_id.'_'.$unapi_cache_key_suffix;
                my $cache_data = $unapi_cache->get_cache($key);
                if (!$cache_data || $$cache_data{running} == $$) {
                    $unapi_cache->put_cache($key, {
                        bre_id => $bre_id,
                        mmr_id => $mmr_id,
                        id => $rec_id, 
                        marc_xml => $xml->toString
                    }, 10);
                }
            }
        }
    }

    if (!$is_meta) {
        my $hl_data = $hl_req->gather(1); # list of arrayref of hashrefs
        $self->ctx->{_hl_data} = { map { ''.$$_[0]{source} => $_ } @$hl_data };
        $outer_self->timelog("get_records_and_facets(): got highlighting content (". keys(%{$self->ctx->{_hl_data}}).")");
    }

    my $facets = {};
    if ($facet_req) {
        $self->timelog("get_records_and_facets():almost ready to fetch facets");

        my $tmp_facets = $facet_req->gather(1);
        $self->timelog("get_records_and_facets(): gathered facet data");
        for my $cmf_id (keys %$tmp_facets) {

            # sort highest to lowest match count
            my @entries;
            my $entries = $tmp_facets->{$cmf_id};
            for my $ent (keys %$entries) {
                push(@entries, {value => $ent, count => $$entries{$ent}});
            };

            # Sort facet entries by 1) count descending, 2) text ascending
            @entries = sort {
                $b->{count} <=> $a->{count} ||
                $a->{value} cmp $b->{value}
            } @entries;

            $facets->{$cmf_id} = {
                cmf => $self->ctx->{get_cmf}->($cmf_id),
                data => \@entries
            }
        }
        $self->timelog("get_records_and_facets(): gathered/sorted facet data");
    } else {
        $facets = undef;
    }
    $search->kill_me;


    return ($facets, map { $tmp_data{$_} } @$rec_ids);
}

sub _resolve_org_id_or_shortname {
    my ($self, $str) = @_;

    if (length $str) {
        # Match on shortname case insensitively, but only if there's exactly
        # one match.  We wouldn't want the system to arbitrarily interpret
        # 'foo' as either the org unit with shortname 'FOO' or 'Foo' and fail
        # to make it clear to the user which one was chosen and why.
        my $res = $self->editor->search_actor_org_unit({
            shortname => {
                '=' => {
                    transform => 'evergreen.lowercase',
                    value => lc($str)
                }
            }
        });
        return $res->[0]->id if $res and @$res == 1;
    }

    # Note that we don't validate IDs; we only try a shortname lookup and then
    # assume anything else must be an ID.
    return int($str); # Wrapping in int() prevents 500 on unmatched string.
}

sub _get_search_lib {
    my $self = shift;
    my $ctx = $self->ctx;

    # avoid duplicate lookups
    return $ctx->{search_ou} if $ctx->{search_ou};

    my $loc = $ctx->{copy_location_group_org};
    return $loc if $loc;

    # loc param takes precedence
    # XXX ^-- over what exactly? We could use clarification here. To me it looks
    # like locg takes precedence over loc which in turn takes precedence over
    # request headers which take precedence over pref_lib (which can be
    # specified a lot of different ways and eventually falls back to
    # physical_loc) and it all finally defaults to top of the org tree.
    # To say nothing of all the code that doesn't look to this function at all
    # but rather accesses some subset of these inputs directly.

    $loc = $self->cgi->param('loc');
    return $loc if $loc;

    if ($self->apache->headers_in->get('OILS-Search-Lib')) {
        return $self->apache->headers_in->get('OILS-Search-Lib');
    }
    if ($self->cgi->cookie('eg_search_lib')) {
        return $self->cgi->cookie('eg_search_lib');
    }

    my $pref_lib = $self->_get_pref_lib();
    return $pref_lib if $pref_lib;

    return $ctx->{aou_tree}->()->id;
}

sub _get_pref_lib {
    my $self = shift;
    my $ctx = $self->ctx;

    # plib param takes precedence
    my $plib = $self->cgi->param('plib');
    return $plib if $plib;

    if ($self->apache->headers_in->get('OILS-Pref-Lib')) {
        return $self->apache->headers_in->get('OILS-Pref-Lib');
    }
    if ($self->cgi->cookie('eg_pref_lib')) {
        return $self->cgi->cookie('eg_pref_lib');
    }

    if ($ctx->{user}) {
        # See if the user has a search library preference
        my $lset = $self->editor->search_actor_user_setting({
            usr => $ctx->{user}->id, 
            name => 'opac.default_search_location'
        })->[0];
        return OpenSRF::Utils::JSON->JSON2perl($lset->value) if $lset;

        # Otherwise return the user's home library
        my $ou = $ctx->{user}->home_ou;
        return ref($ou) ? $ou->id : $ou;
    }

    if ($ctx->{physical_loc}) {
        return $ctx->{physical_loc};
    }

}

# This is defensively coded since we don't do much manual reading from the
# file system in this module.
sub load_eg_cache_hash {
    my ($self) = @_;

    # just a context helper
    $self->ctx->{eg_cache_hash} = sub { return $cache{eg_cache_hash}; };

    # Need to actually load the value? If already done, move on.
    return if defined $cache{eg_cache_hash};

    # In this way even if we fail, we won't slow things down by ever trying
    # again within this Apache process' lifetime.
    $cache{eg_cache_hash} = 0;

    my $path = File::Spec->catfile(
        $self->apache->document_root, "eg_cache_hash"
    );

    if (not open FH, "<$path") {
        $self->apache->log->warn("error opening $path : $!");
        return;
    } else {
        my $buf;
        my $rv = read FH, $buf, 64;  # defensive
        close FH;

        if (not defined $rv) {  # error
            $self->apache->log->warn("error reading $path : $!");
        } elsif ($rv > 0) {     # no error, something read
            chomp $buf;
            $cache{eg_cache_hash} = $buf;
        }
    }
}

# Extracts the copy location org unit and group from the 
# "logc" param, which takes the form org_id:grp, where
# grp can either be a location group id or can match the
# pattern "lasso(lasso_name_or_id)".
sub extract_copy_location_group_info {
    my $self = shift;
    my $ctx = $self->ctx;
    if (my $clump = $self->cgi->param('locg')) {
        my ($org, $grp) = split(/:/, $clump);
        if ($grp =~ /^lasso\(([^)]+)\)/) {
            $ctx->{search_lasso} = $1;
            $ctx->{search_scope} = $grp;
            $self->search_lasso_orgs;
        } elsif ($grp) {
            $ctx->{copy_location_group} = $grp;
            $ctx->{search_scope} = "location_groups($grp)";
        }
        $ctx->{copy_location_group_org} =
            $self->_resolve_org_id_or_shortname($org);
    }
}

sub load_copy_location_groups {
    my $self = shift;
    my $ctx = $self->ctx;

    # User can access to the search location groups at the current 
    # search lib, the physical location lib, and the patron's home ou.
    my @ctx_orgs = $ctx->{search_ou};
    push(@ctx_orgs, $ctx->{physical_loc}) if $ctx->{physical_loc};
    push(@ctx_orgs, $ctx->{user}->home_ou) if $ctx->{user};

    my $grps = $self->editor->search_asset_copy_location_group([
        {
            opac_visible => 't',
            owner => {
                in => {
                    select => {aou => [{
                        column => 'id', 
                        transform => 'actor.org_unit_full_path',
                        result_field => 'id',
                    }]},
                    from => 'aou',
                    where => {id => \@ctx_orgs}
                }
            }
        },
        {order_by => [{class => "acplg", field => "pos"},{class => "acplg", field => "name"}]}
    ]);

    my %buckets;
    push(@{$buckets{$_->owner}}, $_) for @$grps;
    $ctx->{copy_location_groups} = \%buckets;
}

sub load_hold_subscriptions {
    my $self = shift;
    my $ctx = $self->ctx;

    return unless $ctx->{authtoken};

    my $e = new_editor(authtoken => $ctx->{authtoken});
    $e->personality('open-ils.pcrud'); # use pcrud mode to filter appropriately

    $ctx->{hold_subscriptions} =
        $e->search_container_user_bucket([
            { btype => 'hold_subscription' },
            { order_by => {cub => 'name'} }
        ]);

}

sub load_my_hold_subscriptions {
    my $self = shift;
    my $ctx = $self->ctx;

    return unless $ctx->{authtoken};

    my $sub_entries = $self->editor->search_container_user_bucket_item(
        { target_user => $ctx->{user}->id }
    );

    my $sub_ids = [ uniq map { $_->bucket } @$sub_entries ];
    $ctx->{my_hold_subscriptions} = scalar(@$sub_ids) ?
        $self->editor->search_container_user_bucket(
            {btype => 'hold_subscription', id => $sub_ids, pub => 't'}
        ) : [];
}

sub search_lasso_orgs {
    my $self = shift;
    my $ctx = $self->ctx;
    return $ctx->{search_lasso_orgs} if defined $ctx->{search_lasso_orgs};
    return undef unless $ctx->{search_lasso};

    # User can access global lassos and those at the current search lib
    my $lasso_maps = $self->editor->search_actor_org_lasso_map(
        { lasso => $ctx->{search_lasso} }
    );
    $ctx->{search_lasso_orgs} = [ map { $_->org_unit } @$lasso_maps];
}

sub load_lassos {
    my $self = shift;
    my $ctx = $self->ctx;

    # User can access global lassos and those at the current search lib
    my $direct_lassos = $self->editor->search_actor_org_lasso_map(
        { org_unit => $ctx->{search_ou} }
    );
    $direct_lassos = [ map { $_->lasso } @$direct_lassos];

    my $lassos = $self->editor->search_actor_org_lasso(
        { '-or' => { global => 't', @$direct_lassos ? (id => { in => $direct_lassos}) : () } }
    );

    $ctx->{lassos} = [ sort { $a->name cmp $b->name } @$lassos ];
    $self->apache->log->info("Fetched ".scalar(@$lassos)." lassos");
}

sub set_file_download_headers {
    my $self = shift;
    my $filename = shift;
    my $ctype = shift || "text/plain; encoding=utf8";

    $self->apache->content_type($ctype);

    $self->apache->headers_out->add(
        "Content-Disposition",
        "attachment;filename=$filename"
    );

    return Apache2::Const::OK;
}

sub apache_log_if_event {
    my ($self, $event, $prefix_text, $success_ok, $level) = @_;

    $prefix_text ||= "Evergreen returned event";
    $success_ok ||= 0;
    $level ||= "warn";

    chomp $prefix_text;
    $prefix_text .= ": ";

    my $code = $U->event_code($event);
    if (defined $code and ($code or not $success_ok)) {
        $self->apache->log->$level(
            $prefix_text .
            ($event->{textcode} || "") . " ($code)" .
            ($event->{note} ? (": " . $event->{note}) : "")
        );
        return 1;
    }

    return;
}

sub load_search_filter_groups {
    my $self = shift;
    my $ctx_org = shift;
    my $org_list = $U->get_org_ancestors($ctx_org, 1);

    my %seen;
    for my $org_id (@$org_list) {

        my $grps;
        if (! ($grps = $cache{search_filter_groups}{$org_id}) ) {
            $grps = $self->editor->search_actor_search_filter_group([
                {owner => $org_id},
                {   flesh => 2, 
                    flesh_fields => {
                        asfg => ['entries'],
                        asfge => ['query']
                    },
                    order_by => {asfge => 'pos'}
                }
            ]);
            $cache{search_filter_groups}{$org_id} = $grps;
        }

        # for the current context, if a descendant org has a group 
        # with a matching code replace the group from the parent.
        $seen{$_->code} = $_ for @$grps;
    }

    return $self->ctx->{search_filter_groups} = \%seen;
}


sub check_for_temp_list_warning {
    my $self = shift;
    my $ctx = $self->ctx;
    my $cgi = $self->cgi;

    my $lib = $self->_get_search_lib;
    my $warn = ($ctx->{get_org_setting}->($lib || 1, 'opac.patron.temporary_list_warn')) ? 1 : 0;

    if ($warn && $ctx->{user}) {
        $self->_load_user_with_prefs;
        my $map = $ctx->{user_setting_map};
        $warn = 0 if ($$map{'opac.temporary_list_no_warn'});
    }

    # Check for a cookie disabling the warning.
    $warn = 0 if ($warn && $cgi->cookie('no_temp_list_warn'));

    return $warn;
}

sub load_org_util_funcs {
    my $self = shift;
    my $ctx = $self->ctx;

    # evaluates to true if test_ou is within the same depth-
    # scoped tree as ctx_ou. both ou's are org unit objects.
    $ctx->{org_within_scope} = sub {
        my ($ctx_ou, $test_ou, $depth) = @_;

        return 1 if $ctx_ou->id == $test_ou->id;

        if ($depth) {

            # find the top-most ctx-org ancestor at the provided depth
            while ($depth < $ctx_ou->ou_type->depth 
                    and $ctx_ou->id != $test_ou->id) {
                $ctx_ou = $ctx->{get_aou}->($ctx_ou->parent_ou);
            }

            # the preceeding loop may have landed on our org
            return 1 if $ctx_ou->id == $test_ou->id;

        } else {

            return 1 if defined $depth; # $depth == 0;
        }

        for my $child (@{$ctx_ou->children}) {
            return 1 if $ctx->{org_within_scope}->($child, $test_ou);
        }

        return 0;
    };

    # Returns true if the provided org unit is within the same 
    # org unit hiding depth-scoped tree as the physical location.
    # Org unit hiding is based on the immutable physical_loc
    # and is not meant to change as search/pref/etc libs change
    $ctx->{org_within_hiding_scope} = sub {
        my $org_id = shift;
        my $ploc = $ctx->{physical_loc} or return 1;

        my $depth = $ctx->{get_org_setting}->(
            $ploc, 'opac.org_unit_hiding.depth');

        return 1 unless $depth; # 0 or undef

        return $ctx->{org_within_scope}->( 
            $ctx->{get_aou}->($ploc), 
            $ctx->{get_aou}->($org_id), $depth);
 
    };

    # Evaluates to true if the context org (defaults to get_library) 
    # is not within the hiding scope.  Also evaluates to true if the 
    # user's pref_ou is set and it's out of hiding scope.
    # Always evaluates to true when ctx.is_staff
    $ctx->{org_hiding_disabled} = sub {
        my $ctx_org = shift || $ctx->{search_ou};

        return 1 if $ctx->{is_staff};

        # beware locg values formatted as org:loc
        $ctx_org =~ s/:.*//g;

        return 1 if !$ctx->{org_within_hiding_scope}->($ctx_org);

        return 1 if $ctx->{pref_ou} and $ctx->{pref_ou} != $ctx_org 
            and !$ctx->{org_within_hiding_scope}->($ctx->{pref_ou});

        return 0;
    };

}

# returns the list of org unit IDs for which the 
# selected org unit setting returned a true value
sub setting_is_true_for_orgs {
    my ($self, $setting) = @_;
    my $ctx = $self->ctx;
    my @valid_orgs;

    my $test_org;
    $test_org = sub {
        my $org = shift;
        push (@valid_orgs, $org->id) if
            $ctx->{get_org_setting}->($org->id, $setting);
        $test_org->($_) for @{$org->children};
    };

    $test_org->($ctx->{aou_tree}->());
    return \@valid_orgs;
}

# Builds and links a perm checking function, testing permissions against
# the currently logged in user.  
# ctx->{has_perm}->(perm_code, org_id) => 1/undef
# For security, perm checks are cached per page, not per process.
sub load_perm_funcs {
    my $self = shift;
    my %perm_cache;
    $self->ctx->{has_perm} = sub {
        my ($perm_code, $org_id) = @_;
        return 0 unless $self->editor->requestor;

        if ($perm_cache{$org_id}) {
            return $perm_cache{$org_id}{$perm_code} 
                if exists $perm_cache{$org_id}{$perm_code};
        } else {
            $perm_cache{$org_id} = {};
        }
        return $perm_cache{$org_id}{$perm_code} =
            $self->editor->allowed($perm_code, $org_id);
    }
}
    


1;
