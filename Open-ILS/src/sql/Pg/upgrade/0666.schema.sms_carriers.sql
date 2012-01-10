BEGIN;

SELECT evergreen.upgrade_deps_block_check('0666', :eg_version);

-- 950.data.seed-values.sql
INSERT INTO config.settings_group (name, label) VALUES
    (
        'sms',
        oils_i18n_gettext(
            'sms',
            'SMS Text Messages',
            'csg',
            'label'
        )
    )
;

INSERT INTO config.org_unit_setting_type (name, grp, label, description, datatype) VALUES
    (
        'sms.enable',
        'sms',
        oils_i18n_gettext(
            'sms.enable',
            'Enable features that send SMS text messages.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'sms.enable',
            'Current features that use SMS include hold-ready-for-pickup notifications and a "Send Text" action for call numbers in the OPAC. If this setting is not enabled, the SMS options will not be offered to the user.  Unless you are carefully silo-ing patrons and their use of the OPAC, the context org for this setting should be the top org in the org hierarchy, otherwise patrons can trample their user settings when jumping between orgs.',
            'coust',
            'description'
        ),
        'bool'
    )
    ,(
        'sms.disable_authentication_requirement.callnumbers',
        'sms',
        oils_i18n_gettext(
            'sms.disable_authentication_requirement.callnumbers',
            'Disable auth requirement for texting call numbers.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'sms.disable_authentication_requirement.callnumbers',
            'Disable authentication requirement for sending call number information via SMS from the OPAC.',
            'coust',
            'description'
        ),
        'bool'
    )
;

-- 002.schema.config.sql
CREATE TABLE config.sms_carrier (
    id              SERIAL PRIMARY KEY,
    region          TEXT,
    name            TEXT,
    email_gateway   TEXT,
    active          BOOLEAN DEFAULT TRUE
);

-- 090.schema.action.sql
ALTER TABLE action.hold_request ADD COLUMN sms_notify TEXT;
ALTER TABLE action.hold_request ADD COLUMN sms_carrier INT REFERENCES config.sms_carrier (id);
ALTER TABLE action.hold_request ADD CONSTRAINT sms_check CHECK (
    sms_notify IS NULL
    OR sms_carrier IS NOT NULL -- and implied sms_notify IS NOT NULL
);

-- 950.data.seed-values.sql
INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype,fm_class) VALUES (
    'opac.default_sms_carrier',
    'sms',
    TRUE,
    oils_i18n_gettext(
        'opac.default_sms_carrier',
        'Default SMS/Text Carrier',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_sms_carrier',
        'Default SMS/Text Carrier',
        'cust',
        'description'
    ),
    'link',
    'csc'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'opac.default_sms_notify',
    'sms',
    TRUE,
    oils_i18n_gettext(
        'opac.default_sms_notify',
        'Default SMS/Text Number',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_sms_notify',
        'Default SMS/Text Number',
        'cust',
        'description'
    ),
    'string'
);

INSERT INTO config.usr_setting_type (name,grp,opac_visible,label,description,datatype) VALUES (
    'opac.default_phone',
    'opac',
    TRUE,
    oils_i18n_gettext(
        'opac.default_phone',
        'Default Phone Number',
        'cust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.default_phone',
        'Default Phone Number',
        'cust',
        'description'
    ),
    'string'
);

SELECT setval( 'config.sms_carrier_id_seq', 1000 );
INSERT INTO config.sms_carrier VALUES

    -- Testing
    (
        1,
        oils_i18n_gettext(
            1,
            'Local',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            1,
            'Test Carrier',
            'csc',
            'name'
        ),
        'opensrf+$number@localhost',
        FALSE
    ),

    -- Canada & USA
    (
        2,
        oils_i18n_gettext(
            2,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            2,
            'Rogers Wireless',
            'csc',
            'name'
        ),
        '$number@pcs.rogers.com',
        TRUE
    ),
    (
        3,
        oils_i18n_gettext(
            3,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            3,
            'Rogers Wireless (Alternate)',
            'csc',
            'name'
        ),
        '1$number@mms.rogers.com',
        TRUE
    ),
    (
        4,
        oils_i18n_gettext(
            4,
            'Canada & USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            4,
            'Telus Mobility',
            'csc',
            'name'
        ),
        '$number@msg.telus.com',
        TRUE
    ),

    -- Canada
    (
        5,
        oils_i18n_gettext(
            5,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            5,
            'Koodo Mobile',
            'csc',
            'name'
        ),
        '$number@msg.telus.com',
        TRUE
    ),
    (
        6,
        oils_i18n_gettext(
            6,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            6,
            'Fido',
            'csc',
            'name'
        ),
        '$number@fido.ca',
        TRUE
    ),
    (
        7,
        oils_i18n_gettext(
            7,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            7,
            'Bell Mobility & Solo Mobile',
            'csc',
            'name'
        ),
        '$number@txt.bell.ca',
        TRUE
    ),
    (
        8,
        oils_i18n_gettext(
            8,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            8,
            'Bell Mobility & Solo Mobile (Alternate)',
            'csc',
            'name'
        ),
        '$number@txt.bellmobility.ca',
        TRUE
    ),
    (
        9,
        oils_i18n_gettext(
            9,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            9,
            'Aliant',
            'csc',
            'name'
        ),
        '$number@sms.wirefree.informe.ca',
        TRUE
    ),
    (
        10,
        oils_i18n_gettext(
            10,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            10,
            'PC Telecom',
            'csc',
            'name'
        ),
        '$number@mobiletxt.ca',
        TRUE
    ),
    (
        11,
        oils_i18n_gettext(
            11,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            11,
            'SaskTel',
            'csc',
            'name'
        ),
        '$number@sms.sasktel.com',
        TRUE
    ),
    (
        12,
        oils_i18n_gettext(
            12,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            12,
            'MTS Mobility',
            'csc',
            'name'
        ),
        '$number@text.mtsmobility.com',
        TRUE
    ),
    (
        13,
        oils_i18n_gettext(
            13,
            'Canada',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            13,
            'Virgin Mobile',
            'csc',
            'name'
        ),
        '$number@vmobile.ca',
        TRUE
    ),

    -- International
    (
        14,
        oils_i18n_gettext(
            14,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            14,
            'Iridium',
            'csc',
            'name'
        ),
        '$number@msg.iridium.com',
        TRUE
    ),
    (
        15,
        oils_i18n_gettext(
            15,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            15,
            'Globalstar',
            'csc',
            'name'
        ),
        '$number@msg.globalstarusa.com',
        TRUE
    ),
    (
        16,
        oils_i18n_gettext(
            16,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            16,
            'Bulletin.net',
            'csc',
            'name'
        ),
        '$number@bulletinmessenger.net', -- International Formatted number
        TRUE
    ),
    (
        17,
        oils_i18n_gettext(
            17,
            'International',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            17,
            'Panacea Mobile',
            'csc',
            'name'
        ),
        '$number@api.panaceamobile.com',
        TRUE
    ),

    -- USA
    (
        18,
        oils_i18n_gettext(
            18,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            18,
            'C Beyond',
            'csc',
            'name'
        ),
        '$number@cbeyond.sprintpcs.com',
        TRUE
    ),
    (
        19,
        oils_i18n_gettext(
            19,
            'Alaska, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            19,
            'General Communications, Inc.',
            'csc',
            'name'
        ),
        '$number@mobile.gci.net',
        TRUE
    ),
    (
        20,
        oils_i18n_gettext(
            20,
            'California, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            20,
            'Golden State Cellular',
            'csc',
            'name'
        ),
        '$number@gscsms.com',
        TRUE
    ),
    (
        21,
        oils_i18n_gettext(
            21,
            'Cincinnati, Ohio, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            21,
            'Cincinnati Bell',
            'csc',
            'name'
        ),
        '$number@gocbw.com',
        TRUE
    ),
    (
        22,
        oils_i18n_gettext(
            22,
            'Hawaii, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            22,
            'Hawaiian Telcom Wireless',
            'csc',
            'name'
        ),
        '$number@hawaii.sprintpcs.com',
        TRUE
    ),
    (
        23,
        oils_i18n_gettext(
            23,
            'Midwest, USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            23,
            'i wireless (T-Mobile)',
            'csc',
            'name'
        ),
        '$number.iws@iwspcs.net',
        TRUE
    ),
    (
        24,
        oils_i18n_gettext(
            24,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            24,
            'i-wireless (Sprint PCS)',
            'csc',
            'name'
        ),
        '$number@iwirelesshometext.com',
        TRUE
    ),
    (
        25,
        oils_i18n_gettext(
            25,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            25,
            'MetroPCS',
            'csc',
            'name'
        ),
        '$number@mymetropcs.com',
        TRUE
    ),
    (
        26,
        oils_i18n_gettext(
            26,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            26,
            'Kajeet',
            'csc',
            'name'
        ),
        '$number@mobile.kajeet.net',
        TRUE
    ),
    (
        27,
        oils_i18n_gettext(
            27,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            27,
            'Element Mobile',
            'csc',
            'name'
        ),
        '$number@SMS.elementmobile.net',
        TRUE
    ),
    (
        28,
        oils_i18n_gettext(
            28,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            28,
            'Esendex',
            'csc',
            'name'
        ),
        '$number@echoemail.net',
        TRUE
    ),
    (
        29,
        oils_i18n_gettext(
            29,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            29,
            'Boost Mobile',
            'csc',
            'name'
        ),
        '$number@myboostmobile.com',
        TRUE
    ),
    (
        30,
        oils_i18n_gettext(
            30,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            30,
            'BellSouth',
            'csc',
            'name'
        ),
        '$number@bellsouth.com',
        TRUE
    ),
    (
        31,
        oils_i18n_gettext(
            31,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            31,
            'Bluegrass Cellular',
            'csc',
            'name'
        ),
        '$number@sms.bluecell.com',
        TRUE
    ),
    (
        32,
        oils_i18n_gettext(
            32,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            32,
            'AT&T Enterprise Paging',
            'csc',
            'name'
        ),
        '$number@page.att.net',
        TRUE
    ),
    (
        33,
        oils_i18n_gettext(
            33,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            33,
            'AT&T Mobility/Wireless',
            'csc',
            'name'
        ),
        '$number@txt.att.net',
        TRUE
    ),
    (
        34,
        oils_i18n_gettext(
            34,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            34,
            'AT&T Global Smart Messaging Suite',
            'csc',
            'name'
        ),
        '$number@sms.smartmessagingsuite.com',
        TRUE
    ),
    (
        35,
        oils_i18n_gettext(
            35,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            35,
            'Alltel (Allied Wireless)',
            'csc',
            'name'
        ),
        '$number@sms.alltelwireless.com',
        TRUE
    ),
    (
        36,
        oils_i18n_gettext(
            36,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            36,
            'Alaska Communications',
            'csc',
            'name'
        ),
        '$number@msg.acsalaska.com',
        TRUE
    ),
    (
        37,
        oils_i18n_gettext(
            37,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            37,
            'Ameritech',
            'csc',
            'name'
        ),
        '$number@paging.acswireless.com',
        TRUE
    ),
    (
        38,
        oils_i18n_gettext(
            38,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            38,
            'Cingular (GoPhone prepaid)',
            'csc',
            'name'
        ),
        '$number@cingulartext.com',
        TRUE
    ),
    (
        39,
        oils_i18n_gettext(
            39,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            39,
            'Cingular (Postpaid)',
            'csc',
            'name'
        ),
        '$number@cingular.com',
        TRUE
    ),
    (
        40,
        oils_i18n_gettext(
            40,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            40,
            'Cellular One (Dobson) / O2 / Orange',
            'csc',
            'name'
        ),
        '$number@mobile.celloneusa.com',
        TRUE
    ),
    (
        41,
        oils_i18n_gettext(
            41,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            41,
            'Cellular South',
            'csc',
            'name'
        ),
        '$number@csouth1.com',
        TRUE
    ),
    (
        42,
        oils_i18n_gettext(
            42,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            42,
            'Cellcom',
            'csc',
            'name'
        ),
        '$number@cellcom.quiktxt.com',
        TRUE
    ),
    (
        43,
        oils_i18n_gettext(
            43,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            43,
            'Chariton Valley Wireless',
            'csc',
            'name'
        ),
        '$number@sms.cvalley.net',
        TRUE
    ),
    (
        44,
        oils_i18n_gettext(
            44,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            44,
            'Cricket',
            'csc',
            'name'
        ),
        '$number@sms.mycricket.com',
        TRUE
    ),
    (
        45,
        oils_i18n_gettext(
            45,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            45,
            'Cleartalk Wireless',
            'csc',
            'name'
        ),
        '$number@sms.cleartalk.us',
        TRUE
    ),
    (
        46,
        oils_i18n_gettext(
            46,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            46,
            'Edge Wireless',
            'csc',
            'name'
        ),
        '$number@sms.edgewireless.com',
        TRUE
    ),
    (
        47,
        oils_i18n_gettext(
            47,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            47,
            'Syringa Wireless',
            'csc',
            'name'
        ),
        '$number@rinasms.com',
        TRUE
    ),
    (
        48,
        oils_i18n_gettext(
            48,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            48,
            'T-Mobile',
            'csc',
            'name'
        ),
        '$number@tmomail.net',
        TRUE
    ),
    (
        49,
        oils_i18n_gettext(
            49,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            49,
            'Straight Talk / PagePlus Cellular',
            'csc',
            'name'
        ),
        '$number@vtext.com',
        TRUE
    ),
    (
        50,
        oils_i18n_gettext(
            50,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            50,
            'South Central Communications',
            'csc',
            'name'
        ),
        '$number@rinasms.com',
        TRUE
    ),
    (
        51,
        oils_i18n_gettext(
            51,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            51,
            'Simple Mobile',
            'csc',
            'name'
        ),
        '$number@smtext.com',
        TRUE
    ),
    (
        52,
        oils_i18n_gettext(
            52,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            52,
            'Sprint (PCS)',
            'csc',
            'name'
        ),
        '$number@messaging.sprintpcs.com',
        TRUE
    ),
    (
        53,
        oils_i18n_gettext(
            53,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            53,
            'Nextel',
            'csc',
            'name'
        ),
        '$number@messaging.nextel.com',
        TRUE
    ),
    (
        54,
        oils_i18n_gettext(
            54,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            54,
            'Pioneer Cellular',
            'csc',
            'name'
        ),
        '$number@zsend.com', -- nine digit number
        TRUE
    ),
    (
        55,
        oils_i18n_gettext(
            55,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            55,
            'Qwest Wireless',
            'csc',
            'name'
        ),
        '$number@qwestmp.com',
        TRUE
    ),
    (
        56,
        oils_i18n_gettext(
            56,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            56,
            'US Cellular',
            'csc',
            'name'
        ),
        '$number@email.uscc.net',
        TRUE
    ),
    (
        57,
        oils_i18n_gettext(
            57,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            57,
            'Unicel',
            'csc',
            'name'
        ),
        '$number@utext.com',
        TRUE
    ),
    (
        58,
        oils_i18n_gettext(
            58,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            58,
            'Teleflip',
            'csc',
            'name'
        ),
        '$number@teleflip.com',
        TRUE
    ),
    (
        59,
        oils_i18n_gettext(
            59,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            59,
            'Virgin Mobile',
            'csc',
            'name'
        ),
        '$number@vmobl.com',
        TRUE
    ),
    (
        60,
        oils_i18n_gettext(
            60,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            60,
            'Verizon Wireless',
            'csc',
            'name'
        ),
        '$number@vtext.com',
        TRUE
    ),
    (
        61,
        oils_i18n_gettext(
            61,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            61,
            'USA Mobility',
            'csc',
            'name'
        ),
        '$number@usamobility.net',
        TRUE
    ),
    (
        62,
        oils_i18n_gettext(
            62,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            62,
            'Viaero',
            'csc',
            'name'
        ),
        '$number@viaerosms.com',
        TRUE
    ),
    (
        63,
        oils_i18n_gettext(
            63,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            63,
            'TracFone',
            'csc',
            'name'
        ),
        '$number@mmst5.tracfone.com',
        TRUE
    ),
    (
        64,
        oils_i18n_gettext(
            64,
            'USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            64,
            'Centennial Wireless',
            'csc',
            'name'
        ),
        '$number@cwemail.com',
        TRUE
    ),

    -- South Korea and USA
    (
        65,
        oils_i18n_gettext(
            65,
            'South Korea and USA',
            'csc',
            'region'
        ),
        oils_i18n_gettext(
            65,
            'Helio',
            'csc',
            'name'
        ),
        '$number@myhelio.com',
        TRUE
    )
;

INSERT INTO permission.perm_list ( id, code, description ) VALUES
    (
        517,
        'ADMIN_SMS_CARRIER',
        oils_i18n_gettext(
            517,
            'Allows a user to add/create/delete SMS Carrier entries.',
            'ppl',
            'description'
        )
    )
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, TRUE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Global Administrator' AND
        aout.name = 'Consortium' AND
        perm.code = 'ADMIN_SMS_CARRIER';

INSERT INTO action_trigger.reactor (
    module,
    description
) VALUES (
    'SendSMS',
    'Send an SMS text message based on a user-defined template'
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    cleanup_success,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    true,
    1, -- admin
    'Hold Ready for Pickup SMS Notification',
    'hold.available',
    'HoldIsAvailable',
    'SendSMS',
    'CreateHoldNotification',
    '00:30:00',
    'shelf_time',
    'sms_notify',
    '[%- USE date -%]
[%- user = target.0.usr -%]
From: [%- params.sender_email || default_sender %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(target.0.sms_carrier,target.0.sms_notify) %]
Subject: [% target.size %] hold(s) ready

[% FOR hold IN target %][%-
  bibxml = helpers.xml_doc( hold.current_copy.call_number.record.marc );
  title = "";
  FOR part IN bibxml.findnodes(''//*[@tag="245"]/*[@code="a"]'');
    title = title _ part.textContent;
  END;
  author = bibxml.findnodes(''//*[@tag="100"]/*[@code="a"]'').textContent;
%][% hold.usr.first_given_name %]:[% title %] @ [% hold.pickup_lib.name %]
[% END %]
'
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'current_copy.call_number.record.simple_record'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib.billing_address'
);

INSERT INTO action_trigger.hook(
    key,
    core_type,
    description,
    passive
) VALUES (
    'acn.format.sms_text',
    'acn',
    oils_i18n_gettext(
        'acn.format.sms_text',
        'A text message has been requested for a call number.',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    template
) VALUES (
    true,
    1, -- admin
    'SMS Call Number',
    'acn.format.sms_text',
    'NOOP_True',
    'SendSMS',
    '[%- USE date -%]
From: [%- params.sender_email || default_sender %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(user_data.sms_carrier,user_data.sms_notify) %]
Subject: Call Number

[%-
  bibxml = helpers.xml_doc( target.record.marc );
  title = "";
  FOR part IN bibxml.findnodes(''//*[@tag="245"]/*[@code="a" or @code="b"]'');
    title = title _ part.textContent;
  END;
  author = bibxml.findnodes(''//*[@tag="100"]/*[@code="a"]'').textContent;
%]
Call Number: [% target.label %]
Location: [% helpers.get_most_populous_location( target.id ).name %]
Library: [% target.owning_lib.name %]
[%- IF title %]
Title: [% title %]
[%- END %]
[%- IF author %]
Author: [% author %]
[%- END %]
'
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'record.simple_record'
), (
    currval('action_trigger.event_definition_id_seq'),
    'owning_lib.billing_address'
);


-- DELETE FROM actor.usr_setting WHERE name = 'opac.default_phone' OR name in ( SELECT name FROM config.usr_setting_type WHERE grp = 'sms' ); DELETE FROM config.usr_setting_type WHERE name = 'opac.default_phone' OR grp = 'sms'; DELETE FROM actor.org_unit_setting WHERE name in ( SELECT name FROM config.org_unit_setting_type WHERE grp = 'sms' ); DELETE FROM config.org_unit_setting_type_log WHERE field_name in ( SELECT name FROM config.org_unit_setting_type WHERE grp = 'sms' ); DELETE FROM config.org_unit_setting_type WHERE grp = 'sms'; DELETE FROM config.settings_group WHERE name = 'sms'; DELETE FROM permission.grp_perm_map WHERE perm = 517; DELETE FROM permission.perm_list WHERE id = 517; ALTER TABLE action.hold_request DROP CONSTRAINT sms_check; ALTER TABLE action.hold_request DROP COLUMN sms_notify; ALTER TABLE action.hold_request DROP COLUMN sms_carrier; DROP TABLE config.sms_carrier; DELETE FROM action_trigger.event WHERE event_def = ( SELECT id FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification' ); DELETE FROM action_trigger.environment WHERE event_def = ( SELECT id FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification' ); DELETE FROM action_trigger.event_definition WHERE name = 'Hold Ready for Pickup SMS Notification'; DELETE FROM action_trigger.event WHERE event_def IN ( SELECT id FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text' ); DELETE FROM action_trigger.environment WHERE event_def IN ( SELECT id FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text' ); DELETE FROM action_trigger.event_definition WHERE hook = 'acn.format.sms_text'; DELETE FROM action_trigger.hook WHERE key = 'acn.format.sms_text'; DELETE FROM action_trigger.reactor WHERE module = 'SendSMS'; DELETE FROM config.upgrade_log WHERE version = 'XXXX';

COMMIT;
