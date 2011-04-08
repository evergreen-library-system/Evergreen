dojo.provide("openils.vandelay.TreeDndSource");
dojo.require("dijit._tree.dndSource");

/* This class specifically serves the eg/vandelay/match_set interface
 * for editing Vandelay Match Set trees.  It should probably  have a more
 * specific name that reflects that.
 */
dojo.declare(
    "openils.vandelay.TreeDndSource", dijit._tree.dndSource, {
        "checkItemAcceptance": function(target, source, position) {
            return (
                source._ready && (
                    position != "over" ||
                    this.tree.model.mayHaveChildren(
                        dijit.getEnclosingWidget(target).item
                    )
                )
            );
            /* code in match_set.js makes sure that source._ready gets set true
             * only when we want the item to be draggable */
        },
        "itemCreator": function(nodes) {
            var default_items = this.inherited(arguments);
            for (var i = 0; i < default_items.length; i++)
                default_items[i].match_point = nodes[i].match_point;
            return default_items;
        }
    }
);
