dojo.provide("openils.vandelay.TreeDndSource");
dojo.require("dijit._tree.dndSource");

/* This class specifically serves the eg/vandelay/match_set interface
 * for editing Vandelay Match Set trees.  It should probably  have a more
 * specific name that reflects that.
 */
dojo.declare(
    "openils.vandelay.TreeDndSource", dijit._tree.dndSource, {
        "_is_replaceable": function(src_item, target_item) {
            /* An OP can replace anything, but non-OPs can only replace other
             * non-OPs
             */
            console.log("src item: " + src_item + " target item: " + target_item);
            return true;    /* XXX TODO FINISHME */
        },
        "constructor": function() {
            /* Given a tree object, there seems to be no way to access its
             * dndController, which seems to be the only thing that knows
             * about a tree's selected nodes.  So we register instances
             * in a global variable in order to find them later. :-(
             */
            if (!window._tree_dnd_controllers)
                window._tree_dnd_controllers = [];

            window._tree_dnd_controllers.push(this);
        },
        "checkItemAcceptance": function(target, source, position) {
            if (!source._ready || source == this) return;

            if (this.tree.model._replace_mode) {
                return (
                    position == "over" && this._is_replaceable(
                        source.getAllNodes()[0].match_point,
                        dijit.getEnclosingWidget(target).item.match_point
                    )
                );
            } else {
                return (
                    position != "over" ||
                    this.tree.model.mayHaveChildren(
                        dijit.getEnclosingWidget(target).item
                    )
                );
            }
            /* code in match_set.js makes sure that source._ready gets set true
             * only when we want the item to be draggable */
        },
        "itemCreator": function(nodes, somethingelse) {
            console.log("gew: " + dijit.getEnclosingWidget(somethingelse).item.name);
            console.log("dojo.dnd.manager.copy: " + dojo.dnd.manager.copy);
            var default_items = this.inherited(arguments);
            for (var i = 0; i < default_items.length; i++)
                default_items[i].match_point = nodes[i].match_point;
            return default_items;
        }
    }
);
