import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {LinkTableComponent, LinkTableLinkComponent} from '@eg/staff/share/link-table/link-table.component';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';

@NgModule({
  declarations: [
    LinkTableComponent,
    LinkTableLinkComponent,
    BasicAdminPageComponent
  ],
  imports: [
    StaffCommonModule
  ],
  exports: [
    StaffCommonModule,
    LinkTableComponent,
    LinkTableLinkComponent,
    BasicAdminPageComponent
  ],
  providers: [
  ]
})

export class AdminCommonModule {
}


