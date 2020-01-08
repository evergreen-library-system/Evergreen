import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AuthorityRoutingModule} from './routing.module';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';
import {AuthorityMarcEditComponent} from './marc-edit.component';

@NgModule({
  declarations: [
    AuthorityMarcEditComponent
  ],
  imports: [
    StaffCommonModule,
    CommonWidgetsModule,
    MarcEditModule,
    AuthorityRoutingModule
  ],
  providers: [
  ]
})

export class AuthorityModule {
}
