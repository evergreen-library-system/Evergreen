if (!dojo._hasResource["openils.widget.FlattenerFilterDialog"]) {
    dojo.provide("openils.widget.FlattenerFilterDialog");
    dojo.require("openils.widget.FlattenerFilterPane");
    dojo.require("dijit.Dialog");

    dojo.declare(
        "openils.widget.FlattenerFilterDialog", [
            dijit.Dialog, openils.widget.FlattenerFilterPane
        ], {
            "constructor": function() {
                dojo.connect(
                    this, "postCreate", this,
                    function() {
                        /* Of course I don't *want* to hardcode 400px below,
                         * but without some kind of maxHeight, this dialog
                         * can just grow forever, until it's no longer
                         * possible to access the close button on the top or
                         * the buttons at the bottom. */
                        dojo.style(
                            this.domNode, {
                                "maxHeight": "400px", "overflow": "auto"
                            }
                        );
                    }
                );
            }
        }
    );
}
