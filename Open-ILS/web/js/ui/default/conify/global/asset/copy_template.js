dojo.require("dojo.data.ItemFileWriteStore");
dojo.require("dijit.form.CurrencyTextBox");
dojo.require("dijit.form.FilteringSelect");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.PermaCrud");
dojo.require("openils.widget.OrgUnitFilteringSelect");

var pcrud;
var actOwner;
var actList;

function actInit() {
    pcrud = new openils.PermaCrud();

    new openils.User().buildPermOrgSelector(
        "ADMIN_ASSET_COPY_TEMPLATE",
        actOwnerSelect,
        null,
        function() {
            dojo.connect(
                actOwnerSelect,
                "onChange",
                function() {
                    actOwner = fieldmapper.aou.findOrgUnit(this.attr("value"));
                    actGrid.resetStore();
                    buildActGrid();
                }
            );
            buildActGrid();
        }
    );
}

function buildActGrid() {
    if (!actOwner)
        actOwner = fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou());

    pcrud.search(
        "act", {
            "owning_lib": fieldmapper.aou.orgNodeTrail(actOwner, true /* asId */)
        }, {
            "async": true,
            "onresponse": function(r) {
                if ((actList = openils.Util.readResponse(r))) {
                    actList = openils.Util.objectSort(actList);
                    actList.forEach(
                        function(o) {
                            actGrid.store.newItem(act.toStoreItem(o));
                        }
                    );
                }
            },
            "oncomplete": function() {
                actGrid.hideLoadProgressIndicator();
            }
        }
    );
}

openils.Util.addOnLoad(actInit);
