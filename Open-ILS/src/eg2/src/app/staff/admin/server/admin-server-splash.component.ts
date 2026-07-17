import {Component} from '@angular/core';
import { RouterModule } from '@angular/router';
import { LinkTableComponent, LinkTableLinkComponent } from '@eg/staff/share/link-table/link-table.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';

@Component({
    templateUrl: './admin-server-splash.component.html',
    imports: [
        LinkTableComponent,
        LinkTableLinkComponent,
        RouterModule,
        StaffBannerComponent,
    ]
})

export class AdminServerSplashComponent {
}


