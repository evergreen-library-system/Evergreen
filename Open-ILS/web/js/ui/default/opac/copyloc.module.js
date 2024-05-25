// called on initial page load and when the advance search org unit
// selector is changed.
export function apply_adv_copy_locations() {
    // patron selected org
    var sel = document.getElementById('adv_org_selector');
    var selected_id = sel.value;
    if (org_unit_is_selected(sel)) {
        var org_unit = window.aou_hash[selected_id];

        var display_orgs = [];

        // eslint-disable-next-line no-inner-declarations
        function collect_parent_orgs(org_id) {
            if (!org_id) return;
            display_orgs.push(org_id);
            collect_parent_orgs(window.aou_hash[org_id].parent_ou);
        }

        display_orgs.push(org_unit.id);
        collect_parent_orgs(org_unit.parent_ou);
        fetch_adv_copy_locations_by_org(display_orgs);
    } else if (shelving_location_group_is_selected(sel)) {
        // The UI has shelving location group ids in the format
        // 3:2, where 3 is the owning org id and 2 is the location
        // group id.  To query fielder, we only need the location
        // group id.
        const group_id = selected_id.split(':')[1];
        fetch_adv_copy_locations_by_group(group_id);
    }
}

function fetch_adv_copy_locations_by_org(org_ids) {
    var params = [{
        cache : 1,
        fields : ['name', 'id', 'owning_lib'],
        query : {owning_lib : org_ids, opac_visible : 't', deleted : 'f'}
    }];
    send_and_process_fielder_query(params);
}

function send_and_process_fielder_query(params) {
    new window.OpenSRF.ClientSession('open-ils.fielder').request({
        method: 'open-ils.fielder.acpl.atomic',
        params: params,
        async: true,
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                var list = resp.content();
                if (list && list.length) {
                    render_adv_copy_locations(list);
                    render_adv_copy_locations_new(list);
                } else {
                    document.getElementById('adv_chunk_copy_location').classList.add('hidden');
                }
            } else {
                document.getElementById('adv_chunk_copy_location').classList.add('hidden');
            }
        }
    }).send();
}

function fetch_adv_copy_locations_by_group(group_id) {
    const params = [{
        cache : 1,
        fields : ['name', 'id', 'owning_lib'],
        // open-ils.fielder.acpl.atomic unfortunately
        // can't do JOINs, so we will use a subquery
        // instead
        query : {
            opac_visible : 't',
            deleted : 'f',
            id: {
                in: {
                    from:"acplgm",
                    select:{"acplgm":["location"]},
                    "where":{"lgroup": group_id}
                }
            }
        }
    }];
    send_and_process_fielder_query(params);
}

function render_adv_copy_locations_new(locations) {
    var sel = document.getElementById('adv_copy_location_selector_new');
    if(sel)
    {
    sel.innerText = '';

    // collect any location values from the URL to re-populate the list
    // first, get any fi:locations from &-separated query params
    let url_selected = new URLSearchParams(window.location.search).get('fi:locations');
    // next, get any fi:locations from ;-separated query params
    const fi_location_digit = /\??fi.*locations\=(\d+)/;
    let semicolon_matches = window.location.search.split(';').filter(qstring => fi_location_digit.test(qstring)).map(qstring => fi_location_digit.exec(qstring)[1]);
    if (url_selected) {
        if (!url_selected.isArray())
            url_selected = [url_selected];
    } else {
        url_selected = [];
    }
    url_selected = url_selected.concat(semicolon_matches);

    document.getElementById('adv_chunk_copy_location').classList.remove('hidden');

    // sort by name
    locations = locations.sort(
        function(a, b) {return a.name < b.name ? -1 : 1;}
    );


    var ulist = document.createElement('ul');
    ulist.classList.add("adv_filters");
    // append the new list of locations
    locations.forEach(loc => {
        const checked = (url_selected && url_selected.indexOf(''+loc.id) > -1);

        const li = document.createElement('li');
        li.innerHTML = `<div class="form-check">
                          <label class="form-check-label">
                            <input class="form-check-input"
                                   value="${loc.id}"
                                   name="fi:locations"
                                   ${checked ? 'checked' : ''}
                                   type="checkbox">
                            ${loc.name}
                          </label>
                        </div>`;
        ulist.append(li);
    });
    sel.append(ulist);
}
}



function render_adv_copy_locations(locations) {
    var sel = document.getElementById('adv_copy_location_selector');
    if(sel){


    // collect any location values from the URL to re-populate the list
    let url_selected = new URLSearchParams(window.location.search).get('fi:locations');
    if (url_selected) {
        if (!url_selected.isArray())
            url_selected = [url_selected];
    }

    document.getElementById('adv_chunk_copy_location').classList.remove('hidden');

    // sort by name
    locations = locations.sort(
        function(a, b) {return a.name < b.name ? -1 : 1;}
    );

    // remove the previous list of locations
    sel.innerText = '';

    // append the new list of locations
    locations.forEach((loc) => {
        const option = document.createElement('option');
        option.setAttribute('value', loc.id);
        option.innerHTML = loc.name;
        if (url_selected && url_selected.indexOf(''+loc.id) > -1) {
            option.setAttribute('selected', true);
        }
        sel.append(option);
    });
}

}

function org_unit_is_selected(sel) {
    return sel.selectedOptions?.[0]?.classList?.contains('org_unit');
}

function shelving_location_group_is_selected(sel) {
    return sel.selectedOptions?.[0]?.classList?.contains('loc_grp');
}
