package OpenILS::Application::Cat::AuthCommon;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use OpenSRF::AppSession;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';


# ---------------------------------------------------------------------------
# Shared authority mangling code.  Do not publish methods from here.
# ---------------------------------------------------------------------------

# generate a MARC XML document from a MARC XML string
sub marc_xml_to_doc {
    my $xml = shift;
    my $marc_doc = XML::LibXML->new->parse_string($xml);
    $marc_doc->documentElement->setNamespace(MARC_NAMESPACE, 'marc', 1);
    $marc_doc->documentElement->setNamespace(MARC_NAMESPACE);
    return $marc_doc;
}


sub import_authority_record {
    my($class, $e, $marc_xml, $source) = @_;
    
    my $marc_doc = marc_xml_to_doc($marc_xml);
    my $rec = Fieldmapper::authority::record_entry->new;
    $rec->creator($e->requestor->id);
    $rec->editor($e->requestor->id);
    $rec->create_date('now');
    $rec->edit_date('now');
    $rec->marc($U->entityize($marc_doc->documentElement->toString));

    $rec = $e->create_authority_record_entry($rec) or return $e->die_event;

    return $rec;
}


sub overlay_authority_record {
    my($class, $e, $rec_id, $marc_xml, $source) = @_;
    
    my $marc_doc = marc_xml_to_doc($marc_xml);
    my $rec = $e->retrieve_authority_record_entry($rec_id) or return $e->die_event;
    $rec->editor($e->requestor->id);
    $rec->edit_date('now');
    $rec->marc($U->entityize($marc_doc->documentElement->toString));

    $rec = $e->update_authority_record_entry($rec) or return $e->die_event;

    return $rec;
}

1;
