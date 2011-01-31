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

    generate_methods();

}
sub child_init {
    $cache = OpenSRF::Utils::Cache->new('global');
}

sub fielder_fetch {
    my $self = shift;
    my $client = shift;
    my $obj = shift;

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
            $obj_class
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


1;

