
-- Re-create these as plperlu instead of plperl
CREATE OR REPLACE FUNCTION auditor.set_audit_info(INT, INT) RETURNS VOID AS $$
    $_SHARED{"eg_audit_user"} = $_[0];
    $_SHARED{"eg_audit_ws"} = $_[1];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION auditor.get_audit_info() RETURNS TABLE (eg_user INT, eg_ws INT) AS $$
    return [{eg_user => $_SHARED{"eg_audit_user"}, eg_ws => $_SHARED{"eg_audit_ws"}}];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION auditor.clear_audit_info() RETURNS VOID AS $$
    delete($_SHARED{"eg_audit_user"});
    delete($_SHARED{"eg_audit_ws"});
$$ LANGUAGE plperlu;

DROP LANGUAGE plperl;
