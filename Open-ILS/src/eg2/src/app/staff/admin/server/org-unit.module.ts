import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {OrgUnitComponent} from './org-unit.component';
import {OrgAddressComponent} from './org-addr.component';
import {OrgUnitRoutingModule} from './org-unit-routing.module';

@NgModule({
  declarations: [
    OrgUnitComponent,
    OrgAddressComponent
  ],
  imports: [
    AdminCommonModule,
    OrgUnitRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class OrgUnitModule {
}


