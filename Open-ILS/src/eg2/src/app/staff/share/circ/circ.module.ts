import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {CircService} from './circ.service';
import {CircGridComponent} from './grid.component';

@NgModule({
    declarations: [
        CircGridComponent
    ],
    imports: [
        StaffCommonModule,
        HoldingsModule
    ],
    exports: [
        CircGridComponent
    ],
    providers: [
        CircService
    ]
})

export class CircModule {}
