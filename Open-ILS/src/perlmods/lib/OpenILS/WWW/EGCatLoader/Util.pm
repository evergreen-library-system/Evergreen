package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use File::Spec;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::MultiSession;
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
    eg_cache_hash => undef
);

sub init_ro_object_cache {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    # reset org unit setting cache on each page load to avoid the
    # requirement of reloading apache with each org-setting change
    $cache{org_settings} = {};

    if($ro_object_subs) {
        # subs have been built.  insert into the context then move along.
        $ctx->{$_} = $ro_object_subs->{$_} for keys %$ro_object_subs;
        return;
    }

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

        # Retrieve the full set of objects with class $hint
        $ro_object_subs->{$list_key} = sub {
            my $method = "retrieve_all_$eclass";
            $cache{list}{$ctx->{locale}}{$hint} = $e->$method() unless $cache{list}{$ctx->{locale}}{$hint};
            return $cache{list}{$ctx->{locale}}{$hint};
        };

        # locate object of class $hint with Ident field $id
        $cache{map}{$hint} = {};
        $ro_object_subs->{$get_key} = sub {
            my $id = shift;
            return $cache{map}{$ctx->{locale}}{$hint}{$id} if $cache{map}{$ctx->{locale}}{$hint}{$id};
            ($cache{map}{$ctx->{locale}}{$hint}{$id}) = grep { $_->$ident_field eq $id } @{$ro_object_subs->{$list_key}->()};
            return $cache{map}{$ctx->{locale}}{$hint}{$id};
        };

        # search for objects of class $hint where field=value
        $cache{search}{$hint} = {};
        $ro_object_subs->{$search_key} = sub {
            my ($field, $val, $filterfield, $filterval) = @_;
            my $method = "search_$eclass";
            my $cacheval = $val;
            if (ref $val) {
                $val = [sort(@$val)] if ref $val eq 'ARRAY';
                $cacheval = OpenSRF::Utils::JSON->perl2JSON($val);
                #$self->apache->log->info("cacheval : $cacheval");
            }
            my $search_obj = {$field => $val};
            if($filterfield) {
                $search_obj->{$filterfield} = $filterval;
                $cacheval .= ':' . $filterfield . ':' . $filterval;
            }
            #$cache{search}{$ctx->{locale}}{$hint}{$field} = {} unless $cache{search}{$ctx->{locale}}{$hint}{$field};
            $cache{search}{$ctx->{locale}}{$hint}{$field}{$cacheval} = $e->$method($search_obj)
                unless $cache{search}{$ctx->{locale}}{$hint}{$field}{$cacheval};
            return $cache{search}{$ctx->{locale}}{$hint}{$field}{$cacheval};
        };
    }

    $ro_object_subs->{aou_tree} = sub {

        # fetch the org unit tree
        unless($cache{aou_tree}{$ctx->{locale}}) {
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
                my $ro_object_subs = shift;
                my $ctx = shift;
                $node->ou_type( $ro_object_subs->{get_aout}->($node->ou_type) );
                $cache{map}{$ctx->{locale}}{aou}{$node->id} = $node;
                flesh_aout($_, $ro_object_subs, $ctx) foreach @{$node->children};
            };
            flesh_aout($tree, $ro_object_subs, $ctx);

            $cache{aou_tree}{$ctx->{locale}} = $tree;
        }

        return $cache{aou_tree}{$ctx->{locale}};
    };

    # Add a special handler for the tree-shaped org unit cache
    $ro_object_subs->{get_aou} = sub {
        my $org_id = shift;
        return undef unless defined $org_id;
        $ro_object_subs->{aou_tree}->(); # force the org tree to load
        return $cache{map}{$ctx->{locale}}{aou}{$org_id};
    };

    # Returns a flat list of aou objects.  often easier to manage than a tree.
    $ro_object_subs->{aou_list} = sub {
        $ro_object_subs->{aou_tree}->(); # force the org tree to load
        return [ values %{$cache{map}{$ctx->{locale}}{aou}} ];
    };

    $ro_object_subs->{aouct_tree} = sub {

        # fetch the org unit tree
        unless(exists $cache{aouct_tree}{$ctx->{locale}}) {
            $cache{aouct_tree}{$ctx->{locale}} = undef;

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
                        $child_org->ou_type( $ro_object_subs->{get_aout}->($child_org->ou_type) );
                        push(@{$aou->children}, $child_org);
                        push(@nodes, $cnode);
                    }
                }

                $cache{aouct_tree}{$ctx->{locale}} = $node_tree->org_unit;
            }
        }

        return $cache{aouct_tree}{$ctx->{locale}};
    };

    # turns an ISO date into something TT can understand
    $ro_object_subs->{parse_datetime} = sub {
        my $date = shift;
        $date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($date));
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
    $ro_object_subs->{get_org_setting} = sub {
        my($org_id, $setting) = @_;

        $cache{org_settings}{$ctx->{locale}}{$org_id}{$setting} =
            $U->ou_ancestor_setting_value($org_id, $setting)
                unless exists $cache{org_settings}{$ctx->{locale}}{$org_id}{$setting};

        return $cache{org_settings}{$ctx->{locale}}{$org_id}{$setting};
    };

    $ctx->{$_} = $ro_object_subs->{$_} for keys %$ro_object_subs;
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

sub get_records_and_facets {
    my ($self, $rec_ids, $facet_key, $unapi_args) = @_;

    $unapi_args ||= {};
    $unapi_args->{site} ||= $self->ctx->{aou_tree}->()->shortname;
    $unapi_args->{depth} ||= $self->ctx->{aou_tree}->()->ou_type->depth;
    $unapi_args->{flesh_depth} ||= 5;

    my @data;
    my $outer_self = $self;
    $self->timelog("get_records_and_facets(): about to call multisession");
    my $ses = OpenSRF::MultiSession->new(
        app => 'open-ils.cstore',
        cap => 10, # XXX config
        success_handler => sub {
            my($self, $req) = @_;
            my $data = $req->{response}->[0]->content;

            $outer_self->timelog("get_records_and_facets(): got response content");

            # Protect against requests for non-existent records
            return unless $data->{'unapi.bre'};

            my $xml = XML::LibXML->new->parse_string($data->{'unapi.bre'})->documentElement;

            $outer_self->timelog("get_records_and_facets(): parsed xml");
            # Protect against legacy invalid MARCXML that might not have a 901c
            my $bre_id;
            my $bre_id_nodes =  $xml->find('*[@tag="901"]/*[@code="c"]');
            if ($bre_id_nodes) {
                $bre_id =  $bre_id_nodes->[0]->textContent;
            } else {
                $logger->warn("Missing 901 subfield 'c' in " . $xml->toString());
            }
            push(@data, {id => $bre_id, marc_xml => $xml});
            $outer_self->timelog("get_records_and_facets(): end of success handler");
        }
    );

    $self->timelog("get_records_and_facets(): about to call unapi.bre via json_query (rec_ids has " . scalar(@$rec_ids));

    $ses->request(
        'open-ils.cstore.json_query',
         {from => [
            'unapi.bre', $_, 'marcxml','record', 
            $unapi_args->{flesh}, 
            $unapi_args->{site}, 
            $unapi_args->{depth}, 
            'acn=>' . $unapi_args->{flesh_depth} . ',acp=>' . $unapi_args->{flesh_depth}, 
            undef, undef, $unapi_args->{pref_lib}
        ]}
    ) for @$rec_ids;


    $self->timelog("get_records_and_facets():almost ready to fetch facets");
    # collect the facet data
    my $search = OpenSRF::AppSession->create('open-ils.search');
    my $facet_req = $search->request(
        'open-ils.search.facet_cache.retrieve', $facet_key, 10
    ) if $facet_key;

    # gather up the unapi recs
    $ses->session_wait(1);
    $self->timelog("get_records_and_facets():past session wait");

    my $facets = {};
    if ($facet_key) {
        my $tmp_facets = $facet_req->gather(1);
        $self->timelog("get_records_and_facets(): gathered facet data");
        for my $cmf_id (keys %$tmp_facets) {

            # sort highest to lowest match count
            my @entries;
            my $entries = $tmp_facets->{$cmf_id};
            for my $ent (keys %$entries) {
                push(@entries, {value => $ent, count => $$entries{$ent}});
            };
            @entries = sort { $b->{count} <=> $a->{count} } @entries;
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

    return ($facets, @data);
}

# TODO: blend this code w/ ^-- get_records_and_facets
sub fetch_marc_xml_by_id {
    my ($self, $id_list) = @_;
    $id_list = [$id_list] unless ref($id_list);

    {
        no warnings qw/numeric/;
        $id_list = [map { int $_ } @$id_list];
        $id_list = [grep { $_ > 0} @$id_list];
    };

    return {} if scalar(@$id_list) < 1;

    # I'm just sure there needs to be some more efficient way to get all of
    # this.
    my $results = $self->editor->json_query({
        "select" => {"bre" => ["id", "marc"]},
        "from" => {"bre" => {}},
        "where" => {"id" => $id_list}
    }, {substream => 1}) or return $self->editor->die_event;

    my $marc_xml = {};
    for my $r (@$results) {
        $marc_xml->{$r->{"id"}} =
            (new XML::LibXML)->parse_string($r->{"marc"});
    }

    return $marc_xml;
}

sub _get_search_lib {
    my $self = shift;
    my $ctx = $self->ctx;

    # avoid duplicate lookups
    return $ctx->{search_ou} if $ctx->{search_ou};

    my $loc = $ctx->{copy_location_group_org};
    return $loc if $loc;

    # loc param takes precedence
    $loc = $self->cgi->param('loc');
    return $loc if $loc;

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

    if ($ctx->{user}) {
        # See if the user has a search library preference
        my $lset = $self->editor->search_actor_user_setting({
            usr => $ctx->{user}->id, 
            name => 'opac.default_search_location'
        })->[0];
        return OpenSRF::Utils::JSON->JSON2perl($lset->value) if $lset;

        # Otherwise return the user's home library
        return $ctx->{user}->home_ou;
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
# "logc" param, which takes the form org_id:grp_id.
sub extract_copy_location_group_info {
    my $self = shift;
    my $ctx = $self->ctx;
    if (my $clump = $self->cgi->param('locg')) {
        my ($org, $grp) = split(/:/, $clump);
        $ctx->{copy_location_group_org} = $org;
        $ctx->{copy_location_group} = $grp if $grp;
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
        {order_by => {acplg => 'pos'}}
    ]);

    my %buckets;
    push(@{$buckets{$_->owner}}, $_) for @$grps;
    $ctx->{copy_location_groups} = \%buckets;
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
                    }
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

1;
