BEGIN;

-- Create seed data for the asset.uri table
INSERT INTO asset.uri (id, href, active) VALUES (-1, 'http://example.com/fake', FALSE);

COMMIT;

