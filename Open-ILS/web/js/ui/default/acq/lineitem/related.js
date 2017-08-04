dojo.require("openils.acq.Lineitem");
dojo.require("openils.Util");
dojo.require("openils.XUL");
dojo.require("openils.CGI");
dojo.require("openils.PermaCrud");
dojo.require('openils.BibTemplate');
dojo.require('openils.widget.PCrudAutocompleteBox');
dojo.require('fieldmapper.OrgUtils');

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var liTable;
var identTarget;
var bibRecord;
var paramPL;
var paramPO;

function fetchLi() {
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve.authoritative"], {
            "async": true,
            "params": [openils.User.authtoken, targetId, {
                "flesh_attrs": true,
                "flesh_li_details": true,
                "flesh_fund_debit": true,
                "flesh_cancel_reason": true
            }],
            "oncomplete": function(r) {
                var li = openils.Util.readResponse(r);
                fetchBib(li.eg_bib_id());
            }
        }
    );
}


function fetchRelated() {
    var method = 'open-ils.acq.lineitems_for_bib.by_lineitem_id';
    if(identTarget == 'bib')
        var method = 'open-ils.acq.lineitems_for_bib.by_bib_id';

    var total = 0;
    fieldmapper.standardRequest(
        ["open-ils.acq", method], {
            "async": true,
            "params": [openils.User.authtoken, targetId, {
                "flesh_attrs": true,
                "flesh_notes": true,
                "flesh_cancel_reason": true
            }],
            "onresponse": function(r) {
                var resp = openils.Util.readResponse(r);
                if (resp) {
                    total++;
                    liTable.show("list");
                    liTable.addLineitem(resp);
                }
            }
        }
    );
}

function fetchBib(bibId) {
    bibId = bibId || targetId;
    new openils.BibTemplate({ 
        record : bibId, 
        org_unit : fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()).shortname()
    }).render();

    new openils.PermaCrud().retrieve('bre', bibId, {
        oncomplete : function(r) {
            bibRecord = openils.Util.readResponse(r);
            // render bib details
            // perhaps we just pull these from the beating heart of bibtemplate
        }
    }) 
}

function createLi(oncomplete) {
    return function() {
        progressDialog.show();
        liTable.reset();
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.biblio.create_by_id"], {
                "params": [
                    openils.User.authtoken, [bibRecord.id()], {
                        "flesh_attrs": true,
                        "flesh_cancel_reason": true,
                        "flesh_notes": true
                    }
                ],
                "async": false,
                "onresponse": function(r) {
                    var li = openils.Util.readResponse(r);
                    if (typeof(li) == "object") {
                        liTable.show("list");
                        liTable.addLineitem(li);
                        dojo.query(
                            "input[name='selectbox']", liTable._findLiRow(li)
                        )[0].checked = true;
                    }
                },
                "oncomplete": function() {
                    progressDialog.hide();
                    oncomplete();
                }
            }
        );
    };
}

function prepareButtons() {
    addToPlButton.onClick = createLi(
        function() { /* oncomplete */
            acqLitSavePlDialog.show();
        }
    );
    addToPoButton.onClick = createLi(
        function() { /* oncomplete */
            addToPoDialog.show();
        }
    );
    createPoButton.onClick = createLi(
        function() { /* oncomplete */
            liTable._loadPOSelect();
            acqLitPoCreateDialog.show();
        }
    );
}

function load() {
    var cgi = new openils.CGI();

    identTarget = cgi.param('target');
    paramPL = cgi.param('pl');
//    paramPO = cgi.param('po');

    if (identTarget == 'bib') {
        fetchBib();
    } else {
        fetchLi(); 
    }

    liTable = new AcqLiTable();
    liTable.enableActionsDropdownOptions("vp");
    liTable.reset();
    liTable._isRelatedViewer = true;

    // render the batch updater to activate fund selection, but leave
    // it hidden for now since it's not fully functional in this UI.
    liTable.initBatchUpdater(null, true);

    prepareButtons();
    fetchRelated();

    /* addToPoDialog now requires this function be defined to tell it what
     * lineitem IDs to add to the PO.  Part of making it reusable in more
     * places. */
    addToPoDialog._get_li = function() {
        return liTable.getSelected()[0].id();
    };
}

openils.Util.addOnLoad(load);
