import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AcqSearchRoutingModule} from './routing.module';
import {AcqSearchComponent} from './acq-search.component';
import {AcqSearchFormComponent} from './acq-search-form.component';
import {LineitemResultsComponent} from './lineitem-results.component';
import {PurchaseOrderResultsComponent} from './purchase-order-results.component';
import {InvoiceResultsComponent} from './invoice-results.component';
import {PicklistResultsComponent} from './picklist-results.component';
import {PicklistCreateDialogComponent} from './picklist-create-dialog.component';
import {PicklistCloneDialogComponent} from './picklist-clone-dialog.component';
import {PicklistDeleteDialogComponent} from './picklist-delete-dialog.component';
import {PicklistMergeDialogComponent} from './picklist-merge-dialog.component';

@NgModule({
  declarations: [
    AcqSearchComponent,
    AcqSearchFormComponent,
    LineitemResultsComponent,
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
    AcqSearchRoutingModule
  ]
})

export class AcqSearchModule {
}
