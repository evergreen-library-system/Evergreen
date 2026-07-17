import {Component} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { LinkTableComponent, LinkTableLinkComponent } from '@eg/staff/share/link-table/link-table.component';

@Component({
    templateUrl: './admin-booking-splash.component.html',
    imports: [
        LinkTableComponent,
        LinkTableLinkComponent,
        StaffCommonModule
    ]
})

export class AdminBookingSplashComponent {
}


