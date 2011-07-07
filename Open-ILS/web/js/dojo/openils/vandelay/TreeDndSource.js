dojo.provide("openils.vandelay.TreeDndSource");
dojo.require("dijit._tree.dndSource");

/* This class specifically serves the eg/vandelay/match_set interface
 * for editing Vandelay Match Set trees.  It should probably  have a more
 * specific name that reflects that.
 */
dojo.declare(
    "openils.vandelay.TreeDndSource", dijit._tree.dndSource, {
        "_is_replaceable": function(spoint, dpoint, disroot) {
            /* An OP can replace anything, but non-OPs can only replace other
             * non-OPs.
             */
            if (spoint.bool_op())
                return true;
            else if (!dpoint.bool_op())
                return true;
            return false;
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

            dojo.connect(
                this.tree.model.store, "onNew", this,
                function() { this.redraw_expression_preview(); }
            );
            dojo.connect(
                this.tree.model.store, "onDelete", this,
                function() { this.redraw_expression_preview(); }
            );
        },
        "redraw_expression_preview": function() {
            if (typeof(window.redraw_expression_preview) == "function") {
                window.redraw_expression_preview();
            } else {
                console.log("no redraw_expression_preview function registered");
            }
        },
        "checkItemAcceptance": function(target, source, position) {
            if (!source._ready || source == this) return;

            if (this.tree.model.replace_mode) {
                var ditem = dijit.getEnclosingWidget(target).item;
                return (
                    position == "over" && this._is_replaceable(
                        source.getAllNodes()[0].match_point,
                        this.tree.model.store.getValue(ditem, "match_point"),
                        ditem === this.tree.model.root
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
            var default_items = this.inherited(arguments);
            for (var i = 0; i < default_items.length; i++)
                default_items[i].match_point = nodes[i].match_point;
            return default_items;
        },
        "onDndDrop": function(source, nodes, copy) {
            if (
                !this.tree.model.replace_mode ||
                this.containerState != "Over" ||
                this.dropPosition == "Before" ||
                this.dropPosition == "After" ||
                source == this
            ) {
                return this.inherited(arguments);
            }

            /* This method only comes into play for our "replace mode" */

            var target_widget = dijit.getEnclosingWidget(this.targetAnchor);
            var new_params = this.itemCreator(nodes, this.targetAnchor)[0];

            /* Here, we morph target_widget.item into the new item */

            var store = this.tree.model.store;
            var item = target_widget.item;
            for (var k in new_params) {
                if (k == "id") continue;    /* can't use this / don't need it */
                store.setValue(item, k, new_params[k]);
            }
            if (this.tree.model.root === item) {    /* replacing root node */
                if (!new_params.match_point.bool_op()) {
                    /* If we're here, we've replaced the root node with
                     * something that isn't a bool op, so we need to nuke
                     * any children that the item has.
                     */
                    store.setValue(item, "children", []);
                }
            }
            if (typeof(window.render_vmsp_label) == "function") {
                store.setValue(
                    item,
                    "name",
                    window.render_vmsp_label(new_params.match_point)
                );
            }

            this.redraw_expression_preview();

            /* just because this is at the end of the default implementation: */
            this.onDndCancel();
        }
    }
);
