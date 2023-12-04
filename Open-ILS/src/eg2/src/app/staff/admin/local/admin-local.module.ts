import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminLocalRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminLocalSplashComponent} from './admin-local-splash.component';
import {AddressAlertComponent} from './address-alert.component';
import {AdminCarouselComponent} from './admin-carousel.component';
import {ClonePortalEntriesDialogComponent} from './staff_portal_page/clone-portal-entries-dialog.component';
import {AdminStaffPortalPageComponent} from './staff_portal_page/staff-portal-page.component';
import {StandingPenaltyComponent} from './standing-penalty.component';

@NgModule({
    declarations: [
        AdminLocalSplashComponent,
        AddressAlertComponent,
        AdminCarouselComponent,
        StandingPenaltyComponent,
        ClonePortalEntriesDialogComponent,
        AdminStaffPortalPageComponent
    ],
    imports: [
        AdminCommonModule,
        AdminLocalRoutingModule,
        TreeModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class AdminLocalModule {
}


