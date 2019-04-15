import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminServerRoutingModule} from './routing.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {AdminServerSplashComponent} from './admin-server-splash.component';
import {OrgUnitTypeComponent} from './org-unit-type.component';
import {PrintTemplateComponent} from './print-template.component';
import {SampleDataService} from '@eg/share/util/sample-data.service';

@NgModule({
  declarations: [
      AdminServerSplashComponent,
      OrgUnitTypeComponent,
      PrintTemplateComponent
  ],
  imports: [
    AdminCommonModule,
    AdminServerRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
    SampleDataService
  ]
})

export class AdminServerModule {
}


