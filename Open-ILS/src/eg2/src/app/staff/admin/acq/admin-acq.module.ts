import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminAcqRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminAcqSplashComponent} from './admin-acq-splash.component';
import {ClaimingAdminComponent} from './claiming-admin.component';
import {FiscalYearAdminComponent} from './fiscal-year-admin.component';

@NgModule({
    imports: [
        AdminAcqSplashComponent,
        AdminCommonModule,
        AdminAcqRoutingModule,
        ClaimingAdminComponent,
        FiscalYearAdminComponent
    ],
    exports: [
    ],
    providers: [
    ]
})

export class AdminAcqModule {
}


