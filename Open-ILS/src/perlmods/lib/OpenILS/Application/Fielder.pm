# vim:et:ts=4:sw=4:

package OpenILS::Application::Fielder;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use Unicode::Normalize;
use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;

use OpenILS::Utils::CStoreEditor qw/:funcs/;

use Digest::MD5 qw(md5_hex);

use XML::LibXML;
use XML::LibXML::XPathContext;
use XML::LibXSLT;

use OpenILS::Application::Flattener;
use Data::Dumper;

$Data::Dumper::Indent = 0;

our %namespace_map = (
    oils_persist=> {ns => 'http://open-ils.org/spec/opensrf/IDL/persistence/v1'},
    oils_obj    => {ns => 'http://open-ils.org/spec/opensrf/IDL/objects/v1'},
    idl         => {ns => 'http://opensrf.org/spec/IDL/base/v1'},
    reporter    => {ns => 'http://open-ils.org/spec/opensrf/IDL/reporter/v1'},
    perm        => {ns => 'http://open-ils.org/spec/opensrf/IDL/permacrud/v1'},
);


my $log = 'OpenSRF::Utils::Logger';

my $cache;
my $cache_timeout;
my $default_locale;
my $parser = XML::LibXML->new();
my $xslt = XML::LibXSLT->new();

my $xpc = XML::LibXML::XPathContext->new();
$xpc->registerNs($_, $namespace_map{$_}{ns}) for ( keys %namespace_map );

my $idl;

sub initialize {

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $idl_file = $conf->config_value( 'IDL' );

    $idl = $parser->parse_file( $idl_file );

    $log->debug( 'IDL XML file loaded' );

    $cache_timeout = $conf->config_value(
            "apps", "open-ils.fielder", "app_settings", "cache_timeout" ) || 300;

    $default_locale = $conf->config_value("default", "default_locale") || 'en-US';

    generate_methods();

}
sub child_init {
    $cache = OpenSRF::Utils::Cache->new('global');
}

sub fielder_fetch {
    my $self = shift;
    my $client = shift;
    my $obj = shift;

    my $locale = $self->session->session_locale || $default_locale;
    my $query = $obj->{query};
    my $nocache = $obj->{cache} ? 0 : 1;
    my $fields = $obj->{fields};
    my $distinct = $obj->{distinct} ? 1 : 0;

    return undef unless $query;

    my $obj_class = $self->{class_hint};
    my $fm_class = $self->{class_name};

    if (!$fields) {
        $fields = [ $fm_class->real_fields ];
    }

    $fields = [$fields] if (!ref($fields));

    my $qstring = OpenSRF::Utils::JSON->perl2JSON( $query );
    my $fstring = OpenSRF::Utils::JSON->perl2JSON( [ sort { $a cmp $b } @$fields ] );

    $log->debug( 'Query Class: '. $obj_class );
    $log->debug( 'Field list: '. $fstring );
    $log->debug( 'Query: '. $qstring );

    my ($key,$res);
    unless ($nocache) {
        $key = 'open-ils.fielder_' . md5_hex(
            $self->api_name . 
            $qstring .
            $fstring .
            $distinct .
            $obj_class .
            $locale
        );

        $res = $cache->get_cache( $key );

        if ($res) {
            $client->respond($_) for (@$res);
            return undef;
        }
    }

    $res = new_editor()->json_query({
        select  => { $obj_class => $fields },
        from    => $obj_class,
        where   => $query,
        distinct=> $distinct
    });

    for my $value (@$res) {
        $client->respond($value);
    }

    $client->respond_complete();

    $cache->put_cache( $key => $res => $cache_timeout ) unless ($nocache);
    return undef;
}

sub generate_methods {
    try {
        for my $class_node ( $xpc->findnodes( '//idl:class[@oils_persist:field_safe="true"]', $idl->documentElement ) ) {
            my $hint = $class_node->getAttribute('id');
            my $fm = $class_node->getAttributeNS('http://open-ils.org/spec/opensrf/IDL/objects/v1','fieldmapper');
            $log->debug("Fielder class_node $hint");
        
            __PACKAGE__->register_method(
                method          => 'fielder_fetch',
                api_name        => 'open-ils.fielder.' . $hint,
                class_hint      => $hint,
                class_name      => "Fieldmapper::$fm",
                stream          => 1,
                argc            => 1
            );
        }
    } catch Error with {
        my $e = shift;
        $log->error("error generating Fielder methods: $e");
    };
}

sub register_map {
    my ($self, $conn, $auth, $hint, $map) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    $key = 'flat_search_' . md5_hex(
        $hint .
        OpenSRF::Utils::JSON->perl2JSON( $map )
    );

    $cache->put_cache( $key => { hint => $hint, map => $map } => $cache_timeout );
}

__PACKAGE__->register_method(
    method          => 'register_map',
    api_name        => 'open-ils.fielder.flattened_search.prepare',
    argc            => 3,
    signature       => {
        params => [
            {name => "auth", type => "string", desc => "auth token"},
            {name => "hint", type => "string",
                desc => "fieldmapper class hint of core object"},
            {name => "map", type => "object", desc => q{
                path-field mapping structure. See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} }
        ],
        return => {
            desc => q{
                A key used to reference a prepared flattened search on subsequent
                calls to open-ils.fielder.flattened_search.execute},
            type => "string"
        }
    }
);

sub execute_registered_flattened_search {
    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $key  = shift;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $e->disconnect;

    my $blob = $cache->get_cache( $key ) or
        return new OpenILS::Event('CACHE_MISS');

    flattened_search( $self, $conn, $auth, $blob->{hint}, $blob->{map}, @_ )
        if (ref($blob) and $blob->{hint} and $blob->{map});
}

__PACKAGE__->register_method(
    method          => 'execute_registered_flattened_search',
    api_name        => 'open-ils.fielder.flattened_search.execute',
    stream          => 1,
    argc            => 5,
    signature       => {
        params => [
            {name => "auth", type => "string", desc => "auth token"},
            {name => "key", type => "string",
                desc => "Key for a registered map provided by open-ils.fielder.flattened_search.prepare"},
            {name => "where", type => "object", desc => q{
                simplified query clause (like the 'where' clause of a
                json_query, but different). See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} },
            {name => "slo", type => "object", desc => q{
                simplified sort/limit/offset object. See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} }
        ],
        return => {
            desc => q{
                A stream of objects flattened to your specifications. See
                documentation under docs/TechRef/Flattener in the Evergreen
                source tree.},
            type => "object"
        }
    }
);

sub flattened_search {
    my ($self, $conn, $auth, $hint, $map, $where, $slo) = @_;

    # All but the last argument really are necessary.
    $slo ||= {};

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    # Process the map to normalize it, and to get all our joins and fleshing
    # structure into the jffolo.
    my $jffolo;
    ($map, $jffolo) =
        OpenILS::Application::Flattener::process_map($hint, $map);

    # Process the suppied where clause, using our map, to make the
    # filter.
    my $filter = OpenILS::Application::Flattener::prepare_filter($map, $where);

    # Process the supplied sort/limit/offset clause and use it to finish the
    # jffolo.
    $jffolo = OpenILS::Application::Flattener::finish_jffolo(
        $hint, $map, $jffolo, $slo
    );

    # Reach out and touch pcrud (could be cstore, if we wanted to offer
    # this as a private service).
    my $pcrud = create OpenSRF::AppSession("open-ils.pcrud");
    my $req = $pcrud->request(
        "open-ils.pcrud.search.$hint", $auth, $filter, $jffolo
    );

    # Stream back flattened results.
    while (my $resp = $req->recv(timeout => 60)) {
        $conn->respond(
            OpenILS::Application::Flattener::process_result(
                $map, $resp->content
            )
        );
    }

    # Clean up.
    $pcrud->kill_me;

    return;
}

__PACKAGE__->register_method(
    method          => 'flattened_search',
    api_name        => 'open-ils.fielder.flattened_search',
    stream          => 1,
    argc            => 5,
    signature       => {
        params => [
            {name => "auth", type => "string", desc => "auth token"},
            {name => "hint", type => "string",
                desc => "fieldmapper class hint of core object"},
            {name => "map", type => "object", desc => q{
                path-field mapping structure. See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} },
            {name => "where", type => "object", desc => q{
                simplified query clause (like the 'where' clause of a
                json_query, but different). See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} },
            {name => "slo", type => "object", desc => q{
                simplified sort/limit/offset object. See documentation under
                docs/TechRef/Flattener in the Evergreen source tree.} }
        ],
        return => {
            desc => q{
                A stream of objects flattened to your specifications. See
                documentation under docs/TechRef/Flattener in the Evergreen
                source tree.},
            type => "object"
        }
    }
);

1;

