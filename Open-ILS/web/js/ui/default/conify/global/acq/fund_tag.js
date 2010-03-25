dojo.require("dojo.data.ItemFileWriteStore");
dojo.require("dojox.grid.DataGrid");
dojo.require("dojox.grid.cells.dijit");
dojo.require("dojox.widget.PlaceholderMenuItem");
dojo.require("dijit.form.CurrencyTextBox");
dojo.require("dijit.form.FilteringSelect");
dojo.require("openils.widget.AutoGrid");
dojo.require("openils.PermaCrud");
dojo.require("openils.widget.OrgUnitFilteringSelect");

var pcrud;
var ftOwner;
var ftList;

function ftInit() {
    new openils.User().buildPermOrgSelector(
        "ADMIN_ACQ_FUND_TAG",
        ftOwnerSelect,
        null,
        function() {
            dojo.connect(
                ftOwnerSelect,
                "onChange",
                function() {
                    ftOwner = this.getValue();
                    ftGrid.resetStore();
                    buildFtGrid();
                }
            );
        }
    );
}

function buildFtGrid() {
    if (!pcrud) pcrud = new openils.PermaCrud();
    if (!ftOwner) ftOwner = openils.User.user.ws_ou();

    pcrud.search(
        "acqft",
        {"owner": fieldmapper.aou.fullPath(ftOwner, true /* asId */)},
        {
            "async": true,
            "oncomplete": function(r) {
                if ((ftList = openils.Util.readResponse(r))) {
                    ftList = openils.Util.objectSort(ftList);
                    ftList.forEach(
                        function(o) {
                            ftGrid.store.newItem(acqft.toStoreItem(o));
                        }
                    );
                }
            }
        }
    );
}

openils.Util.addOnLoad(ftInit);
