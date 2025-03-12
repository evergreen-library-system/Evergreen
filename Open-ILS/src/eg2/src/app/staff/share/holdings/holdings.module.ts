import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BillingModule} from '@eg/staff/share/billing/billing.module';
import {HoldingsService} from './holdings.service';
import {MarkDamagedDialogComponent} from './mark-damaged-dialog.component';
import {MarkMissingDialogComponent} from './mark-missing-dialog.component';
import {MarkDiscardDialogComponent} from './mark-discard-dialog.component';
import {CopyAlertsDialogComponent, AlertTypeValidatorDirective} from './copy-alerts-dialog.component';
import {CopyTagsDialogComponent} from './copy-tags-dialog.component';
import {TagMapListComponent} from './tag-map-list.component';
import {CopyNotesDialogComponent} from './copy-notes-dialog.component';
import {ReplaceBarcodeDialogComponent} from './replace-barcode-dialog.component';
import {DeleteHoldingDialogComponent} from './delete-volcopy-dialog.component';
import {ConjoinedItemsDialogComponent} from './conjoined-items-dialog.component';
import {TransferItemsComponent} from './transfer-items.component';
import {TransferHoldingsComponent} from './transfer-holdings.component';
import {BatchItemAttrComponent} from './batch-item-attr.component';
import {CopyThingsDialogWrapperComponent} from './copy-things-dialog-wrapper.component';
import {CopyAlertManagerDialogComponent} from './copy-alert-manager.component';
import {CopyAlertsPageComponent} from './copy-alerts-page.component';
import {CopyNotesEditComponent} from './copy-notes-edit/copy-notes-edit.component';
import { FmRecordEditorModule } from '@eg/share/fm-editor/fm-editor.module';

@NgModule({
    declarations: [
        MarkDamagedDialogComponent,
        MarkMissingDialogComponent,
        MarkDiscardDialogComponent,
        CopyThingsDialogWrapperComponent,
        CopyAlertsDialogComponent,
        CopyTagsDialogComponent,
        TagMapListComponent,
        CopyNotesDialogComponent,
        CopyNotesEditComponent,
        ReplaceBarcodeDialogComponent,
        DeleteHoldingDialogComponent,
        ConjoinedItemsDialogComponent,
        TransferItemsComponent,
        TransferHoldingsComponent,
        BatchItemAttrComponent,
        CopyAlertManagerDialogComponent,
        CopyAlertsPageComponent,
        AlertTypeValidatorDirective
    ],
    imports: [
        StaffCommonModule,
        BillingModule,
        FmRecordEditorModule
    ],
    exports: [
        MarkDamagedDialogComponent,
        MarkMissingDialogComponent,
        MarkDiscardDialogComponent,
        CopyAlertsDialogComponent,
        CopyTagsDialogComponent,
        TagMapListComponent,
        CopyNotesDialogComponent,
        ReplaceBarcodeDialogComponent,
        DeleteHoldingDialogComponent,
        ConjoinedItemsDialogComponent,
        TransferItemsComponent,
        TransferHoldingsComponent,
        BatchItemAttrComponent,
        CopyAlertManagerDialogComponent,
        CopyAlertsPageComponent
    ],
    providers: [
        HoldingsService
    ]
})

export class HoldingsModule {}

