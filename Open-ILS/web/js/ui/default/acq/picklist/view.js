dojo.require('dojo.date.stamp');
dojo.require('dojo.date.locale');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('dijit.layout.ContentPane');

var plist;
var plOffset = 0;
var plLimit = 20;
var liTable;


function load() {
    liTable = new AcqLiTable();
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, plId, 
                {flesh_lineitem_count:true, flesh_owner:true}],
            oncomplete: function(r) {
                plist = openils.Util.readResponse(r);
                drawPl(plist);
            }
        }
    );

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
                {flesh_attrs:true, clear_marc:true, offset:plOffset, limit:plLimit}],
            onresponse: function(r) {
                liTable.showTable();
                liTable.addLineitem(openils.Util.readResponse(r));
            }
        }
    );
}

openils.Util.addOnLoad(load);


