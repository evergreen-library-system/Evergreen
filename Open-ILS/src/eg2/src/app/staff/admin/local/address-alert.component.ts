import {Component, ViewChild, TemplateRef} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './address-alert.component.html',
    imports: [
        AdminPageComponent,
        StaffCommonModule
    ]
})

export class AddressAlertComponent {

    @ViewChild('helpTemplate', { static: true }) helpTemplate: TemplateRef<any>;

    constructor() {}
}

