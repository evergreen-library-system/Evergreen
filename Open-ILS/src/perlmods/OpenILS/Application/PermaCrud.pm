package OpenILS::Application::PermaCrud;
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
}
sub child_init {}

sub CRUD_action_object_permcheck {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $obj = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->event unless $e->checkauth;

    unless ($obj->json_hint eq $self->{class_hint}) {
        throw OpenSRF::DomainObject::oilsException->new(
            statusCode => 500,
            status => "Class missmatch: $self->{class_hint} method called with " . $obj->json_hint,
        );
    }

    my $action = $self->api_name =~ s/^open-ils\.admin\.([^\.])\..+$/$1/o;
    my $o_type = $obj->cdbi =~ s/::/./go;

    my ($class_node) = $xpc->findnodes( "//idl:class[\@id='$self->{class_hint}']", $idl->documentElement );
    my ($action_node) = $xpc->findnodes( "perm:permacrud/perm:actions/perm:$action", $class_node );

    my $perm_field_value = $aciton_node->getAttribute('permission');

    if (defined($perm_field_value)) 
        my @perms = split '|', $aciton_node->getAttribute('permission');

        my @context_ous;
        if ($aciton_node->getAttribute('global_required')) {
            push @context_ous, $e->search_actor_org_unit( { parent_ou => undef } )->[0]->id;

        } else {
            my $context_field_value = $aciton_node->getAttribute('context_field');

            if (defined($context_field_value)) {
                push @context_ous, $obj->$_ for ( split '|', $context_field_value );
            } else {  
                for my $context_node ( $xpc->findnodes( "perm:context", $action_node ) ) {
                    my $context_field = $context_node->getAttribute('field');
                    my $link_field = $context_node->getAttribute('link');

                    my ($link_node) = $xpc->findnodes( "idl:links/idl:link[\@field='$link_field']", $class_node );
                    my $link_class_hint = $link_node->getAttribute('class');
                    my $remote_field = $link_node->getAttribute('key');

                    my ($remote_class_node) = $xpc->findnodes( "//idl:class[\@id='$self->{class_hint}']", $idl->documentElement );
                    my $search_method = 'search_' . $xpc->findvalue( '@oils_obj:fieldmapper', $remote_class_node );
                    $search_method =~ s/::/_/go;

                    for my $remote_object ( @{$e->$search_method( { $key => $obj->$link_field } )} ) {
                        push @context_ous, $remote_object->$context_field;
                    }
                }
            }
        }

        my ($pok, $cok) = (0, 0);
        for my $perm (@perms) {
            for my $c_ou (@context_ous) {
                if ($e->allowed($perm => $c_ou => $obj)) {
                    $cok++;
                    last;
                }
            }
            $pok++ if ($cok);
            $cok = 0;
        }

        unless (@perms == $pok) {
            throw OpenSRF::DomainObject::oilsException->new(
                statusCode => 500,
                status => "Perm failure -- action: $action, object type: $self->{json_hint}",
            );
        }
    }
}

for my $class_node ( $xpc->findnodes( "perm:permacrud/perm:actions/perm:$action", $class_node ) ) {
    my $hint = $class_node->getAttribute('id');

    for my $action_node ( $xpc->findnodes( "perm:permacrud/perm:actions/perm:*", $class_node ) ) {
        my $method = $action_node->localname =~ s/^.+:(.+)$/$1/o;

        __PACKAGE__->register_method(
            method      => 'CRUD_action_object_permcheck',
            api_name    => 'open-ils.permacrud.' . $method . '.' . $hint,
            class_hint  => $hint,
        );

    }
}
    


1;

