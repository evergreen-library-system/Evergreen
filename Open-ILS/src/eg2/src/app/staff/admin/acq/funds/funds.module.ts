import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {FundsComponent} from './funds.component';
import {FundsRoutingModule} from './routing.module';
import {FundsManagerComponent} from './funds-manager.component';
import {FundDetailsDialogComponent} from './fund-details-dialog.component';
import {FundingSourcesComponent} from './funding-sources.component';
import {FundingSourceTransactionsDialogComponent} from './funding-source-transactions-dialog.component';
import {FundTagsComponent} from './fund-tags.component';
import {FundTransferDialogComponent} from './fund-transfer-dialog.component';
import {FundRolloverDialogComponent} from './fund-rollover-dialog.component';

@NgModule({
    declarations: [
        FundsComponent,
        FundsManagerComponent,
        FundDetailsDialogComponent,
        FundingSourcesComponent,
        FundingSourceTransactionsDialogComponent,
        FundTagsComponent,
        FundTransferDialogComponent,
        FundRolloverDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AdminCommonModule,
        FundsRoutingModule,
    ],
    exports: [
    ],
    providers: [
    ]
})

export class FundsModule {
}
