import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminServerRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminServerSplashComponent} from './admin-server-splash.component';

@NgModule({
  declarations: [
      AdminServerSplashComponent
  ],
  imports: [
    AdminCommonModule,
    AdminServerRoutingModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class AdminServerModule {
}


