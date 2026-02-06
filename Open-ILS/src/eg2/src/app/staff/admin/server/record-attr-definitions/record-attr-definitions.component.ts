import {Component} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './record-attr-definitions.component.html',
    imports: [
        AdminPageComponent,
        StaffCommonModule
    ]
})

export class RecordAttrDefinitionsComponent { }
