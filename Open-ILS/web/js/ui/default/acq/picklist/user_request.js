dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.widget.AutoGrid');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.EditPane');
dojo.require("dijit.layout.StackContainer");
dojo.require('openils.PermaCrud');
dojo.requireLocalization("openils.acq", "acq");

var contextOrg;
var aur_obj;
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

function setup() {
    if(reqId) {
        drawRequest();
    } else {
        drawList();
    }
}

function drawRequest() {
    var pcrud = new openils.PermaCrud({ authtoken : openils.User.authtoken });
    aur_obj = pcrud.retrieve('aur',reqId);

    // hide the grid and the context selector
    dijit.byId('stackContainer').forward();

    // toggle the View Picklist/Add to Picklist button label
    if (aur_obj.lineitem()) {
        openils.Util.hide( 'add_to_picklist' );
        openils.Util.show( 'view_picklist' );
    } else {
        openils.Util.hide( 'view_picklist' );
        openils.Util.show( 'add_to_picklist' );
    }

    // draw a detail page for a particular request
    var div = document.getElementById('detail_content_pane');
    while (div.lastChild) { div.removeChild( div.lastChild ); }
    var pane = new openils.widget.EditPane({ 
        fmObject : aur_obj,
        readOnly : true
    });
    pane.domNode = div;
    pane.hideActionButtons = true;
    pane.startup();

    // including ability to add request to a picklist
    // and to "reject" it (aka apply a cancel reason)

    dojo.byId("acq-ur-cancel-reason").innerHTML = '';
    var widget = new openils.widget.AutoFieldWidget({
        "fmField": "cancel_reason",
        "fmClass": "aur",
        "parentNode": dojo.byId("acq-ur-cancel-reason"),
        "orgLimitPerms": ["CREATE_PURCHASE_REQUEST"],
        "forceSync": true
    });

    widget.build(
        function(w, ww) {
            acqUrCancelReasonSubmit.onClick = function() {
                if (w.attr("value")) {
                    if (confirm( localeStrings.UR_CANCEL_CONFIRM )) {
                        fieldmapper.standardRequest(
                            [ 'open-ils.acq', 'open-ils.acq.user_request.cancel.batch' ],
                            {   async: true,
                                params: [openils.User.authtoken, [reqId], w.attr("value")],
                                oncomplete: function(r) {
                                    location.href = location.href; // kludge to reload the interface
                                }
                            }
                        );
                    }
                }
            };
        }
    );
}

function fooPicklist() {
    if (aur_obj.lineitem()) {
        viewPicklist();
    } else {
        addToPicklist();
    }
}

function viewPicklist() {
    var lineitem = fieldmapper.standardRequest(
        [ 'open-ils.acq', 'open-ils.acq.lineitem.retrieve.authoritative' ],
        {
            params: [openils.User.authtoken, aur_obj.lineitem()]
        }
    );
    location.href = oilsBasePath + "/acq/picklist/view/" + lineitem.picklist();
}

function fooPicklist() {
    if (aur_obj.lineitem()) {
        viewPicklist();
    } else {
        addToPicklist();
    }
}

function viewPicklist() {
    var lineitem = fieldmapper.standardRequest(
        [ 'open-ils.acq', 'open-ils.acq.lineitem.retrieve' ],
        {
            params: [openils.User.authtoken, aur_obj.lineitem()]
        }
    );
    location.href = oilsBasePath + "/acq/picklist/view/" + lineitem.picklist();
}

function addToPicklist() {
    // reqId, from detail view
    location.href = oilsBasePath + "/acq/picklist/brief_record?ur=" + reqId + "&prepop=" + encodeURIComponent(js2JSON({
        "1": aur_obj.title() || aur_obj.article_title() || aur_obj.volume(),
        "2": aur_obj.author(),
        "5": aur_obj.isxn(),
        "9": aur_obj.publisher(),
        "10": aur_obj.pubdate()
    }));
}

function setNoHold() {
    // reqId, from detail view
    fieldmapper.standardRequest(
        [ 'open-ils.acq', 'open-ils.acq.user_request.set_no_hold.batch' ],
        {   async: true,
            params: [openils.User.authtoken, [reqId]],
            oncomplete: function(r) {
                location.href = location.href; // kludge to reload the interface
            }
        }
    );
}

// format the title data as id:title
function getTitle(idx, item) {
    if(item) {
        return this.grid.store.getValue(item, 'id') + ':' + 
        this.grid.store.getValue(item, 'title');
    }
    return '';
}

// turn id:title into a url
function formatTitle(value) {
    if(value) {
        var parts = value.split(/:/);
        return '<a href="' + oilsBasePath + 
            '/acq/picklist/user_request/' + parts[0] + '">' + parts[1] + '</a>';
    }
}

function drawList() {
    buildGrid();

    var connect = function() {
        dojo.connect(contextOrgSelector, 'onChange',
            function() {
                contextOrg = this.attr('value');
                rGrid.resetStore();
                buildGrid();
            }
        );
    };

    new openils.User().buildPermOrgSelector(
        'CREATE_PICKLIST', contextOrgSelector, null, connect);
}

function buildGrid() {

    if(contextOrg == null)
        contextOrg = openils.User.user.ws_ou();

    rGrid.loadAll(
        {   order_by : {aur : 'request_date'},
            join : 'au' 
        },
        {
            cancel_reason : null,
            '+au' : {
                home_ou : fieldmapper.aou.descendantNodeList(contextOrg).map(
                    function(item) { return item.id(); })
            }
        }
    );
}

openils.Util.addOnLoad(setup);


