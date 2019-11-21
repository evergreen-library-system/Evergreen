INSERT INTO config.usr_activity_type (id, ewho, ewhat, ehow, egroup, label) VALUES
 ( 1001, 'basicauth', 'login', 'apache', 'authen',
    oils_i18n_gettext(1001, 'RemoteAuth Login: HTTP Basic Authentication', 'cuat', 'label'));

-- config for Basic HTTP Authentication (SYS1)
INSERT INTO config.remoteauth_profile
    (name, description, context_org, enabled, perm,
        restrict_to_org, allow_inactive, allow_expired, block_list, usr_activity_type)
    VALUES ('Basic', 'Basic HTTP Authentication for SYS1', 2, TRUE, 1,
        TRUE, FALSE, FALSE, NULL, 1001);

INSERT INTO config.usr_activity_type (id, ewho, ewhat, ehow, egroup, label) VALUES
 ( 1002, 'ezproxy', 'login', 'apache', 'authen',
    oils_i18n_gettext(1002, 'RemoteAuth Login: EZProxy CGI Authentication', 'cuat', 'label'));

-- config for EZProxy CGI Authentication (SYS2)
INSERT INTO config.remoteauth_profile
    (name, description, context_org, enabled, perm,
        restrict_to_org, allow_inactive, allow_expired, block_list, usr_activity_type)
    VALUES ('EZProxyCGI', 'EZProxy CGI Authentication for SYS2', 3, TRUE, 1,
        TRUE, FALSE, FALSE, NULL, 1002);

