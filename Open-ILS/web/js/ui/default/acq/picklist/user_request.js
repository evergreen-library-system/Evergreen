dojo.require('openils.CGI');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.widget.AutoGrid');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.EditPane');
dojo.require("dijit.layout.StackContainer");
dojo.require('openils.PermaCrud');
dojo.requireLocalization("openils.acq", "acq");
dojo.require('openils.acq.Lineitem');

var contextOrg;
var contextUsr;
var contextUsrObj;
var contextLI;
var contextEg_bib;
var aur_obj;
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');
var cgi = new openils.CGI();

function setup() {

    changeBib(cgi.param('eg_bib'));
    changeLI(cgi.param('lineitem'));

    if (cgi.param('usr')) {
        var usr_obj = fieldmapper.standardRequest(
            [
                'open-ils.actor',
                'open-ils.actor.user.fleshed.retrieve.authoritative'
            ],
            {
                params: [openils.User.authtoken, cgi.param('usr')]
            }
        );
        if (typeof usr_obj.textcode == 'undefined') {
            contextUsrObj = usr_obj;
            changeUser(usr_obj.id(),usr_obj.card().barcode());
        } else {
            alert(usr_obj.textcode + ' : ' + usr_obj.desc);
        }
    }

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

    // purge any previous lineitem display
    // FIXME: I thought it would be cool to have this, but I can't get it 
    // to look right with our dojo div/contentPanes.  So just testing for
    // a DOM hook for now.
    if (dojo.byId('lineitem')) {
        //openils.Util.hide( 'lineitem_container' );
        dojo.byId('lineitem').innerHTML = '';
    }

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

    // lineitem summary
    if (dojo.byId('lineitem') && aur_obj.lineitem()) {
        //openils.Util.show( 'lineitem_container' );
        openils.acq.Lineitem.fetchAndRender(aur_obj.lineitem(), {},
            function(li, html) {
                dojo.byId('lineitem').innerHTML = html;
            }
        );
    }

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

    var query = {
        cancel_reason : null,
        '+au' : {
            home_ou : fieldmapper.aou.descendantNodeList(contextOrg).map(
            function(item) { return item.id(); })
        }
    };

    if (contextUsr) {
        delete query['+au']['home_ou'];
        query['+au']['id'] = contextUsr;
    }

    if (contextEg_bib) {
        query['eg_bib'] = contextEg_bib;
    }

    if (contextLI) {
        query['lineitem'] = contextLI;
    }

    rGrid.resetStore();
    rGrid.loadAll(
        {   order_by : {aur : 'request_date'},
            join : 'au' 
        },
        query
    );
}

function changeBib(value) {
    contextEg_bib = value;
    rGrid.overrideEditWidgets.eg_bib = new dijit.form.TextBox({"disabled": true});
    rGrid.overrideEditWidgets.eg_bib.shove = { create : contextEg_bib };
}

function changeLI(value,display_value) {
    contextLI = value;
    contextLITextbox.setValue( contextLI );
    contextLITextbox.setDisplayedValue( display_value || contextLI );
    rGrid.overrideEditWidgets.lineitem = new dijit.form.TextBox({"disabled": true});
    rGrid.overrideEditWidgets.lineitem.shove = { create : contextLI };
}

function changeLIPrompt() {
    var lineitem = window.prompt(localeStrings.UR_FILTER_LINEITEM);
    if(lineitem != '' && (lineitem == null || Number(lineitem) == NaN)) {
        return;
    }
    changeLI(lineitem);
    buildGrid();
}

function changeUser(value,display_value) {
    contextUsr = value;
    contextUsrTextbox.setValue( contextUsr );
    contextUsrTextbox.setDisplayedValue( display_value || contextUsr );
    rGrid.overrideEditWidgets.usr = new dijit.form.TextBox({"disabled": true});
    rGrid.overrideEditWidgets.usr.shove = { create : contextUsr };
}

function changeUserPrompt() {
    var barcode = window.prompt(localeStrings.UR_FILTER_USER);
    if(barcode == null) {
        return;
    }
    if(typeof xulG != 'undefined' && xulG.get_barcode) {
        // We have a "complete the barcode" function, call it (actor = users only)
        var new_barcode = xulG.get_barcode(window, 'actor', barcode);
        // If we got a result (boolean false is "no result") check it
        if(new_barcode) {
            // user_false string means they picked "None of the above"
            // Abort before any other events can fire
            if(new_barcode == "user_false") return;
            // No error means we have a (hopefully valid) completed barcode to use.
            // Otherwise, fall through to other methods of checking
            if(typeof new_barcode.ilsevent == 'undefined')
                barcode = new_barcode.barcode;
        }
    }
    if (barcode == '') {
        contextUsrObj = null;
        changeUser('','');
    } else {
        var usr_obj = fieldmapper.standardRequest(
            [
                'open-ils.actor',
                'open-ils.actor.user.fleshed.retrieve_by_barcode.authoritative'
            ],
            {
                params: [openils.User.authtoken, barcode]
            }
        );
        if (typeof usr_obj.textcode != 'undefined') {
            alert(usr_obj.textcode + ' : ' + usr_obj.desc);
            return;
        } else {
            contextUsrObj = usr_obj;
            changeUser(usr_obj.id(),usr_obj.card().barcode());
        }
    }
    buildGrid();
}

function createRequest() {
    if (!contextUsr) {
        changeUserPrompt();
    }
    if (contextUsr) {
        rGrid.overrideEditWidgets.pickup_lib = new dijit.form.TextBox({"disabled": true});
        rGrid.overrideEditWidgets.pickup_lib.shove = { create : contextUsrObj.home_ou() };
        rGrid.showCreateDialog();
    }
}

openils.Util.addOnLoad(setup);


