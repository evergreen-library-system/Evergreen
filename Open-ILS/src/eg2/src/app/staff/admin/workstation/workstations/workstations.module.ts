import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {WorkstationsRoutingModule} from './routing.module';
import {WorkstationsComponent} from './workstations.component';

@NgModule({
    imports: [
        StaffCommonModule,
        WorkstationsComponent,
        WorkstationsRoutingModule
    ]
})

export class ManageWorkstationsModule {}


