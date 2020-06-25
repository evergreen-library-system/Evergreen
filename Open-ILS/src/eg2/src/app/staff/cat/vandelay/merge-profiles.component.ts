import {Component} from '@angular/core';

@Component({
    template: `<eg-admin-page idlClass="vmp"
      fieldOrder="name,owner,add_spec,replace_spec,strip_spec,preserve_spec,lwm_ratio,update_bib_source,id">
    </eg-admin-page>`
})
export class MergeProfilesComponent {
    constructor() {}
}

