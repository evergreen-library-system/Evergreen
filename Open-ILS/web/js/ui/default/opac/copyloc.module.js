// called on initial page load and when the advance search org unit
// selector is changed.
export function apply_adv_copy_locations() {
    // patron selected org
    var sel = document.getElementById('adv_org_selector');
    var selected_id = sel.value;
    var org_unit = window.aou_hash[selected_id];

    var display_orgs = [];

    function collect_parent_orgs(org_id) {
        if (!org_id) return;
        display_orgs.push(org_id);
        collect_parent_orgs(window.aou_hash[org_id].parent_ou);
    }

    display_orgs.push(org_unit.id);
    collect_parent_orgs(org_unit.parent_ou);
    fetch_adv_copy_locations(display_orgs);
}

function fetch_adv_copy_locations(org_ids) {

    var params = [{
        cache : 1,
        fields : ['name', 'id', 'owning_lib'],
        query : {owning_lib : org_ids, opac_visible : 't', deleted : 'f'}
    }];

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

function render_adv_copy_locations_new(locations) {
    var sel = document.getElementById('adv_copy_location_selector_new');
    if(sel)
    {
    sel.innerText = '';

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


    var ulist = document.createElement('ul');
    ulist.classList.add("adv_filters");
    // append the new list of locations
    locations.forEach(loc => {
        const selected = (url_selected && url_selected.indexOf(''+loc.id) > -1) ? true : false;

        const li = document.createElement('li');
        li.innerHTML = `<div class="form-check">
                          <label class="form-check-label">
                            <input class="form-check-input"
                                   value="${loc.id}"
                                   name="fi:locations"
                                   selected="${selected}"
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
