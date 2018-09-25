import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {WorkstationsRoutingModule} from './routing.module';
import {WorkstationsComponent} from './workstations.component';

@NgModule({
  declarations: [
    WorkstationsComponent,
  ],
  imports: [
    StaffCommonModule,
    WorkstationsRoutingModule
  ]
})

export class ManageWorkstationsModule {}


