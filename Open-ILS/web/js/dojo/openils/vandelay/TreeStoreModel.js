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
    return {
        "label": model.getLabel(item),
        "match_point": String(model.store.getValue(item, "match_point")),
        "children": {}
    };
}

dojo.declare(
    "openils.vandelay.TreeStoreModel", dijit.tree.TreeStoreModel, {
        "_replace_mode": 0,
        "getSimpleTree": function(item, oncomplete, result) {
            var self = this;
            if (!result) result = {};

            var mykey = this.getIdentity(item);
            result[mykey] = _simple_item(this, item);
            var child_collector = result[mykey].children;

            if (this.mayHaveChildren(item)) {
                this.getChildren(
                    item, function(children) {
                        for (var i = 0; i < children.length; i++) {
                            self.getSimpleTree(
                                children[i], null, child_collector
                            );
                        }
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
//        "newItem": function(args, parent) {
//            if (!this.mayHaveChildren(parent)) return;
//            return this.inherited(arguments);
//        }
    }
);
