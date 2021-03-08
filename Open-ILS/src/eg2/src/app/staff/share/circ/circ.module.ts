import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {BillingModule} from '@eg/staff/share/billing/billing.module';
import {CircService} from './circ.service';
import {CircGridComponent} from './grid.component';
import {DueDateDialogComponent} from './due-date-dialog.component';
import {PrecatCheckoutDialogComponent} from './precat-dialog.component';
import {ClaimsReturnedDialogComponent} from './claims-returned-dialog.component';
import {CircComponentsComponent} from './components.component';
import {CircEventsComponent} from './events-dialog.component';

@NgModule({
    declarations: [
        CircGridComponent,
        CircComponentsComponent,
        DueDateDialogComponent,
        PrecatCheckoutDialogComponent,
        ClaimsReturnedDialogComponent,
        CircEventsComponent
    ],
    imports: [
        StaffCommonModule,
        HoldingsModule,
        BillingModule
    ],
    exports: [
        CircGridComponent,
        CircComponentsComponent
    ],
    providers: [
        CircService
    ]
})

export class CircModule {}
