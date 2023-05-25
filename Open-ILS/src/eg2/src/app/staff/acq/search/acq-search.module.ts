import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AcqSearchRoutingModule} from './routing.module';
import {AcqSearchComponent} from './acq-search.component';
import {LineitemResultsComponent} from './lineitem-results.component';
import {PurchaseOrderResultsComponent} from './purchase-order-results.component';
import {InvoiceResultsComponent} from './invoice-results.component';
import {PicklistResultsComponent} from './picklist-results.component';
import {PicklistCreateDialogComponent} from './picklist-create-dialog.component';
import {PicklistCloneDialogComponent} from './picklist-clone-dialog.component';
import {PicklistDeleteDialogComponent} from './picklist-delete-dialog.component';
import {PicklistMergeDialogComponent} from './picklist-merge-dialog.component';
import {AcqSearchService} from './acq-search.service';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {AcqCommonModule} from '../acq-common.module';
import {AcqSearchCommonModule} from './acq-search-common.module';

@NgModule({
    declarations: [
        AcqSearchComponent,
        PurchaseOrderResultsComponent,
        InvoiceResultsComponent,
        PicklistResultsComponent,
        PicklistCreateDialogComponent,
        PicklistCloneDialogComponent,
        PicklistDeleteDialogComponent,
        PicklistMergeDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AcqCommonModule,
        AcqSearchRoutingModule,
        AcqSearchCommonModule,
        LineitemModule
    ],
    providers: [AcqSearchService],
    exports: [
        AcqSearchComponent,
        PurchaseOrderResultsComponent,
        InvoiceResultsComponent,
        PicklistResultsComponent,
        PicklistCreateDialogComponent,
        PicklistCloneDialogComponent,
        PicklistDeleteDialogComponent,
        PicklistMergeDialogComponent
    ]
})

export class AcqSearchModule {
}
