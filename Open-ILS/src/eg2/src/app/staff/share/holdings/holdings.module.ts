import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldingsService} from './holdings.service';
import {MarkDamagedDialogComponent} from './mark-damaged-dialog.component';
import {MarkMissingDialogComponent} from './mark-missing-dialog.component';
import {CopyAlertsDialogComponent} from './copy-alerts-dialog.component';
import {ReplaceBarcodeDialogComponent} from './replace-barcode-dialog.component';

@NgModule({
    declarations: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent,
      CopyAlertsDialogComponent,
      ReplaceBarcodeDialogComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
      MarkDamagedDialogComponent,
      MarkMissingDialogComponent,
      CopyAlertsDialogComponent,
      ReplaceBarcodeDialogComponent
    ],
    providers: [
        HoldingsService
    ]
})

export class HoldingsModule {}

