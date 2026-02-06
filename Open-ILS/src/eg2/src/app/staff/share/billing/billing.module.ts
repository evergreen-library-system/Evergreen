import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BillingService} from './billing.service';
import {AddBillingDialogComponent} from './billing-dialog.component';
import {CreditCardDialogComponent} from './credit-card-dialog.component';

@NgModule({
    imports: [
        AddBillingDialogComponent,
        CreditCardDialogComponent,
        StaffCommonModule
    ],
    exports: [
        AddBillingDialogComponent,
        CreditCardDialogComponent
    ],
    providers: [
        BillingService
    ]
})

export class BillingModule {}
