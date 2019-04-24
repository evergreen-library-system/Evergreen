import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminBookingRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminBookingSplashComponent} from './admin-booking-splash.component';

@NgModule({
  declarations: [
      AdminBookingSplashComponent
  ],
  imports: [
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


