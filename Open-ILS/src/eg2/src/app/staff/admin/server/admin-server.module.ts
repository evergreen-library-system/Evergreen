import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminServerRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminServerSplashComponent} from './admin-server-splash.component';
import {OrgUnitTypeComponent} from './org-unit-type.component';

@NgModule({
  declarations: [
      AdminServerSplashComponent,
      OrgUnitTypeComponent
  ],
  imports: [
    AdminCommonModule,
    AdminServerRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class AdminServerModule {
}


