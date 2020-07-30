package OpenILS::Utils::Configure;

use strict;
use warnings;
use File::Spec;
use OpenILS::Utils::Cronscript;

sub fieldmapper {
    my $web = shift;

    my $core = OpenILS::Utils::Cronscript->new({nolockfile => 1});
    $core->bootstrap;

    my $output;
    my $map = $Fieldmapper::fieldmap;

    # if a true value is provided, we generate the web (light) version of the fieldmapper
    if(!$web) { $web = ""; }

    my @web_core = qw/ 
        aou au perm_ex ex aout 
        mvr ccs ahr aua ac actscecm cbreb acpl 
        cbrebi acpn acp acnn acn bren asc asce 
        clfm cifm citm cam ahtc
        asv asva asvr asvq 
        circ ccs ahn bre mrd
        crcd crmf crrf mbts aoc aus 
        mous mowbus mobts mb ancc cnct cnal
        /;

    my @reports = qw/ perm_ex ex ao aou aout /;


    $output = "var _c = {};\n";

    for my $object (keys %$map) {

        my $hint = $map->{$object}->{hint};

        if($web eq "web_core") {
            next unless (grep { $_ eq $hint } @web_core );
        }

        if($web eq "reports") {
            next unless (grep { $_ eq $hint } @web_core );
        }


        my $short_name = $map->{$object}->{hint};

        my @fields;
        for my $field (keys %{$map->{$object}->{fields}}) {
            my $position = $map->{$object}->{fields}->{$field}->{position};
            $fields[$position] = $field;
        }

        $output .= "_c[\"$short_name\"] = [";
        for my $f (@fields) { 
            next unless $f;
            if( $f ne "isnew" and $f ne "ischanged" and $f ne "isdeleted" ) {
                $output .= "\"$f\","; 
            }
        }
        $output .= "];\n";


    }

    $output .= "var fmclasses = _c;\n";
    return $output;
}

sub org_tree_js {
    # ------------------------------------------------------------
    # turns the orgTree and orgTypes into js files
    # ------------------------------------------------------------
    use OpenSRF::Utils::Cache;

    my $path = shift;
    my $filename = shift;

    my $core = OpenILS::Utils::Cronscript->new({nolockfile => 1});
    $core->bootstrap;

    # must be loaded after the IDL is parsed
    require OpenILS::Utils::CStoreEditor;

    # Get our list of locales
    my $locales = get_locales();

    # Remove the no-locale copy
    my $cache = OpenSRF::Utils::Cache->new;
    $cache->delete_cache("orgtree.");

    foreach my $locale (@$locales) {
        warn "removing OrgTree from the cache for locale " . $locale->code . "...\n";
        $cache->delete_cache("orgtree.".$locale->code);

        # fetch the org_unit's and org_unit_type's
        my $e = OpenILS::Utils::CStoreEditor->new;
        $e->init();
        $e->session->session_locale($locale->code) if ($locale->code);

        my $types = $e->retrieve_all_actor_org_unit_type;
        my $tree = $e->request(
            'open-ils.cstore.direct.actor.org_unit.search.atomic',
            {id => {"!=" => undef}},
            {order_by => {aou => 'name'}, no_i18n => $locale->code ? 0 : 1 }
        );
        my $dir = File::Spec->catdir($path, $locale->code);
        if (!-d $dir) {
            mkdir($dir);
        }
        build_tree_js($types, $tree, File::Spec->catfile($dir, $filename));
    }
}

sub val {
    my $v = shift;
    return 'null' unless defined $v;

    # required for JS code this is checking truthness 
    # without using isTrue() (1/0 vs. t/f)
    return 1 if $v eq 't';
    return 0 if $v eq 'f';

    $v =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%04x',ord($1))/sgoe;

    return "\"$v\"";
}

sub build_tree_js {
    my $types = shift;
    my $tree = shift;
    my $outfile = shift;

    my $pile = "var _l = [";

    my @array;
    for my $o (@$tree) {
        my ($i,$t,$p,$n,$v,$s) = ($o->id,$o->ou_type,$o->parent_ou,val($o->name),val($o->opac_visible),val($o->shortname));
        $p ||= 'null';
        push @array, "[$i,$t,$p,$n,$v,$s]";
    }

    $pile .= join ',', @array;
    $pile .= "]; /* Org Units */ \n";

    $pile .= 'var globalOrgTypes = [';
    for my $t (@$types) {
        my ($u,$v,$d,$i,$n,$o,$p) = (val($t->can_have_users),val($t->can_have_vols),$t->depth,$t->id,val($t->name),val($t->opac_label),$t->parent);
        $p ||= 'null';
        $pile .= "new aout([null,$u,$v,$d,$i,$n,$o,$p]), ";
    }
    $pile =~ s/, $//; # remove trailing comma
    $pile .= ']; /* OU Types */';

    open(OUTFH, '>', $outfile) or die "Could not open $outfile : $!";
    print OUTFH "$pile\n";
    close(OUTFH);
}

sub org_tree_html_options {
    # for each supported locale, turn the orgTree and orgTypes into a static HTML option list

    use Unicode::Normalize;
    use Data::Dumper;

    my $path = shift;
    my $filename = shift; 

    my @types;

    my $core = OpenILS::Utils::Cronscript->new({nolockfile => 1});
    $core->bootstrap;

    my $locales = get_locales();

    foreach my $locale (@$locales) {
        my $ses = OpenSRF::AppSession->create("open-ils.actor");
        $ses->session_locale($locale->code);
        my $tree = $ses->request("open-ils.actor.org_tree.retrieve")->gather(1);

        my $aout = $ses->request("open-ils.actor.org_types.retrieve")->gather(1);
        foreach my $type (@$aout) {
            $types[int($type->id)] = $type;
        }
        my $dir = File::Spec->catdir($path, $locale->code);
        if (!-d $dir) {
            mkdir($dir) or die "Could not create output directory: $dir $!\n";
        }

        my @org_tree_html;
        print_org_tree_html($tree, \@org_tree_html, \@types);
        $ses->disconnect();

        open(OUTFH, '>', File::Spec->catfile($dir, $filename)) or die $!;
        print OUTFH @org_tree_html;
        close OUTFH;
    }

}

sub print_org_tree_html {
    my $node = shift;
    my $org_tree_html = shift;
    my $types = shift;

    return unless ($node->opac_visible =~ /^[y1t]+/i);

    my $depth = $types->[$node->ou_type]->depth;
    my $sname = OpenILS::Application::AppUtils->entityize($node->shortname);
    my $name = OpenILS::Application::AppUtils->entityize($node->name);
    my $kids = $node->children;

    push @$org_tree_html, "<option value='$sname'>" . '&#160;&#160;&#160;'x$depth . "$name</option>\n";
    print_org_tree_html($_, $org_tree_html, $types) for (@$kids);
}

sub org_lasso {
    # Renders a JavaScript version of the org unit search groups
    
    my $core = OpenILS::Utils::Cronscript->new({nolockfile => 1});
    $core->bootstrap;

    # must be loaded after the IDL is parsed
    require OpenILS::Utils::CStoreEditor;

    my $output;

    # fetch the org_unit's and org_unit_type's
    my $e = OpenILS::Utils::CStoreEditor->new;
    $e->init();
    my $lassos = $e->request(
        'open-ils.cstore.direct.actor.org_lasso.search.atomic',
        {id => {"!=" => undef}},
        {order_by => {lasso => 'name'}}
    );

    # We need at least one defined search group; otherwise, just generate an empty array
    if (scalar(@$lassos) > 0) {
       $output =  
            "var _lasso = [\n  new lasso(" .
            join( "),\n  new lasso(", map { OpenSRF::Utils::JSON->perl2JSON( bless($_, 'ARRAY') ) } @$lassos ) .
            ")\n]; /* Org Search Groups (Lassos) */ \n";
    } else {
        $output = <<HERE;
var _lasso = [
]; /* Org Search Groups (Lassos) */
HERE
    }

    return $output;
}

sub locale_html_options {
    # Turns supported locales into a static HTML option list
    my $locales = get_locales();

    my $output = "<select name='locale'>\n";
    foreach my $locale (@$locales) {
        my $code = OpenILS::Application::AppUtils->entityize($locale->code);
        my $name = OpenILS::Application::AppUtils->entityize($locale->name);
        $output .= "  <option value='$code'>$name</option>\n";
    }
    $output .= "</select>\n";

    return $output;
}

sub facet_types {
    # ------------------------------------------------------------
    # turns the facet fields defined on config.metabib_field into JS
    # ------------------------------------------------------------

    my $path = shift;
    my $filename = shift;
    # Get our list of locales
    my $locales = get_locales();

    foreach my $locale (@$locales) {
        warn "removing facet list from the cache for locale " . $locale->code . "...\n";
        my $cache = OpenSRF::Utils::Cache->new;
        $cache->delete_cache("facet_definition.".$locale->code);

        # fetch the org_unit's and org_unit_type's
        my $e = OpenILS::Utils::CStoreEditor->new;
        $e->init();
        $e->session->session_locale($locale->code) if ($locale->code);

        my $types = $e->retrieve_all_actor_org_unit_type;
        my $tree = $e->request(
            'open-ils.cstore.direct.config.metabib_field.search.atomic',
            {   facet_field     => 't' },
            {   no_i18n         => $locale->code ? 0 : 1,
                flesh           => 1,
                flesh_fields    => { cmf => [ 'field_class' ] }
            }
        );
        my $dir = File::Spec->catdir($path, $locale->code);
        if (!-d $dir) {
            mkdir($dir);
        }
        build_facet_type_js($tree, File::Spec->catfile($dir, $filename));
    }
}

sub build_facet_type_js {
    my $tree = shift;
    my $outfile = shift;

    my $pile = "var globalFacets = {";
    my @array;
    for my $o (@$tree) {
        my %hash = (
            id          => $o->id,
            name        => val($o->name),
            label       => val($o->label),
            classname   => val($o->field_class->name),
            classlabel  => val($o->field_class->label)
        );

        $pile .= $hash{id}.':{'.join(',', map { "$_:$hash{$_}" } keys %hash).'},';
    }

    $pile =~ s/,$//; # remove trailing comma
    $pile .= "}; /* Facets */";

    open(OUTFH, '>', $outfile) or die "Could not open $outfile : $!";
    print OUTFH "$pile\n";
    close(OUTFH);
}

sub org_tree_proximity {
    # calculate the proximity of organizations in the organization tree

    my $session = OpenILS::Utils::Cronscript->new({nolockfile => 1})->session('open-ils.storage');
    my $result = $session->request("open-ils.storage.actor.org_unit.refresh_proximity");

    if ($result) {
        print "Successfully updated the organization proximity\n";
    } else {
        print "Failed to update the organization proximity\n";
    }
    $session->disconnect();
}

sub get_locales {
    # Get our list of locales
    my $session = OpenILS::Utils::Cronscript->new({nolockfile => 1})->session("open-ils.cstore");
    my $locales = $session->request(
        "open-ils.cstore.direct.config.i18n_locale.search.atomic",
        {"code" => {"!=" => undef}},
        {"order_by" => {"i18n_l" => "name"}}
    )->gather();
    $session->disconnect();

    return $locales;
}

1;
