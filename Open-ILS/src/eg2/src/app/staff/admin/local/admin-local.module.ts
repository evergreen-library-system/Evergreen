import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminLocalRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminLocalSplashComponent} from './admin-local-splash.component';

@NgModule({
  declarations: [
      AdminLocalSplashComponent
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


