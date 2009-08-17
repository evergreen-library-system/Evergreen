# vim:et:ts=4:sw=4:

package OpenILS::Application::Fielder;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use Unicode::Normalize;
use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;

use OpenILS::Utils::CStoreEditor qw/:funcs/;

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

    generate_methods();

}
sub child_init {}

sub fielder_fetch {
    my $self = shift;
    my $client = shift;
    my $obj = shift;

    my $query = $obj->{query};
    my $fields = $obj->{fields};
    my $distinct = $obj->{distinct} ? 1 : 0;

    my $obj_class = $self->{class_hint};
    my $fm_class = $self->{class_name};

    if (!$fields) {
        $fields = [ $fm_class->real_fields ];
    }

    $log->debug( 'Field list: '. OpenSRF::Utils::JSON->perl2JSON( $fields ) );
    $log->debug( 'Query: '. OpenSRF::Utils::JSON->perl2JSON( $query ) );

    return undef unless $fields;
    return undef unless $query;

    $fields = [$fields] if (!ref($fields));


    $log->debug( 'Query Class: '. $obj_class );

    my $res = new_editor()->json_query({
        select  => { $obj_class => $fields },
        from    => $obj_class,
        where   => $query,
        distinct=> $distinct
    });

    for my $value (@$res) {
        $client->respond($value);
    }

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

