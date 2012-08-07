BEGIN;

CREATE OR REPLACE FUNCTION url_verify.parse_url (url_in TEXT) RETURNS url_verify.url AS $$

use Rose::URI;

my $url_in = shift;
my $url = Rose::URI->new($url_in);

my %parts = map { $_ => $url->$_ } qw/scheme username password host port path query fragment/;

$parts{full_url} = $url_in;
($parts{domain} = $parts{host}) =~ s/^[^.]+\.//;
($parts{tld} = $parts{domain}) =~ s/(?:[^.]+\.)+//;
($parts{page} = $parts{path}) =~ s#(?:[^/]*/)+##;

return \%parts;

$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION url_verify.ingest_url () RETURNS TRIGGER AS $$
DECLARE
    tmp_row url_verify.url%ROWTYPE;
BEGIN
    SELECT * INTO tmp_row FROM url_verify.parse_url(NEW.full_url);

    NEW.scheme          := tmp_row.scheme;
    NEW.username        := tmp_row.username;
    NEW.password        := tmp_row.password;
    NEW.host            := tmp_row.host;
    NEW.domain          := tmp_row.domain;
    NEW.tld             := tmp_row.tld;
    NEW.port            := tmp_row.port;
    NEW.path            := tmp_row.path;
    NEW.page            := tmp_row.page;
    NEW.query           := tmp_row.query;
    NEW.fragment        := tmp_row.fragment;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER ingest_url_tgr
    BEFORE INSERT ON url_verify.url
    FOR EACH ROW EXECUTE PROCEDURE url_verify.ingest_url(); 


COMMIT;

