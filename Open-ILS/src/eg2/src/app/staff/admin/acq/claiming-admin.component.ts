import {Component} from '@angular/core';
import { TitleComponent } from '@eg/share/title/title.component';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './claiming-admin.component.html',
    imports: [
        AdminPageComponent,
        NgbNavModule,
        StaffBannerComponent,
        TitleComponent,
    ]
})
export class ClaimingAdminComponent {
}
