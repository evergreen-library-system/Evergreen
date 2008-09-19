package OpenILS::Application::Cat::Authority;
use strict; use warnings;
use base qw/OpenILS::Application/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Cat::AuthCommon;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';
my $MARC_NAMESPACE = 'http://www.loc.gov/MARC21/slim';


# generate a MARC XML document from a MARC XML string
sub marc_xml_to_doc {
	my $xml = shift;
	my $marc_doc = XML::LibXML->new->parse_string($xml);
	$marc_doc->documentElement->setNamespace($MARC_NAMESPACE, 'marc', 1);
	$marc_doc->documentElement->setNamespace($MARC_NAMESPACE);
	return $marc_doc;
}


__PACKAGE__->register_method(
	method	=> 'import_authority_record',
	api_name	=> 'open-ils.cat.authority.record.import',
);

sub import_authority_record {
    my($self, $conn, $auth, $marc_xml, $source) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('CREATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Utils::Cat::AuthCommon->import_authority_record($marc_xml, $source);
    $e->commit unless $U->event_code($rec);
    return $rec;
}


__PACKAGE__->register_method(
	method	=> 'overlay_authority_record',
	api_name	=> 'open-ils.cat.authority.record.overlay',
);

sub overlay_authority_record {
    my($self, $conn, $auth, $rec_id, $marc_xml, $source) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('UPDATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Utils::Cat::AuthCommon->overlay_authority_record($rec_id, $marc_xml, $source);
    $e->commit unless $U->event_code($rec);
    return $rec;

}

__PACKAGE__->register_method(
	method	=> 'retrieve_authority_record',
	api_name	=> 'open-ils.cat.authority.record.retrieve',
    signature => {
        desc => q/Retrieve an authority record entry/,
        params => [
            {desc => q/hash of options.  Options include "clear_marc" which clears
                the MARC xml from the record before it is returned/}
        ]
    }
);
sub retrieve_authority_record {
    my($self, $conn, $auth, $rec_id, $options) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
    my $rec = $e->retrieve_authority_record($rec_id) or return $e->event;
    $rec->clear_marc if $$options{clear_marc};
    return $rec;
}

__PACKAGE__->register_method(
	method	=> 'batch_retrieve_authority_record',
	api_name	=> 'open-ils.cat.authority.record.batch.retrieve',
    stream => 1,
    signature => {
        desc => q/Retrieve a set of authority record entry objects/,
        params => [
            {desc => q/hash of options.  Options include "clear_marc" which clears
                the MARC xml from the record before it is returned/}
        ]
    }
);
sub batch_retrieve_authority_record {
    my($self, $conn, $auth, $rec_id_list, $options) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
    for my $rec_id (@$rec_id_list) {
        my $rec = $e->retrieve_authority_record($rec_id) or return $e->event;
        $rec->clear_marc if $$options{clear_marc};
        $conn->respond($rec);
    }
    return undef;
}

1;
