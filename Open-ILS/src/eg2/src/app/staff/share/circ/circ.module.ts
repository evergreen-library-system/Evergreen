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
import {OpenCircDialogComponent} from './open-circ-dialog.component';
import {RouteDialogComponent} from './route-dialog.component';
import {CopyInTransitDialogComponent} from './in-transit-dialog.component';
import {CancelTransitDialogComponent} from './cancel-transit-dialog.component';
import {BackdateDialogComponent} from './backdate-dialog.component';
import {WorkLogService} from './work-log.service';

@NgModule({
    declarations: [
        CircGridComponent,
        CircComponentsComponent,
        DueDateDialogComponent,
        PrecatCheckoutDialogComponent,
        ClaimsReturnedDialogComponent,
        CircEventsComponent,
        RouteDialogComponent,
        BackdateDialogComponent,
        CopyInTransitDialogComponent,
        CancelTransitDialogComponent,
        OpenCircDialogComponent
    ],
    imports: [
        StaffCommonModule,
        HoldingsModule,
        BillingModule
    ],
    exports: [
        CircGridComponent,
        BackdateDialogComponent,
        CancelTransitDialogComponent,
        CircComponentsComponent
    ],
    providers: [
        CircService,
        WorkLogService
    ]
})

export class CircModule {}
