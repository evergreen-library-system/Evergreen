import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {ItemLocationSelectModule
} from '@eg/share/item-location-select/item-location-select.module';
import {LineitemWorksheetComponent} from './worksheet.component';
import {LineitemService} from './lineitem.service';
import {PoService} from '../po/po.service';
import {LineitemComponent} from './lineitem.component';
import {LineitemNotesComponent} from './notes.component';
import {LineitemDetailComponent} from './detail.component';
import {LineitemOrderSummaryComponent} from './order-summary.component';
import {LineitemListComponent} from './lineitem-list.component';
import {LineitemCopiesComponent} from './copies.component';
import {LineitemBatchCopiesComponent} from './batch-copies.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';
import {LineitemHistoryComponent} from './history.component';
import {LineitemFromBibIdsComponent} from './from-bib-ids.component';
import {BriefRecordComponent} from './brief-record.component';
import {CreateAssetsComponent} from './create-assets.component';
import {CancelDialogComponent} from './cancel-dialog.component';
import {AddToPoDialogComponent} from './add-to-po-dialog.component';
import {DeleteLineitemsDialogComponent} from './delete-lineitems-dialog.component';
import {AddCopiesDialogComponent} from './add-copies-dialog.component';
import {BibFinderDialogComponent} from './bib-finder-dialog.component';
import {BatchUpdateCopiesDialogComponent} from './batch-update-copies-dialog.component';
import {LinkInvoiceDialogComponent} from './link-invoice-dialog.component';
import {ExportAttributesDialogComponent} from './export-attributes-dialog.component';
import {ClaimPolicyDialogComponent} from './claim-policy-dialog.component';
import {ManageClaimsDialogComponent} from './manage-claims-dialog.component';
import {LineitemAlertDialogComponent} from './lineitem-alert-dialog.component';
import {AddExtraItemsForOrderDialogComponent} from './add-extra-items-for-order-dialog.component';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';
import {AcqCommonModule} from '../acq-common.module';

@NgModule({
    declarations: [
        LineitemComponent,
        LineitemListComponent,
        LineitemNotesComponent,
        LineitemDetailComponent,
        LineitemCopiesComponent,
        LineitemOrderSummaryComponent,
        LineitemBatchCopiesComponent,
        LineitemCopyAttrsComponent,
        LineitemHistoryComponent,
        CancelDialogComponent,
        AddToPoDialogComponent,
        DeleteLineitemsDialogComponent,
        AddCopiesDialogComponent,
        BibFinderDialogComponent,
        BatchUpdateCopiesDialogComponent,
        LinkInvoiceDialogComponent,
        ExportAttributesDialogComponent,
        ClaimPolicyDialogComponent,
        ManageClaimsDialogComponent,
        LineitemAlertDialogComponent,
        AddExtraItemsForOrderDialogComponent,
        LineitemFromBibIdsComponent,
        BriefRecordComponent,
        CreateAssetsComponent,
        LineitemWorksheetComponent
    ],
    exports: [
        LineitemListComponent,
        CancelDialogComponent,
        AddToPoDialogComponent,
        DeleteLineitemsDialogComponent,
        AddCopiesDialogComponent,
        LinkInvoiceDialogComponent,
        ExportAttributesDialogComponent,
        ClaimPolicyDialogComponent,
        ManageClaimsDialogComponent,
        LineitemAlertDialogComponent,
        AddExtraItemsForOrderDialogComponent,
    ],
    imports: [
        StaffCommonModule,
        ItemLocationSelectModule,
        MarcEditModule,
        HttpClientModule,
        AcqCommonModule
    ],
    providers: [
        LineitemService,
        PoService
    ]
})

export class LineitemModule {
}
