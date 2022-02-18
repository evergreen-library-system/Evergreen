import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {PrintersRoutingModule} from './routing.module';
import {PrintersComponent} from './printers.component';

@NgModule({
  declarations: [
    PrintersComponent,
  ],
  imports: [
    StaffCommonModule,
    PrintersRoutingModule
  ]
})

export class ManagePrintersModule {}


