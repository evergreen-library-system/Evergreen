--Upgrade Script for 3.4.3 to 3.5.0
\set eg_version '''3.5.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.5.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1194', :eg_version);

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;


    # Replace unicode curly single and double quote-like characters with straight
    $str =~ s/[\x{2018}\x{2019}\x{201B}\x{FF07}\x{201A}]/\x{0027}/g;
    $str =~ s/[\x{201C}\x{201D}\x{201F}\x{FF0C}\x{201E}\x{2E42}]/\x{0022}/g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.search_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    # Replace unicode curly single and double quote-like characters with straight
    $str =~ s/[\x{2018}\x{2019}\x{201B}\x{FF07}\x{201A}]/\x{0027}/g;
    $str =~ s/[\x{201C}\x{201D}\x{201F}\x{FF0C}\x{201E}\x{2E42}]/\x{0022}/g;


    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}][/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;


SELECT evergreen.upgrade_deps_block_check('1196', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.patron.custom_css', 'opac',
    oils_i18n_gettext('opac.patron.custom_css',
        'Custom CSS for the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.patron.custom_css',
        'Custom CSS for the OPAC',
        'coust', 'description'),
    'string', NULL);


SELECT evergreen.upgrade_deps_block_check('1198', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.results.count', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.catalog.results.count',
        'Catalog Results Page Size',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1199', :eg_version);

INSERT INTO action_trigger.hook
(key,core_type,description,passive)
VALUES
('stgu.created','stgu','Patron requested a card using self registration','t');


INSERT INTO action_trigger.event_definition(active,owner,name,hook,validator,reactor,delay,max_delay,delay_field,group_field,template,retention_interval)
SELECT 'f',1,'Patron Registered for a card stgu.created','stgu.created','NOOP_True','SendEmail','00:01:00'::interval,'1 day'::interval,'row_date','home_ou',
$$[%- USE date -%]
[%- lib = target.0.home_ou -%]
To: [% lib.name %] <[% params.recipient_email || helpers.get_org_setting(target.0.home_ou.id, 'org.bounced_emails') || lib.email || default_sender %]>
From: [% lib.name %] <[%  helpers.get_org_setting(target.0.home_ou.id, 'org.bounced_emails') || lib.email || params.recipient_email || default_sender %]>
Date: [% date.format(format => '%a, %d %b %Y %H:%M:%S %Z') %]
Subject: Patron card requested
Auto-Submitted: auto-generated


Dear Staff Admin,

There are some pending patrons waiting for your attention.

[% FOR patron IN target %]
    [% patron.first_given_name %]

[% END %]

These requests can be tended via the staff interface. Located "Circulation" -> "Pending Patrons"


$$,
'1 year'::interval

WHERE NOT EXISTS (SELECT 1 FROM action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created');

INSERT INTO action_trigger.environment (event_def,path)
SELECT id,'home_ou' from action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created'
AND NOT EXISTS (SELECT 1 FROM action_trigger.environment WHERE
event_def=(SELECT id FROM action_trigger.event_definition WHERE name='Patron Registered for a card stgu.created' AND owner=1 LIMIT 1)
AND path='home_ou');



SELECT evergreen.upgrade_deps_block_check('1200', :eg_version);

CREATE TABLE money.debit_card_payment () INHERITS (money.bnm_desk_payment);
ALTER TABLE money.debit_card_payment ADD PRIMARY KEY (id);
CREATE INDEX money_debit_card_payment_xact_idx ON money.debit_card_payment (xact);
CREATE INDEX money_debit_card_id_idx ON money.debit_card_payment (id);
CREATE INDEX money_debit_card_payment_ts_idx ON money.debit_card_payment (payment_ts);
CREATE INDEX money_debit_card_payment_accepting_usr_idx ON money.debit_card_payment (accepting_usr);
CREATE INDEX money_debit_card_payment_cash_drawer_idx ON money.debit_card_payment (cash_drawer);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('debit_card_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('debit_card_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('debit_card_payment');
 
CREATE OR REPLACE VIEW money.non_drawer_payment_view AS
       SELECT  p.*, c.relname AS payment_type
         FROM  money.bnm_payment p         
                       JOIN pg_class c ON p.tableoid = c.oid
         WHERE c.relname NOT IN ('cash_payment','check_payment','credit_card_payment','debit_card_payment');

UPDATE action_trigger.event_definition 
    SET template = $$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Payment Receipt
Auto-Submitted: auto-generated

[% date.format -%]
[%- SET xact_mp_hash = {} -%]
[%- FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions -%]
    [%- SET xact_id = mp.xact.id -%]
    [%- IF ! xact_mp_hash.defined( xact_id ) -%][%- xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } -%][%- END -%]
    [%- xact_mp_hash.$xact_id.payments.push(mp) -%]
[%- END -%]
[%- FOR xact_id IN xact_mp_hash.keys.sort -%]
    [%- SET xact = xact_mp_hash.$xact_id.xact %]
Transaction ID: [% xact_id %]
    [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
    [% ELSE %]Miscellaneous
    [% END %]
    Line item billings:
        [%- SET mb_type_hash = {} -%]
        [%- FOR mb IN xact.billings %][%# Group billings by their btype -%]
            [%- IF mb.voided == 'f' -%]
                [%- SET mb_type = mb.btype.id -%]
                [%- IF ! mb_type_hash.defined( mb_type ) -%][%- mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } -%][%- END -%]
                [%- IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) -%][%- mb_type_hash.$mb_type.first_ts = mb.billing_ts -%][%- END -%]
                [%- mb_type_hash.$mb_type.last_ts = mb.billing_ts -%]
                [%- mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount -%]
                [%- mb_type_hash.$mb_type.billings.push( mb ) -%]
            [%- END -%]
        [%- END -%]
        [%- FOR mb_type IN mb_type_hash.keys.sort -%]
            [%- IF mb_type == 1 %][%-# Consolidated view of overdue billings -%]
                $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                    on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
            [%- ELSE -%][%# all other billings show individually %]
                [% FOR mb IN mb_type_hash.$mb_type.billings %]
                    $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                [% END %]
            [% END %]
        [% END %]
    Line item payments:
        [% FOR mp IN xact_mp_hash.$xact_id.payments %]
            Payment ID: [% mp.id %]
                Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                    [% CASE "cash_payment" %]cash
                    [% CASE "check_payment" %]check
                    [% CASE "credit_card_payment" %]credit card
                    [%- IF mp.credit_card_payment.cc_number %] ([% mp.credit_card_payment.cc_number %])[% END %]
                    [% CASE "debit_card_payment" %]debit card
                    [% CASE "credit_payment" %]credit
                    [% CASE "forgive_payment" %]forgiveness
                    [% CASE "goods_payment" %]goods
                    [% CASE "work_payment" %]work
                [%- END %] on [% mp.payment_ts %] [% mp.note %]
        [% END %]
[% END %]
$$
WHERE id = 29 AND template = $$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Payment Receipt
Auto-Submitted: auto-generated

[% date.format -%]
[%- SET xact_mp_hash = {} -%]
[%- FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions -%]
    [%- SET xact_id = mp.xact.id -%]
    [%- IF ! xact_mp_hash.defined( xact_id ) -%][%- xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } -%][%- END -%]
    [%- xact_mp_hash.$xact_id.payments.push(mp) -%]
[%- END -%]
[%- FOR xact_id IN xact_mp_hash.keys.sort -%]
    [%- SET xact = xact_mp_hash.$xact_id.xact %]
Transaction ID: [% xact_id %]
    [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
    [% ELSE %]Miscellaneous
    [% END %]
    Line item billings:
        [%- SET mb_type_hash = {} -%]
        [%- FOR mb IN xact.billings %][%# Group billings by their btype -%]
            [%- IF mb.voided == 'f' -%]
                [%- SET mb_type = mb.btype.id -%]
                [%- IF ! mb_type_hash.defined( mb_type ) -%][%- mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } -%][%- END -%]
                [%- IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) -%][%- mb_type_hash.$mb_type.first_ts = mb.billing_ts -%][%- END -%]
                [%- mb_type_hash.$mb_type.last_ts = mb.billing_ts -%]
                [%- mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount -%]
                [%- mb_type_hash.$mb_type.billings.push( mb ) -%]
            [%- END -%]
        [%- END -%]
        [%- FOR mb_type IN mb_type_hash.keys.sort -%]
            [%- IF mb_type == 1 %][%-# Consolidated view of overdue billings -%]
                $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                    on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
            [%- ELSE -%][%# all other billings show individually %]
                [% FOR mb IN mb_type_hash.$mb_type.billings %]
                    $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                [% END %]
            [% END %]
        [% END %]
    Line item payments:
        [% FOR mp IN xact_mp_hash.$xact_id.payments %]
            Payment ID: [% mp.id %]
                Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                    [% CASE "cash_payment" %]cash
                    [% CASE "check_payment" %]check
                    [% CASE "credit_card_payment" %]credit card
                    [%- IF mp.credit_card_payment.cc_number %] ([% mp.credit_card_payment.cc_number %])[% END %]
                    [% CASE "credit_payment" %]credit
                    [% CASE "forgive_payment" %]forgiveness
                    [% CASE "goods_payment" %]goods
                    [% CASE "work_payment" %]work
                [%- END %] on [% mp.payment_ts %] [% mp.note %]
        [% END %]
[% END %]
$$;


SELECT evergreen.upgrade_deps_block_check('1201', :eg_version); -- rhamby/jboyer

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 620, 'UPDATE_ORG_UNIT_SETTING.opac.patron.custom_css', oils_i18n_gettext(620,
   'Update CSS setting for the OPAC', 'ppl', 'description'))
;

UPDATE config.org_unit_setting_type SET update_perm = 620 WHERE name = 'opac.patron.custom_css';


SELECT evergreen.upgrade_deps_block_check('1203', :eg_version);

ALTER TABLE config.best_hold_order ADD COLUMN owning_lib_to_home_lib_prox INT; -- copy owning lib <-> user home lib prox

ALTER table config.best_hold_order DROP CONSTRAINT best_hold_order_check;

-- At least one of these columns must contain a non-null value
ALTER TABLE config.best_hold_order ADD CHECK ((
    pprox IS NOT NULL OR
    hprox IS NOT NULL OR
    owning_lib_to_home_lib_prox IS NOT NULL OR
    aprox IS NOT NULL OR
    priority IS NOT NULL OR
    cut IS NOT NULL OR
    depth IS NOT NULL OR
    htime IS NOT NULL OR
    rtime IS NOT NULL
));

INSERT INTO config.best_hold_order (
    name,
    owning_lib_to_home_lib_prox, hprox, approx, pprox, aprox, priority, cut, depth, rtime
) VALUES (
    'Traditional with Holds-chase-home-lib-patrons',
    1, 2, 3, 4, 5, 6, 7, 8, 9
);

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
