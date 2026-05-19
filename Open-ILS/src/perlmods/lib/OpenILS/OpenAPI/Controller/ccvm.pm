package OpenILS::OpenAPI::Controller::ccvm;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;

our $VERSION = 1;

sub retrieve_ccvm {
    my ($c, $ccvm) = @_;
    return new_editor()->retrieve_config_coded_value_map($ccvm);
}

sub ccvm_by_ctype {
    my ($c, $ctype) = @_;
    return new_editor()->search_config_coded_value_map({ctype=>$ctype});
}

1;
