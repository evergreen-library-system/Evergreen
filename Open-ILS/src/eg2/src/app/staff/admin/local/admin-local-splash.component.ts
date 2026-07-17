import {Component} from '@angular/core';
import { LinkTableComponent, LinkTableLinkComponent } from '@eg/staff/share/link-table/link-table.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';

@Component({
    templateUrl: './admin-local-splash.component.html',
    imports: [
        LinkTableComponent,
        LinkTableLinkComponent,
        StaffBannerComponent
    ]
})

export class AdminLocalSplashComponent {
}


