-- Outside the transaction because the first change is.
SELECT evergreen.upgrade_deps_block_check('1433', :eg_version);

-- This has to happen outside the transaction that uses it below.
ALTER TYPE config.usr_activity_group ADD VALUE IF NOT EXISTS 'mfa';

BEGIN;


-- Permission seed data 
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 657, 'REMOVE_USER_MFA', oils_i18n_gettext(657,
                    'Remove configured MFA factors for another user', 'ppl', 'description')),

    -- XXX Update the YAOUS update_perm below with the ADMIN_MFA permission id if it changes at commit time!!!
 ( 658, 'ADMIN_MFA', oils_i18n_gettext(658,
                    'Configure Multi-factor Authentication', 'ppl', 'description'))
;

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype, grp, update_perm )
    VALUES (
        'auth.mfa_expire_interval',
        oils_i18n_gettext(
            'auth.mfa_expire_interval',
            'Security: MFA recheck interval',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'auth.mfa_expire_interval',
            'How long before MFA verification is required again, when MFA is required for a user.',
            'coust',
            'description'
        ),
        'interval',
        'sec',
        658 -- XXX Update this with the ADMIN_MFA permission id if that changes at commit time!!!
    );

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'mfa.send_email', 'au', 'User has requested a One-Time MFA code by email'),
( 'mfa.send_sms', 'au', 'User has requested a One-Time MFA code by SMS');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send One-Time Password Email', 'mfa.send_email', 'NOOP_True', 'SendEmail', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- user_data.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Your Library One-Time access code
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

We will never call to ask you for this code, and make sure you do not share it with anyone calling you directly.

Use this code to continue logging in to your Evergreen account:

One-Time code: [% user_data.otp_code %]

Sincerely,
[% user_data.issuer %] - [% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send One-Time Password SMS', 'mfa.send_sms', 'NOOP_True', 'SendSMS', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = user.home_ou -%]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(user_data.carrier,user_data.phone) %]
Subject: One-Time code

Your [% user_data.issuer %] code is: [%user_data.otp_code %] $$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou');

-- New stuff!
CREATE TABLE IF NOT EXISTS config.mfa_factor (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL,
    description TEXT    NOT NULL
);

INSERT INTO config.mfa_factor (name, label, description) VALUES
  ('webauthn', 'Web Authentication API', 'Uses external Public Key credentials to confirm authentication'),
  ('totp', 'Time-based One-Time Password', 'For use with TOTP applications such as Google Authenticator'),
  ('email', 'One-Time Password by Email', 'Uses a dedicated MFA email address to confirm authentication'),
  ('sms', 'One-Time Password by SMS', 'Uses a dedicated MFA phone number and carrier to confirm authentication'),
  ('static', 'Pre-generated backup passwords', 'Confirms authentication via pre-shared One-Time passwords')
;

CREATE TABLE IF NOT EXISTS actor.usr_mfa_exception (
    id      SERIAL  PRIMARY KEY,
    usr     BIGINT  NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    ingress TEXT    -- disregard MFA requirement for specific ehow (ingress types, like 'sip2'), or NULL for all
); 

CREATE TABLE IF NOT EXISTS actor.usr_mfa_factor_map (
    id          SERIAL  PRIMARY KEY,
    usr         BIGINT  NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    factor      TEXT    NOT NULL REFERENCES config.mfa_factor (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    purpose     TEXT    NOT NULL DEFAULT 'mfa', -- mfa || login, for now
    add_time    TIMESTAMPTZ NOT NULL DEFAULT NOW()
); 
CREATE UNIQUE INDEX IF NOT EXISTS factor_purpose_usr_once ON actor.usr_mfa_factor_map (usr, purpose, factor);

CREATE TABLE IF NOT EXISTS permission.group_mfa_factor_map (
    id      SERIAL  PRIMARY KEY,
    grp     BIGINT  NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    factor  TEXT    NOT NULL REFERENCES config.mfa_factor (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE permission.grp_tree
    ADD COLUMN IF NOT EXISTS mfa_allowed BOOL NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS mfa_required BOOL NOT NULL DEFAULT FALSE;

INSERT INTO config.usr_activity_type (id, ewhat, egroup, label)
    VALUES (31, 'confirm', 'mfa', 'Generic MFA authentication confirmation')
    ;--ON CONFLICT DO NOTHING;

ALTER TABLE actor.usr_activity
    ADD COLUMN IF NOT EXISTS event_data TEXT;

DROP FUNCTION actor.insert_usr_activity(INT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION actor.insert_usr_activity(usr INT, ewho TEXT, ewhat TEXT, ehow TEXT, edata TEXT DEFAULT NULL)
 RETURNS SETOF actor.usr_activity
AS $f$
DECLARE
    new_row actor.usr_activity%ROWTYPE;
BEGIN
    SELECT id INTO new_row.etype FROM actor.usr_activity_get_type(ewho, ewhat, ehow);
    IF FOUND THEN
        new_row.usr := usr;
        new_row.event_data := edata;
        INSERT INTO actor.usr_activity (usr, etype, event_data)
            VALUES (usr, new_row.etype, new_row.event_data)
            RETURNING * INTO new_row;
        RETURN NEXT new_row;
    END IF;
END;
$f$ LANGUAGE plpgsql;

----- Support functions for encoding WebAuthn -----
CREATE OR REPLACE FUNCTION evergreen.gen_random_bytes_b64 (INT) RETURNS TEXT AS $f$
    SELECT encode(gen_random_bytes($1),'base64');
$f$ STRICT IMMUTABLE LANGUAGE SQL;


----- Support functions for encoding URLs -----
CREATE OR REPLACE FUNCTION evergreen.encode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return encode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.decode_base32 (TEXT) RETURNS TEXT AS $f$
  use MIME::Base32;
  my $input = shift;
  return decode_base32($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_escape (TEXT) RETURNS TEXT AS $f$
  use URI::Escape;
  my $input = shift;
  return uri_escape_utf8($input);
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION evergreen.uri_unescape (TEXT) RETURNS TEXT AS $f$
  my $input = shift;
  $input =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; # inline the RE, it is 700% faster than URI::Escape::uri_unescape
  return $input;
$f$ STRICT IMMUTABLE LANGUAGE PLPERLU;

----- Flags used to control OTP calculations -----
INSERT INTO config.global_flag (name, label, value, enabled) VALUES
    ('webauthn.mfa.issuer', 'WebAuthn Relying Party name for multi-factor authentication', 'Evergreen WebAuthn', TRUE),
    ('webauthn.mfa.domain', 'WebAuthn Relying Party domain (optional base domain) for multi-factor authentication', '', TRUE),
    ('webauthn.mfa.digits', 'WebAuthn challenge size (bytes)', '16', TRUE),
    ('webauthn.mfa.period', 'WebAuthn challenge timeout (seconds)', '60', TRUE), -- 1 minute for WebAuthn
    ('webauthn.mfa.multicred', 'If Enabled, allows a user to register multiple multi-factor login WebAuthn verification devices', NULL, TRUE),
    ('webauthn.login.issuer', 'WebAuthn Relying Party name for single-factor login', 'Evergreen WebAuthn', TRUE),
    ('webauthn.login.domain', 'WebAuthn Relying Party domain (optional base domain) for single-factor login', '', TRUE),
    ('webauthn.login.digits', 'WebAuthn single-factor login challenge size (bytes)', '16', TRUE),
    ('webauthn.login.period', 'WebAuthn single-factor login challenge timeout (seconds)', '60', TRUE),
    ('webauthn.login.multicred', 'If Enabled, allows a user to register multiple single-factor login WebAuthn verification devices', NULL, TRUE),
    ('totp.mfa.issuer', 'TOTP Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('totp.mfa.digits', 'TOTP code length (Google Authenticator supports only 6)', '6', TRUE),
    ('totp.mfa.algorithm', 'TOTP code generation algorithm (Google Authenticator supports only SHA1)', 'SHA1', TRUE),
    ('totp.mfa.period', 'TOTP code validity period in seconds  (Google Authenticator supports only 30)', '30', TRUE), -- 30 seconds for totp, but remember, fuzziness!
    ('totp.login.issuer', 'TOTP Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('totp.login.digits', 'TOTP code length (Google Authenticator supports only 6)', '6', TRUE),
    ('totp.login.algorithm', 'TOTP code generation algorithm (Google Authenticator supports only SHA1)', 'SHA1', TRUE),
    ('totp.login.period', 'TOTP code validity period in seconds  (Google Authenticator supports only 30)', '30', TRUE),
    ('email.mfa.issuer', 'Email Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('email.mfa.digits', 'Email One-Time code length for multi-factor authentication; max: 8', '6', TRUE),
    ('email.mfa.algorithm', 'Email One-Time code algorithm for multi-factor authentication: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('email.mfa.period', 'Email One-Time validity period for multi-factor authentication in seconds (default: 30 minutes)', '1800', TRUE), -- 30 minutes for email
    ('email.login.issuer', 'Email Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('email.login.digits', 'Email One-Time code length for single-factor login; max: 8', '6', TRUE),
    ('email.login.algorithm', 'Email One-Time code algorithm for single-factor login: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('email.login.period', 'Email One-Time validity period for single-factor login in seconds (default: 30 minutes)', '1800', TRUE),
    ('sms.mfa.issuer', 'SMS Issuer string for multi-factor authentication', 'Evergreen-MFA', TRUE),
    ('sms.mfa.digits', 'SMS One-Time code length for multi-factor authentication; max: 8', '6', TRUE),
    ('sms.mfa.algorithm', 'SMS One-Time code algorithm for multi-factor authentication: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('sms.mfa.period', 'SMS One-Time validity period for multi-factor authentication in seconds (default: 15 minutes)', '900', TRUE), -- 15 minutes for SMS
    ('sms.login.issuer', 'SMS Issuer string for single-factor login', 'Evergreen-Login', TRUE),
    ('sms.login.digits', 'SMS One-Time code length for single-factor login; max: 8', '6', TRUE),
    ('sms.login.algorithm', 'SMS One-Time code algorithm for single-factor login: SHA1, SHA256, SHA512', 'SHA1', TRUE),
    ('sms.login.period', 'SMS One-Time validity period for single-factor login in seconds (default: 15 minutes)', '900', TRUE)
;

----- Password types to support secondary factors -----
INSERT INTO actor.passwd_type (code, name) VALUES
    ('email-mfa', 'Time-base One-Time Password Secret for multi-factor authentication via EMail'),
    ('email-login', 'Time-base One-Time Password Secret for single-factor login via EMail'),
    ('sms-mfa', 'Time-base One-Time Password Secret for multi-factor authentication via SMS'),
    ('sms-login', 'Time-base One-Time Password Secret for single-factor login via SMS'),
    ('totp-mfa', 'Time-base One-Time Password Secret for multi-factor authentication'),
    ('totp-login', 'Time-base One-Time Password Secret for single-factor login'),
    ('webauthn-mfa', 'WebAuthn data for multi-factor authentication'),
    ('webauthn-login', 'WebAuthn data for single-factor login')
;

----- OTP URI destroyer: Removes the TOTP password entry if the user knows the secret NOW -----
CREATE OR REPLACE FUNCTION actor.remove_otpauth_uri(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    proof TEXT,
    fuzziness INT DEFAULT 1
) RETURNS BOOL AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $usr_id = shift;
my $otype = shift;
my $purpose = shift;
my $proof = shift;
my $fuzziness_width = shift // 1;

if ($otype eq 'webauthn') { # nothing to prove
    my $waq = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
    my $res = spi_exec_prepared($waq, $usr_id, $otype, $purpose);
    spi_freeplan($waq);
    return 1;
}

# Normalize the proof value
$proof =~ s/\D//g;
return 0 unless $proof; # all-0s is not valid

my $q = spi_prepare('SELECT actor.otpauth_uri($1, $2, $3) AS uri;', 'INTEGER', 'TEXT', 'TEXT');
my $otp_uri = spi_exec_prepared($q, {limit => 1}, $usr_id, $otype, $purpose)->{rows}[0]{uri};
spi_freeplan($q);

return 0 unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    my $otp_code = Pass::OTP::otp(%otp_config);
    if ($otp_code eq $proof) {
        $q = spi_prepare('DELETE FROM actor.passwd WHERE usr = $1 AND passwd_type = $2 || $$-$$ || $3;', 'INTEGER', 'TEXT', 'TEXT');
        my $res = spi_exec_prepared($q, $usr_id, $otype, $purpose);
        spi_freeplan($q);
        return 1;
    }
}

return 0;
$f$ LANGUAGE PLPERLU;

----- OTP proof generator: find the TOTP code, optionally with fuzziness -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    otp_uri TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$

use Pass::OTP;
use Pass::OTP::URI;

my $otp_uri = shift;
my $fuzziness_width = shift // 0;

return undef unless $otp_uri;

my %otp_config = Pass::OTP::URI::parse($otp_uri);
return undef unless $otp_config{type};

for my $fuzziness ( -$fuzziness_width .. $fuzziness_width ) {
    $otp_config{'start-time'} = $otp_config{period} * $fuzziness;
    return_next({period_step => $fuzziness, proof => Pass::OTP::otp(%otp_config)});
}

return undef;

$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION actor.otpauth_uri_get_proof(
    usr_id INT,
    otype TEXT,
    purpose TEXT,
    fuzziness INT DEFAULT 0
) RETURNS TABLE ( period_step INT, proof TEXT) AS $f$
BEGIN
    RETURN QUERY
      SELECT * FROM actor.otpauth_uri_get_proof( actor.otpauth_uri($1, $2, $3), $4 );
    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

----- TOTP URI generator: Saves the secret on the first call for each user ID -----
CREATE OR REPLACE FUNCTION actor.otpauth_uri(
    usr_id INT,
    otype TEXT DEFAULT 'totp',
    purpose TEXT DEFAULT 'mfa',
    additional_params HSTORE DEFAULT ''::HSTORE -- this can be used to pass a start-time parameter to offset totp calc
) RETURNS TEXT AS $f$
DECLARE
    issuer      TEXT := 'Evergreen';
    algorithm   TEXT := 'SHA1';
    digits      TEXT := '6';
    period      TEXT := '30';
    counter     TEXT := '0';
    otp_secret  TEXT;
    otp_params  HSTORE;
    uri         TEXT;
    param_name  TEXT;
    uri_otype  TEXT;
BEGIN

    IF additional_params IS NULL THEN additional_params = ''::HSTORE; END IF;

    -- we're going to be a bit strict here, for now
    IF otype NOT IN ('webauthn','email','sms','totp','hotp') THEN RETURN NULL; END IF;
    IF purpose NOT IN ('mfa','login') THEN RETURN NULL; END IF;

    uri_otype := otype;
    IF otype NOT IN ('totp','hotp') THEN
        uri_otype := 'totp'; -- others are time-based, but with different settings
    END IF;

    -- protect "our" keys
    additional_params := additional_params - ARRAY['issuer','algorithm','digits','period'];

    SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM actor.passwd WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;

    IF NOT FOUND THEN

        issuer := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.issuer' AND enabled),
            issuer
        );

        algorithm := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.algorithm' AND enabled),
            algorithm
        );

        digits := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.digits' AND enabled),
            digits
        );

        period := COALESCE(
            (SELECT value FROM config.internal_flag WHERE name = otype||'.'||purpose||'.period' AND enabled),
            period
        );

        otp_params := HSTORE('counter', counter)
                      || HSTORE('issuer', issuer)
                      || HSTORE('algorithm', UPPER(algorithm))
                      || HSTORE('digits', digits)
                      || HSTORE('period', period);

        IF additional_params ? 'counter' THEN
            otp_params := otp_params - 'counter';
        END IF;

        otp_params := additional_params || otp_params;

        WITH new_secret AS (
            INSERT INTO actor.passwd (usr, salt, passwd, passwd_type)
                VALUES (usr_id, otp_params::TEXT, gen_random_uuid()::TEXT, otype || '-' || purpose)
                RETURNING passwd, salt
        ) SELECT passwd, salt::HSTORE INTO otp_secret, otp_params FROM new_secret;

    ELSE
        otp_params := otp_params - akeys(additional_params); -- remove what we're receiving
        otp_params := additional_params || otp_params;
        IF additional_params != ''::HSTORE THEN -- new additional params were passed, let's save the salt again
            UPDATE actor.passwd SET salt = otp_params::TEXT WHERE usr = usr_id AND passwd_type = otype || '-' || purpose;
        END IF;
    END IF;


    uri :=  'otpauth://' || uri_otype || '/' || evergreen.uri_escape(otp_params -> 'issuer') || ':' || usr_id::TEXT
            ||'?secret='    || evergreen.encode_base32(otp_secret);

    FOREACH param_name IN ARRAY akeys(otp_params) LOOP
        uri := uri || '&' || evergreen.uri_escape(param_name) || '=' || evergreen.uri_escape(otp_params -> param_name);
    END LOOP;

    RETURN uri;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;

