import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {PrintersRoutingModule} from './routing.module';
import {PrintersComponent} from './printers.component';

@NgModule({
    imports: [
        PrintersComponent,
        StaffCommonModule,
        PrintersRoutingModule
    ]
})

export class ManagePrintersModule {}


