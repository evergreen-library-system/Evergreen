import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CashReportsComponent} from './cash-reports.component';
import {CashReportsRoutingModule} from './routing.module';

@NgModule({
    declarations: [
        CashReportsComponent
    ],
    imports: [
        StaffCommonModule,
        TreeModule,
        CashReportsRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CashReportsModule {
}

