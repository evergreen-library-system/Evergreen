dojo.require('openils.widget.AutoGrid');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('dijit.form.DateTextBox');
dojo.require('dojo.date.stamp');

var eventState;
var eventContextOrg;
var eventList;
var eventStartDateRange;
var eventEndDateRange;

function eventInit() {
    try {
        buildStateSelector();
        buildOrgSelector();
        buildDatePickers();
        eventGrid.resetStore();
        buildEventGrid();

        eventGrid.cancelSelected = function() { doSelected('open-ils.acq.purchase_order.event.cancel.batch') };
        eventGrid.resetSelected = function() { doSelected('open-ils.acq.purchase_order.event.reset.batch') };
        eventGrid.doSearch = function() {
            buildEventGrid();
        }

    } catch(E) {
        //dump('Error in acq/events.js, eventInit(): ' + E);
        throw(E);
    }
}

function buildDatePickers() {
    var today = new Date(); 
    var yesterday = new Date( today.getFullYear(), today.getMonth(), today.getDate() - 1);
    eventStartDatePicker.constraints.max = today;
    eventStartDatePicker.setValue( yesterday );
    eventStartDateRange = eventStartDatePicker.getValue();
    eventEndDatePicker.constraints.max = today;
    eventEndDatePicker.setValue( today );
    eventEndDateRange = eventEndDatePicker.getValue();
    dojo.connect(
        eventStartDatePicker,
        'onChange',
        function() {
            var new_date = arguments[0];
            if (new_date > eventEndDatePicker.getValue()) {
                var swap = eventEndDatePicker.getValue();
                eventEndDatePicker.setValue( new_date );
                this.setValue( swap );
            }
            eventStartDateRange = this.getValue();
        }
    );
    dojo.connect(
        eventEndDatePicker,
        'onChange',
        function() {
            var new_date = arguments[0];
            if (new_date < eventStartDatePicker.getValue()) {
                var swap = eventStartDatePicker.getValue();
                eventStartDatePicker.setValue( new_date );
                this.setValue( swap );
            }
            eventEndDateRange = this.getValue();
        }
    );

}

function buildStateSelector() {
    try {
        eventStateSelect.store = new dojo.data.ItemFileReadStore({
            data : {
                identifier:"value",
                label: "name",
                items: [
                    /* FIXME: I18N? */
                    {name:"Pending", value:'pending'},
                    {name:"Complete", value:'complete'},
                    {name:"Error", value:'error'}
                ]
            }
        });
        eventStateSelect.setValue('pending');
        dojo.connect(
            eventStateSelect, 
            'onChange',
            function() {
                try {
                     eventState = this.getValue();
                } catch(E) {
                    //dump('Error in acq/events.js, eventInit, connect, onChange: ' + E);
                    throw(E);
                }
            }
        );

    } catch(E) {
        //dump('Error in acq/events.js, buildStateSelector(): ' + E);
        throw(E);
    }
}

function buildOrgSelector() {
    try {
        var connect = function() {
            try {
                dojo.connect(
                    eventContextOrgSelect, 
                    'onChange',
                    function() {
                        try {
                             eventContextOrg = this.getValue();
                        } catch(E) {
                            //dump('Error in acq/events.js, eventInit, connect, onChange: ' + E);
                            throw(E);
                        }
                    }
                );
            } catch(E) {
                //dump('Error in acq/events.js, eventInit, connect: ' + E);
                throw(E);
            }
        };
        new openils.User().buildPermOrgSelector('STAFF_LOGIN', eventContextOrgSelect, null, connect);

    } catch(E) {
        //dump('Error in acq/events.js, buildOrgSelector(): ' + E);
        throw(E);
    }
}

function doSelected(method) {
    try {
        var ids = [];
        dojo.forEach(
            eventGrid.getSelectedItems(),
            function(item) {
                ids.push( eventGrid.store.getValue(item,'id') );
            }
        );
        fieldmapper.standardRequest(
            [ 'open-ils.acq', method ],
            {   async: true,
                params: [openils.User.authtoken, ids],
                onresponse: function(r) {
                    try {
                        var result = openils.Util.readResponse(r);
                        if (typeof result.ilsevent != 'undefined') { throw(result); }
                    } catch(E) {
                        //dump('Error in acq/events.js, doSelected(), onresponse(): ' + E);
                    }
                },
                onerror: function(r) {
                    try {
                        var result = openils.Util.readResponse(r);
                        throw(result);
                    } catch(E) {
                        //dump('Error in acq/events.js, doSelected(), onerror(): ' + E);
                        throw(E);
                    }
                },
                oncomplete: function(r) {
                    try {
                        var result = openils.Util.readResponse(r);
                        buildEventGrid();
                    } catch(E) {
                        //dump('Error in acq/events.js, doSelected(), oncomplete(): ' + E);
                        throw(E);
                    }
                }
            }
        );
    } catch(E) {
        //dump('Error in acq/events.js, doSelected(): ' + E);
        throw(E);
    }
}

function buildEventGrid() {
    eventGrid.resetStore();
    if(eventContextOrg == null) {
        eventContextOrg = openils.User.user.ws_ou();
    }
    if(eventState == null) {
        eventState = 'pending';
    }
    var filter = {"state":eventState, "order_by":[{"class":"atev", "field":"run_time", "direction":"desc"}]};
    if(eventStartDateRange != null) {
        /* the dijit appears to always provide 00:00:00 for the timestamp component */
        var end_of_day = eventEndDateRange; end_of_day.setDate( end_of_day.getDate() + 1 ); 
        filter['start_time'] = {
            'between' : [
                dojo.date.stamp.toISOString( eventStartDateRange ),
                dojo.date.stamp.toISOString( end_of_day )
            ]
        }
    }
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.events.ordering_agency'],
        {   async: true,
            params: [openils.User.authtoken, eventContextOrg, filter],
            onresponse: function(r) {
                try {
                    if(eventObject = openils.Util.readResponse(r)) {
                        eventGrid.store.newItem(atev.toStoreItem(eventObject));
                    }
                } catch(E) {
                    //dump('Error in acq/events.js, buildEventGrid, onresponse: ' + E);
                    throw(E);
                }
            }
        }
    );
}

openils.Util.addOnLoad(eventInit);


