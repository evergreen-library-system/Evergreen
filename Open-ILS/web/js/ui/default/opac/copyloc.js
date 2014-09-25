dojo.require("DojoSRF");
dojo.require("openils.CGI");

// called on initial page load and when the advance search org unit
// selector is changed.
function apply_adv_copy_locations() {

    // patron selected org
    var sel = dojo.byId('adv_org_selector');
    var selected_id = sel.options[sel.selectedIndex].getAttribute('value');
    var org_unit = aou_hash[selected_id];

    if (org_unit.can_have_vols != 't') {
        dojo.addClass('adv_chunk_copy_location', 'hidden');
        return;
    }

    var display_orgs = [];

    // we want to display copy locations at the selected org,
    // all parent orgs, and all child orgs.

    function collect_child_orgs(org_id) {
        display_orgs.push(org_id);
        for (var id in aou_hash) { // for key in
            if (aou_hash[id].parent_ou == org_id) 
                collect_child_orgs(id);
        }
    }

    function collect_parent_orgs(org_id) {
        if (!org_id) return;
        display_orgs.push(org_id);
        collect_parent_orgs(aou_hash[org_id].parent_ou);
    }

    collect_child_orgs(org_unit.id);
    collect_parent_orgs(org_unit.parent_ou);
    fetch_adv_copy_locations(display_orgs);
}

function fetch_adv_copy_locations(org_ids) {

    var params = [{
        cache : 1, 
        fields : ['name', 'id', 'owning_lib'],
        query : {owning_lib : org_ids, opac_visible : 't', deleted : 'f'}
    }];

    new OpenSRF.ClientSession('open-ils.fielder').request({
        method: 'open-ils.fielder.acpl.atomic',
        params: params,
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                var list = resp.content();
                if (list && list.length) {
                    render_adv_copy_locations(list);
                } else {
                    dojo.addClass('adv_chunk_copy_location', 'hidden');
                }
            } else {
                dojo.addClass('adv_chunk_copy_location', 'hidden');
            }
        }                                                              
    }).send(); 
}

function render_adv_copy_locations(locations) {
    var sel = dojo.byId('adv_copy_location_selector');
    var cgi = new openils.CGI();

    // collect any location values from the URL to re-populate the list
    var url_selected = cgi.param('fi:locations');
    if (url_selected) {
        if (!dojo.isArray(url_selected)) 
            url_selected = [url_selected];
    }

    dojo.removeClass('adv_chunk_copy_location', 'hidden');
    
    // sort by name
    locations = locations.sort(
        function(a, b) {return a.name < b.name ? -1 : 1}
    );

    // remove the previous list of locations
    dojo.empty(sel);

    // append the new list of locations
    dojo.forEach(locations, function(loc) {
        var attrs = {value : loc.id, innerHTML : loc.name};
        if (url_selected && url_selected.indexOf(''+loc.id) > -1) {
            attrs.selected = true;
        }
        sel.appendChild(dojo.create('option', attrs));
    });
}

// load the locations on page load
dojo.addOnLoad(function() {
    apply_adv_copy_locations();
    dojo.connect(dojo.byId('adv_org_selector'), 
        'onchange', apply_adv_copy_locations);
});

