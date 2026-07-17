import {NgModule} from '@angular/core';
import {AdminBookingRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminBookingSplashComponent} from './admin-booking-splash.component';

@NgModule({
    imports: [
        AdminBookingSplashComponent,
        AdminCommonModule,
        AdminBookingRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class AdminBookingModule {
}


