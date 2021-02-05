import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {CircService} from './circ.service';

@NgModule({
    declarations: [
    ],
    imports: [
        StaffCommonModule,
        HoldingsModule
    ],
    exports: [
    ],
    providers: [
        CircService
    ]
})

export class CircModule {}
