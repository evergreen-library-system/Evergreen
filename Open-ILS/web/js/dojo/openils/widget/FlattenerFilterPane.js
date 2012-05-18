if (!dojo._hasResource["openils.widget.FlattenerFilterPane"]) {
    dojo._hasResource["openils.widget.FlattenerFilterPane"] = true;

    dojo.provide("openils.widget.FlattenerFilterPane");
    dojo.require("openils.widget.PCrudFilterPane");

    dojo.declare(
        "openils.widget.FlattenerFilterPane",
        [openils.widget.PCrudFilterPane], {
            "mapTerminii": null,

            "constructor": function(args) {
                dojo.mixin(this, args);
            },

            "_buildFieldStore": function() {
                var self = this;

                if (!this.mapTerminii)
                    throw new Error("No mapTerminii list; can't proceed");

                var realFieldList = dojo.clone(this.mapTerminii).filter(
                    function(o) {
                        if (self.suppressFilterFields &&
                            dojo.indexOf(
                                self.suppressFilterFields, o.simple_name
                            ) >= -1
                        ) {
                            return false;
                        }

                        return o.isfilter;
                    }
                );

                this.fieldStore = new dojo.data.ItemFileReadStore({
                    "data": {
                        "identifier": "simple_name",
                        "name": "label",
                        "items": realFieldList.map(
                            function(item) {
                                return {
                                    "label": item.label,
                                    "name": item.name,
                                    "type": item.datatype,
                                    "fmClass": item.fmClass,
                                    "simple_name": item.simple_name,
                                    "indirect": item.indirect
                                };
                            }
                        )
                    }
                });
            }
        }
    );
}
