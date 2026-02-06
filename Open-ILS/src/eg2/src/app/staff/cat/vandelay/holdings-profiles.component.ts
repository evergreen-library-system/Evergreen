import {Component} from '@angular/core';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    template: '<eg-admin-page idlClass="viiad"></eg-admin-page>',
    imports: [AdminPageComponent]
})
export class HoldingsProfilesComponent {
    constructor() {}
}

