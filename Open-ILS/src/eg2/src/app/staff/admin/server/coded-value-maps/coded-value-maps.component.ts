import {Component} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './coded-value-maps.component.html',
    imports: [
        AdminPageComponent,
        StaffCommonModule
    ]
})

export class CodedValueMapsComponent { }
