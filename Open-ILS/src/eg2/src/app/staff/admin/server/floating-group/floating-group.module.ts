import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {FloatingGroupComponent} from './floating-group.component';
import {EditFloatingGroupComponent} from './edit-floating-group.component';
import {FloatingGroupRoutingModule} from './floating-group-routing.module';

@NgModule({
  declarations: [
    FloatingGroupComponent,
    EditFloatingGroupComponent
  ],
  imports: [
    AdminCommonModule,
    FloatingGroupRoutingModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class FloatingGroupModule {
}
