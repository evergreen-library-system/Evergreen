BEGIN;

ALTER TABLE actor.usr ADD CONSTRAINT usr_address_fkey FOREIGN KEY ( address ) REFERENCES actor.usr_address (id) ON DELETE RESTRICT;
ALTER TABLE actor.usr ADD CONSTRAINT usr_home_ou_fkey FOREIGN KEY ( home_ou ) REFERENCES actor.org_unit (id) ON DELETE RESTRICT;

ALTER TABLE actor.org_unit_type ADD CONSTRAINT org_unit_type_parent_fkey FOREIGN KEY ( parent ) REFERENCES actor.org_unit_type (id) ON DELETE RESTRICT;

ALTER TABLE actor.org_unit ADD CONSTRAINT org_unit_parent_ou_fkey FOREIGN KEY ( parent_ou ) REFERENCES actor.org_unit (id) ON DELETE RESTRICT;
ALTER TABLE actor.org_unit ADD CONSTRAINT org_unit_ou_type_fkey FOREIGN KEY ( ou_type ) REFERENCES actor.org_unit_type (id) ON DELETE RESTRICT;

ALTER TABLE actor.usr_access_entry ADD CONSTRAINT usr_access_entry_usr_fkey FOREIGN KEY ( usr ) REFERENCES actor.usr (id) ON DELETE RESTRICT;
ALTER TABLE actor.usr_access_entry ADD CONSTRAINT usr_access_entry_org_unit_fkey FOREIGN KEY ( org_unit ) REFERENCES actor.org_unit (id) ON DELETE RESTRICT;

ALTER TABLE actor.perm_group ADD CONSTRAINT perm_group_org_unit_fkey FOREIGN KEY ( ou_type ) REFERENCES actor.org_unit_type (id) ON DELETE RESTRICT;

ALTER TABLE actor.perm_group_permission_map ADD CONSTRAINT perm_group_permission_map_permission_fkey FOREIGN KEY ( permission ) REFERENCES actor.permission (id) ON DELETE RESTRICT;
ALTER TABLE actor.perm_group_permission_map ADD CONSTRAINT perm_group_permission_map_perm_group_fkey FOREIGN KEY ( perm_group ) REFERENCES actor.perm_group (id) ON DELETE RESTRICT;

ALTER TABLE actor.perm_group_usr_map ADD CONSTRAINT perm_group_usr_map_permission_fkey FOREIGN KEY ( usr ) REFERENCES actor.usr (id) ON DELETE RESTRICT;
ALTER TABLE actor.perm_group_usr_map ADD CONSTRAINT perm_group_usr_map_perm_group_fkey FOREIGN KEY ( perm_group ) REFERENCES actor.perm_group (id) ON DELETE RESTRICT;

ALTER TABLE actor.usr_address ADD CONSTRAINT usr_address_usr_fkey FOREIGN KEY ( usr ) REFERENCES actor.usr (id) ON DELETE RESTRICT;

COMMIT;
