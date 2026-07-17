import {Component} from '@angular/core';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    template: `<eg-admin-page idlClass="vmp"
      fieldOrder="name,owner,add_spec,replace_spec,strip_spec,preserve_spec,lwm_ratio,update_bib_source,id">
    </eg-admin-page>`,
    imports: [AdminPageComponent]
})
export class MergeProfilesComponent {
    constructor() {}
}

