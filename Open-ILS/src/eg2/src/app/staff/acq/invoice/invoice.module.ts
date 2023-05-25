import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {AcqCommonModule} from '@eg/staff/acq/acq-common.module';
import {AcqSearchCommonModule} from '@eg/staff/acq/search/acq-search-common.module';
import {LineitemResultsComponent} from '@eg/staff/acq/search/lineitem-results.component';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {InvoiceRoutingModule} from './routing.module';
import {InvoiceComponent} from './invoice.component';
import {InvoiceBatchReceiveComponent} from './batch_receive.component';
import {PrintComponent} from './print.component';
import {InvoiceDetailsComponent} from './details.component';
import {InvoiceChargesComponent} from './charges.component';
import {DisencumberChargeDialogComponent} from './disencumber-charge-dialog.component';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';

@NgModule({
    declarations: [
        InvoiceComponent,
        InvoiceDetailsComponent,
        InvoiceChargesComponent,
        InvoiceBatchReceiveComponent,
        PrintComponent,
        DisencumberChargeDialogComponent
    ],
    imports: [
        StaffCommonModule,
        CatalogCommonModule,
        AcqCommonModule,
        AcqSearchCommonModule,
        LineitemModule,
        InvoiceRoutingModule,
        FmRecordEditorModule
    ],
    providers: []
})

export class InvoiceModule {
}
