dojo.require("openils.PermaCrud");
dojo.require("dojo.data.ItemFileReadStore");

if (typeof(localeStrings) == "undefined") {
    dojo.requireLocalization("openils.acq", "acq");
    var localeStrings = dojo.i18n.getLocalization("openils.acq", "acq");
}

function TagManager(displayNode) {
    var self = this;
    this.tagCache = {};
    this.displayNode = displayNode;

    this.pcrud = new openils.PermaCrud();

// selected (by checkbox) id's from an autogrid of objects:
//        return grid.getSelectedItems().map(function(o) { return o.id[0]; });

    this.displayFund = function(fund) {
        if (!fund) {
            this.displayNode.innerHTML = localeStrings.FUND_NOT_YET_LOADED;
            return;
        }

        dojo.empty(this.displayNode);
        fund.tags().forEach(
            function(o) {
                dojo.place(self.renderTagMapping(o), self.displayNode, "last");
            }
        );
    };

    this.renderTagMapping = function(mapping) {
        var span = dojo.create(
            "span", {
                "id": "oils-acq-fund-tag-mapping-" + mapping.id(),
                "className": "oils-acq-fund-tag",
                "innerHTML": mapping.tag().name()
            }
        );
        dojo.create(
            "a", {
                "href": "javascript:void(0);",
                "innerHTML": "X",
                "onclick": function() { self.deleteMapping(mapping); },
            },
            span, "last"
        );
        return span;
    };

    this.deleteMapping = function(mapping) {
        if (confirm(localeStrings.CONFIRM_DELETE_MAPPING)) {
            this.pcrud.eliminate(
                mapping, {
                    "oncomplete": function(r) {
                        dojo.destroy(
                            "oils-acq-fund-tag-mapping-" + mapping.id()
                        );
                        fund.tags(
                            fund.tags().filter(
                                function(o) { return o.id() != mapping.id(); }
                            )
                        );
                    },
                    "onerror": function() {
                        /* XXX does onerror not actually work? */
                        alert(localeStrings.COULD_NOT_DELETE_MAPPING);
                    }
                }
            );
        }
    };

    this.addMapping = function(fund, tag) {
        var mapping = new acqftm();
        mapping.fund(fund.id());
        mapping.tag(tag.id());

        this.pcrud.create(
            mapping, {
                "onerror": function(r) {
                    /* XXX does onerror not actually work? */
                    alert(localeStrings.COULD_NOT_CREATE_MAPPING);
                },
                "oncomplete": function(r, list) {
                    mapping = list[0]; /* get the new mapping's ID this way */
                    mapping.tag(tag); /* re-"flesh" */
                    fund.tags().push(mapping); /* save local reference */
                    dojo.place(
                        self.renderTagMapping(mapping),
                        self.displayNode, "last"
                    );
                }
            }
        );
    };

    this.prepareTagSelector = function(selector) {
        this.pcrud.search(
            "acqft", {
                "owner": fieldmapper.aou.orgNodeTrail(
                    fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()),
                    true /* asId */
                )
            }, {
                "async": true,
                "oncomplete": function(r) {
                    if ((r = openils.Util.readResponse(r))) {
                        selector.store = new dojo.data.ItemFileReadStore(
                            {"data": acqft.toStoreData(r)}
                        );
                        selector.startup();
                    }
                }
            }
        );
    };
}
