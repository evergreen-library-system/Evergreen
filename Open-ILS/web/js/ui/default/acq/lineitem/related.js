dojo.require("openils.acq.Lineitem");
dojo.require("openils.Util");
dojo.require("openils.XUL");
dojo.require("openils.CGI");
dojo.require("openils.PermaCrud");
dojo.require('openils.BibTemplate');
dojo.require('fieldmapper.OrgUtils');

var liTable;
var identTarget;
var bibRecord;
var paramPL;
var paramPO;

function fetchLi() {
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve"], {
            "async": true,
            "params": [openils.User.authtoken, targetId, {
                "flesh_attrs": true,
                "flesh_li_details": true,
                "flesh_fund_debit": true,
                "flesh_cancel_reason": true
            }],
            "oncomplete": function(r) {
                fetchBib();
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

function fetchBib() {
    new openils.BibTemplate({ 
        record : targetId, 
        org_unit : fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()).shortname()
    }).render();

    new openils.PermaCrud().retrieve('bre', targetId, {
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
                "async": true,
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
            liTable._loadPLSelect(paramPL);
            acqLitSavePlDialog.show();
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
    liTable.reset();
    liTable._isRelatedViewer = true;

    prepareButtons();
    fetchRelated();
}

openils.Util.addOnLoad(load);
