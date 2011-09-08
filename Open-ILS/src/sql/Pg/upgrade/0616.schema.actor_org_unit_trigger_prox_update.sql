BEGIN;

SELECT evergreen.upgrade_deps_block_check('0616', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_prox_update () RETURNS TRIGGER as $$
BEGIN


IF TG_OP = 'DELETE' THEN

    DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);

END IF;

IF TG_OP = 'UPDATE' THEN

    IF NEW.parent_ou <> OLD.parent_ou THEN

        DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);
            INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
            SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
                FROM  actor.org_unit l, actor.org_unit r
                WHERE (l.id = NEW.id or r.id = NEW.id);

    END IF;

END IF;

IF TG_OP = 'INSERT' THEN

     INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
     SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
         FROM  actor.org_unit l, actor.org_unit r
         WHERE (l.id = NEW.id or r.id = NEW.id);

END IF;

RETURN null;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER proximity_update_tgr AFTER INSERT OR UPDATE OR DELETE ON actor.org_unit FOR EACH ROW EXECUTE PROCEDURE actor.org_unit_prox_update ();

COMMIT;
