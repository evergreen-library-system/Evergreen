import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsService} from './holdings.service';
import {MarkDamagedDialogComponent} from './mark-damaged-dialog.component';
import {MarkMissingDialogComponent} from './mark-missing-dialog.component';
import {CopyAlertsDialogComponent} from './copy-alerts-dialog.component';
import {ReplaceBarcodeDialogComponent} from './replace-barcode-dialog.component';
import {DeleteHoldingDialogComponent} from './delete-volcopy-dialog.component';
import {ConjoinedItemsDialogComponent} from './conjoined-items-dialog.component';
import {TransferItemsComponent} from './transfer-items.component';
import {TransferHoldingsComponent} from './transfer-holdings.component';

@NgModule({
    declarations: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent,
      CopyAlertsDialogComponent,
      ReplaceBarcodeDialogComponent,
      DeleteHoldingDialogComponent,
      ConjoinedItemsDialogComponent,
      TransferItemsComponent,
      TransferHoldingsComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent,
      CopyAlertsDialogComponent,
      ReplaceBarcodeDialogComponent,
      DeleteHoldingDialogComponent,
      ConjoinedItemsDialogComponent,
      TransferItemsComponent,
      TransferHoldingsComponent
    ],
    providers: [
        HoldingsService
    ]
})

export class HoldingsModule {}

