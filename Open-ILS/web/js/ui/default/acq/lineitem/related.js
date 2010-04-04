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

function addLi(fields) {

    var li = new fieldmapper.jub();
    li.marc(bibRecord.marc());
    li.eg_bib_id(bibRecord.id());
    if(fields.picklist) li.picklist(fields.picklist);
    if(fields.po) li.po(fields.po);
    li.selector(openils.User.user.id());
    li.creator(openils.User.user.id());
    li.editor(openils.User.user.id());

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.create'],
        {   async : true,
            params : [openils.User.authtoken, li],
            oncomplete : function(r) {
                var id = openils.Util.readResponse(r);
                if(!id) return;
                if(fields.picklist) 
                    location.href = oilsBasePath + '/acq/picklist/view/' + fields.picklist;
                else
                    location.href = oilsBasePath + '/acq/po/view/' + fields.po;
            }
        }
    );
}

function loadPl() {

    if(paramPL) {

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
            {   async: true,
                params: [openils.User.authtoken, paramPL], 
                oncomplete : function(r) {
                    var pl = openils.Util.readResponse(r);
                    plSelector.store = 
                        new dojo.data.ItemFileReadStore({data:fieldmapper.acqpl.toStoreData([pl])});
                    plSelector.attr('value', pl.name());
                    plSelector.attr('disabled', true);
                }
            }
        );

    } else {

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.picklist.user.retrieve.atomic'],
            {   async: true,
                params: [openils.User.authtoken], 
                oncomplete : function(r) {
                    var list = openils.Util.readResponse(r);
                    plSelector.store = 
                        new dojo.data.ItemFileReadStore({data:fieldmapper.acqpl.toStoreData(list)});
                }
            }
        );
    }
}


function load() {
    var cgi = new openils.CGI();

    identTarget = cgi.param('target');
    paramPL = cgi.param('pl');
    paramPO = cgi.param('po');

    loadPl();

    if(identTarget == 'bib') {
        fetchBib();
    } else {
        fetchLi(); 
    }

    liTable = new AcqLiTable();
    liTable.reset();
    liTable._isRelatedViewer = true;

    fetchRelated();
}

openils.Util.addOnLoad(load);
