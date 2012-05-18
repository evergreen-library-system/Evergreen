if (!dojo._hasResource["openils.widget.FlattenerFilterDialog"]) {
    dojo.provide("openils.widget.FlattenerFilterDialog");
    dojo.require("openils.widget.FlattenerFilterPane");
    dojo.require("dijit.Dialog");

    dojo.declare(
        "openils.widget.FlattenerFilterDialog", [
            dijit.Dialog, openils.widget.FlattenerFilterPane
        ]
    );
}
