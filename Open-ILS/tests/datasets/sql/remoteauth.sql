-- config for Basic HTTP Authentication (SYS1)
INSERT INTO config.remoteauth_profile
    (name, description, context_org, enabled, perm,
        restrict_to_org, allow_inactive, allow_expired, block_list)
    VALUES ('Basic', 'Basic HTTP Authentication for SYS1', 2, TRUE, 1,
        TRUE, FALSE, FALSE, NULL);

