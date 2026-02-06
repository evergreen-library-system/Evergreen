import {Component} from '@angular/core';
import { RouterModule } from '@angular/router';
import { TitleComponent } from '@eg/share/title/title.component';
import { LinkTableComponent, LinkTableLinkComponent } from '@eg/staff/share/link-table/link-table.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';

@Component({
    templateUrl: './admin-acq-splash.component.html',
    imports: [
        LinkTableComponent,
        LinkTableLinkComponent,
        RouterModule,
        StaffBannerComponent,
        TitleComponent,
    ]
})

export class AdminAcqSplashComponent {
}


