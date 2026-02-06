import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {AdminLocalRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminLocalSplashComponent} from './admin-local-splash.component';
import {AddressAlertComponent} from './address-alert.component';
import {AdminCarouselComponent} from './admin-carousel.component';
import {ClonePortalEntriesDialogComponent} from './staff_portal_page/clone-portal-entries-dialog.component';
import {AdminStaffPortalPageComponent} from './staff_portal_page/staff-portal-page.component';
import {StandingPenaltyComponent} from './standing-penalty.component';
import { CopyAlertTypesComponent } from './copy-alert-types/copy-alert-types.component';

@NgModule({
    imports: [
        AddressAlertComponent,
        AdminCarouselComponent,
        AdminCommonModule,
        AdminLocalRoutingModule,
        AdminLocalSplashComponent,
        AdminStaffPortalPageComponent,
        ClonePortalEntriesDialogComponent,
        CopyAlertTypesComponent,
        StandingPenaltyComponent,
        TreeModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class AdminLocalModule {
}


