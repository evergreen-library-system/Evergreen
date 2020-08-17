BEGIN;

SELECT evergreen.upgrade_deps_block_check('1213', :eg_version);

CREATE OR REPLACE FUNCTION actor.change_password (user_id INT, new_pw TEXT, pw_type TEXT DEFAULT 'main')
RETURNS VOID AS $$
DECLARE
    new_salt TEXT;
BEGIN
    SELECT actor.create_salt(pw_type) INTO new_salt;

    IF pw_type = 'main' THEN
        -- Only 'main' passwords are required to have
        -- the extra layer of MD5 hashing.
        PERFORM actor.set_passwd(
            user_id, pw_type, md5(new_salt || md5(new_pw)), new_salt
        );

    ELSE
        PERFORM actor.set_passwd(user_id, pw_type, new_pw, new_salt);
    END IF;
END;
$$ LANGUAGE 'plpgsql';

COMMENT ON FUNCTION actor.change_password(INT,TEXT,TEXT) IS $$
Allows setting a salted password for a user by passing actor.usr id and the text of the password.
$$;

COMMIT;
