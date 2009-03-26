dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('openils.Util');
dojo.require('openils.User');

var evtCache = {};

function init() {
    var store = new dojo.data.ItemFileWriteStore({data:acqf.initStoreData()});
    evtGrid.setStore(store);
    evtGrid.render();

    function onResponse(r) {
        var evt = openils.Util.readResponse(r);
        evtCache[evt.id()] = evt;
        evtGrid.store.newItem(evt.toStoreItem()); 
    }

    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.events.circ'],
        {   async: true,
            params: [openils.User.authtoken, patronId],
            onresponse : onResponse
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.events.ahr'],
        {   async: true,
            params: [openils.User.authtoken, patronId],
            onresponse : onResponse
        }
    );
}

function getField(rowIdx, item) {
    if(!item) return '';
    var evt = evtCache[this.grid.store.getValue(item, 'id')];

    switch(this.field) {
        case 'reactor':
            return evt.event_def().reactor().module();
        case 'validator':
            return evt.event_def().validator().module();
        case 'hook':
            return evt.event_def().hook();
        case 'target':
            switch(evt.target().classname) {
                case 'circ':
                    return evt.target().target_copy().barcode();
                case 'ahr':
                    if(evt.target().currrent_copy())
                        return evt.target().currrent_copy().barcode();
            }
            
    }

    return this.grid.store.getValue(item, this.field) || '';
}

function evtCancelSelected() {
    var selected = evtGrid.selection.getSelected();
    if(selected.length == 0) return;
    var eventIds = selected.map(
        function(item) { return evtGrid.store.getValue(item, 'id') } );
    alert(eventIds);
    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.event.cancel.batch'],
        {   async: true,
            params: [openils.User.authtoken, eventIds],
            oncomplete : init
        }
    );
}

openils.Util.addOnLoad(init);

