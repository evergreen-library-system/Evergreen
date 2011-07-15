dojo.provide("openils.vandelay.TreeStoreModel");
dojo.require("dijit.tree.TreeStoreModel");
dojo.require("openils.Util");

/* This class specifically serves the eg/vandelay/match_set interface
 * for editing Vandelay Match Set trees.  It should probably  have a more
 * specific name that reflects that.
 */

function _simple_item(model, item) {
    /* Instead of model.getLabel(), could do
     * model.store.getValue(item, "blah") or something like that ... */
    var mp = model.store.getValue(item, "match_point");
    mp.children([]);
    return mp;
}

dojo.declare(
    "openils.vandelay.TreeStoreModel", dijit.tree.TreeStoreModel, {
        "replace_mode": 0,
        "get_simple_tree": function(item, oncomplete, result) {
            var self = this;
            var me;
            if (!result) {
                me = result = _simple_item(this, item);
            } else {
                me = _simple_item(this, item);
                result.push(me);
            }

            if (this.mayHaveChildren(item)) {
                this.getChildren(
                    item, function(children) {
                        var kids_here = [];
                        for (var i = 0; i < children.length; i++) {
                            self.get_simple_tree(children[i], null, kids_here);
                        }
                        me.children(kids_here);
                        if (oncomplete) oncomplete(result);
                    }
                );
            }
        },
        "mayHaveChildren": function(item) {
            var match_point = this.store.getValue(item, "match_point");
            if (match_point)
                return openils.Util.isTrue(match_point.bool_op());
            else
                return true;
        }
    }
);
