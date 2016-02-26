BEGIN;

SELECT evergreen.upgrade_deps_block_check('0961', :eg_version);

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE actor.passwd_type (
    code        TEXT PRIMARY KEY,
    name        TEXT UNIQUE NOT NULL,
    login       BOOLEAN NOT NULL DEFAULT FALSE,
    regex       TEXT,   -- pending
    crypt_algo  TEXT,   -- e.g. 'bf'

    -- gen_salt() iter count used with each new salt.
    -- A non-NULL value for iter_count is our indication the 
    -- password is salted and encrypted via crypt()
    iter_count  INTEGER CHECK (iter_count IS NULL OR iter_count > 0)
);

CREATE TABLE actor.passwd (
    id          SERIAL PRIMARY KEY,
    usr         INTEGER NOT NULL REFERENCES actor.usr(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    salt        TEXT, -- will be NULL for non-crypt'ed passwords
    passwd      TEXT NOT NULL,
    passwd_type TEXT NOT NULL REFERENCES actor.passwd_type(code)
                DEFERRABLE INITIALLY DEFERRED,
    create_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    edit_date   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT  passwd_type_once_per_user UNIQUE (usr, passwd_type)
);

CREATE OR REPLACE FUNCTION actor.create_salt(pw_type TEXT)
    RETURNS TEXT AS $$
DECLARE
    type_row actor.passwd_type%ROWTYPE;
BEGIN
    /* Returns a new salt based on the passwd_type encryption settings.
     * Returns NULL If the password type is not crypt()'ed.
     */

    SELECT INTO type_row * FROM actor.passwd_type WHERE code = pw_type;

    IF NOT FOUND THEN
        RETURN EXCEPTION 'No such password type: %', pw_type;
    END IF;

    IF type_row.iter_count IS NULL THEN
        -- This password type is unsalted.  That's OK.
        RETURN NULL;
    END IF;

    RETURN gen_salt(type_row.crypt_algo, type_row.iter_count);
END;
$$ LANGUAGE PLPGSQL;


/* 
    TODO: when a user changes their password in the application, the
    app layer has access to the bare password.  At that point, we have
    the opportunity to store the new password without the MD5(MD5())
    intermediate hashing.  Do we care?  We would need a way to indicate
    which passwords have the legacy intermediate hashing and which don't
    so the app layer would know whether it should perform the intermediate
    hashing.  In either event, with the exception of migrate_passwd(), the
    DB functions know or care nothing about intermediate hashing.  Every
    password is just a value that may or may not be internally crypt'ed. 
*/

CREATE OR REPLACE FUNCTION actor.set_passwd(
    pw_usr INTEGER, pw_type TEXT, new_pass TEXT, new_salt TEXT DEFAULT NULL)
    RETURNS BOOLEAN AS $$
DECLARE
    pw_salt TEXT;
    pw_text TEXT;
BEGIN
    /* Sets the password value, creating a new actor.passwd row if needed.
     * If the password type supports it, the new_pass value is crypt()'ed.
     * For crypt'ed passwords, the salt comes from one of 3 places in order:
     * new_salt (if present), existing salt (if present), newly created 
     * salt.
     */

    IF new_salt IS NOT NULL THEN
        pw_salt := new_salt;
    ELSE 
        pw_salt := actor.get_salt(pw_usr, pw_type);

        IF pw_salt IS NULL THEN
            /* We have no salt for this user + type.  Assume they want a 
             * new salt.  If this type is unsalted, create_salt() will 
             * return NULL. */
            pw_salt := actor.create_salt(pw_type);
        END IF;
    END IF;

    IF pw_salt IS NULL THEN 
        pw_text := new_pass; -- unsalted, use as-is.
    ELSE
        pw_text := CRYPT(new_pass, pw_salt);
    END IF;

    UPDATE actor.passwd 
        SET passwd = pw_text, salt = pw_salt, edit_date = NOW()
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no password row exists for this user + type.  Create one.
        INSERT INTO actor.passwd (usr, passwd_type, salt, passwd) 
            VALUES (pw_usr, pw_type, pw_salt, pw_text);
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION actor.get_salt(pw_usr INTEGER, pw_type TEXT)
    RETURNS TEXT AS $$
DECLARE
    pw_salt TEXT;
    type_row actor.passwd_type%ROWTYPE;
BEGIN
    /* Returns the salt for the requested user + type.  If the password 
     * type of "main" is requested and no password exists in actor.passwd, 
     * the user's existing password is migrated and the new salt is returned.
     * Returns NULL if the password type is not crypt'ed (iter_count is NULL).
     */

    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF FOUND THEN
        RETURN pw_salt;
    END IF;

    IF pw_type = 'main' THEN
        -- Main password has not yet been migrated. 
        -- Do it now and return the newly created salt.
        RETURN actor.migrate_passwd(pw_usr);
    END IF;

    -- We have no salt to return.  actor.create_salt() needed.
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION 
    actor.migrate_passwd(pw_usr INTEGER) RETURNS TEXT AS $$
DECLARE
    pw_salt TEXT;
    usr_row actor.usr%ROWTYPE;
BEGIN
    /* Migrates legacy actor.usr.passwd value to actor.passwd with 
     * a password type 'main' and returns the new salt.  For backwards
     * compatibility with existing CHAP-style API's, we perform a 
     * layer of intermediate MD5(MD5()) hashing.  This is intermediate
     * hashing is not required of other passwords.
     */

    -- Avoid calling get_salt() here, because it may result in a 
    -- migrate_passwd() call, creating a loop.
    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = 'main';

    -- Only migrate passwords that have not already been migrated.
    IF FOUND THEN
        RETURN pw_salt;
    END IF;

    SELECT INTO usr_row * FROM actor.usr WHERE id = pw_usr;

    pw_salt := actor.create_salt('main');

    PERFORM actor.set_passwd(
        pw_usr, 'main', MD5(pw_salt || usr_row.passwd), pw_salt);

    -- clear the existing password
    UPDATE actor.usr SET passwd = '' WHERE id = usr_row.id;

    RETURN pw_salt;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION 
    actor.verify_passwd(pw_usr INTEGER, pw_type TEXT, test_passwd TEXT) 
    RETURNS BOOLEAN AS $$
DECLARE
    pw_salt TEXT;
BEGIN
    /* Returns TRUE if the password provided matches the in-db password.  
     * If the password type is salted, we compare the output of CRYPT().
     * NOTE: test_passwd is MD5(salt || MD5(password)) for legacy 
     * 'main' passwords.
     */

    SELECT INTO pw_salt salt FROM actor.passwd 
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no such password
        RETURN FALSE;
    END IF;

    IF pw_salt IS NULL THEN
        -- Password is unsalted, compare the un-CRYPT'ed values.
        RETURN EXISTS (
            SELECT TRUE FROM actor.passwd WHERE 
                usr = pw_usr AND
                passwd_type = pw_type AND
                passwd = test_passwd
        );
    END IF;

    RETURN EXISTS (
        SELECT TRUE FROM actor.passwd WHERE 
            usr = pw_usr AND
            passwd_type = pw_type AND
            passwd = CRYPT(test_passwd, pw_salt)
    );
END;
$$ STRICT LANGUAGE PLPGSQL;

--- DATA ----------------------

INSERT INTO actor.passwd_type 
    (code, name, login, crypt_algo, iter_count) 
    VALUES ('main', 'Main Login Password', TRUE, 'bf', 10);

COMMIT;
