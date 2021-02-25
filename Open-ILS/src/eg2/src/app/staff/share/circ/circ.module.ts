import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {CircService} from './circ.service';
import {CircGridComponent} from './grid.component';
import {DueDateDialogComponent} from './due-date-dialog.component';
import {PrecatCheckoutDialogComponent} from './precat-dialog.component';

@NgModule({
    declarations: [
        CircGridComponent,
        DueDateDialogComponent,
        PrecatCheckoutDialogComponent
    ],
    imports: [
        StaffCommonModule,
        HoldingsModule
    ],
    exports: [
        CircGridComponent,
        PrecatCheckoutDialogComponent
    ],
    providers: [
        CircService
    ]
})

export class CircModule {}
