dojo.require('dojo.date.stamp');
dojo.require('dojo.date.locale');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.CGI');
dojo.require('dijit.layout.ContentPane');

var plist;
var plOffset = 0;
var plLimit = 20;
var liTable;


function load() {
    liTable = new AcqLiTable();
    liTable.isPL = plId;
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.retrieve.authoritative'],
        {   async: true,
            params: [openils.User.authtoken, plId, 
                {flesh_lineitem_count:true, flesh_owner:true}],
            oncomplete: function(r) {
                plist = openils.Util.readResponse(r);
                drawPl(plist);
            }
        }
    );

    /* if we got here from the search/invoice page with a focused LI,
     * return to the previous page with the same LI focused */
    var cgi = new openils.CGI();
    var source = cgi.param('source');
    var focus_li = cgi.param('focus_li');
    if (source && focus_li) {
        dojo.forEach(
            ['search', 'invoice'], // perhaps a wee bit too loose
            function(srcType) {
                if (source.match(new RegExp(srcType))) {
                    openils.Util.show('acq-pl-return-to-' + srcType);
                    var newCgi = new openils.CGI({url : source});
                    newCgi.param('focus_li', cgi.param('focus_li'));
                    dojo.byId('acq-pl-return-to-' + srcType + '-button').onclick = function() {
                        location.href = newCgi.url();
                    }
                }
            }
        );
    }
}

function drawPl() {

    dojo.byId("oils-acq-picklist-name").innerHTML = plist.name();
    dojo.byId("oils-acq-picklist-attr-owner").innerHTML = plist.owner().usrname();
    dojo.byId("oils-acq-picklist-attr-count").innerHTML = plist.entry_count();

    dojo.byId("oils-acq-picklist-attr-cdate").innerHTML =
         dojo.date.locale.format(
            dojo.date.stamp.fromISOString(plist.create_time()), 
            {selector:'date'}
        );

    dojo.byId("oils-acq-picklist-attr-edate").innerHTML = 
         dojo.date.locale.format(
            dojo.date.stamp.fromISOString(plist.edit_time()), 
            {selector:'date'}
        );

    loadLIs();
}

function loadLIs() {
    liTable.reset();

    if(plist.entry_count() > (plOffset + plLimit)) {
        liTable.setNext(
            function() { 
                plOffset += plLimit;
                loadLIs();
            }
        );
    } else {
        liTable.setNext(null);
    }

    if(plOffset > 0) {
        liTable.setPrev(
            function() { 
                plOffset -= plLimit;
                loadLIs();
            }
        );
    } else {
        liTable.setPrev(null);
    }


    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.picklist.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, plId, 
                {flesh_notes:true, flesh_cancel_reason:true, flesh_attrs:true, clear_marc:true, offset:plOffset, limit:plLimit}],
            onresponse: function(r) {
                var li = openils.Util.readResponse(r);
                if (li) { /* Not every response is an LI (for some reason) */
                    liTable.addLineitem(li);
                    liTable.show('list');
                }
            }
        }
    );
}

openils.Util.addOnLoad(load);


