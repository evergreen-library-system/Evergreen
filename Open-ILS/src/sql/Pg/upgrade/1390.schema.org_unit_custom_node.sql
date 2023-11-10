BEGIN;

SELECT evergreen.upgrade_deps_block_check('1390', :eg_version);

ALTER TABLE actor.org_unit_custom_tree_node
DROP CONSTRAINT org_unit_custom_tree_node_parent_node_fkey;

ALTER TABLE actor.org_unit_custom_tree_node
ADD CONSTRAINT org_unit_custom_tree_node_parent_node_fkey 
FOREIGN KEY (parent_node) 
REFERENCES actor.org_unit_custom_tree_node(id) 
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

COMMIT;
