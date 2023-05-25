import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
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
import {AcqSearchFormComponent} from '@eg/staff/acq/search/acq-search-form.component';
import {LineitemResultsComponent} from './lineitem-results.component';

@NgModule({
    imports: [
        StaffCommonModule,
        AcqCommonModule,
        LineitemModule
    ],
    declarations: [
        AcqSearchFormComponent,
        LineitemResultsComponent
    ],
    exports: [
        AcqSearchFormComponent,
        LineitemResultsComponent
    ],
    providers: [AcqSearchService]
})

export class AcqSearchCommonModule {
}
