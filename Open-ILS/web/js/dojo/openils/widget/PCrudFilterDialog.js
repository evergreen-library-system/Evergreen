if (!dojo._hasResource["openils.widget.PCrudFilterDialog"]) {
    dojo.provide("openils.widget.PCrudFilterDialog");
    dojo.require("openils.widget.PCrudFilterPane");
    dojo.require("dijit.Dialog");

    dojo.declare(
        "openils.widget.PCrudFilterDialog", [
            dijit.Dialog, openils.widget.PCrudFilterPane
        ]
    );
}
