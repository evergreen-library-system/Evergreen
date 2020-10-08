import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {ItemLocationSelectModule
    } from '@eg/share/item-location-select/item-location-select.module';
import {LineitemWorksheetComponent} from './worksheet.component';
import {LineitemService} from './lineitem.service';
import {LineitemComponent} from './lineitem.component';
import {LineitemNotesComponent} from './notes.component';
import {LineitemDetailComponent} from './detail.component';
import {LineitemOrderSummaryComponent} from './order-summary.component';
import {LineitemListComponent} from './lineitem-list.component';
import {LineitemCopiesComponent} from './copies.component';
import {LineitemBatchCopiesComponent} from './batch-copies.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';
import {LineitemHistoryComponent} from './history.component';
import {BriefRecordComponent} from './brief-record.component';
import {CancelDialogComponent} from './cancel-dialog.component';
import {MarcEditModule} from '@eg/staff/share/marc-edit/marc-edit.module';

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
    BriefRecordComponent,
    LineitemWorksheetComponent
  ],
  exports: [
    LineitemListComponent,
    CancelDialogComponent
  ],
  imports: [
    StaffCommonModule,
    ItemLocationSelectModule,
    MarcEditModule
  ],
  providers: [
    LineitemService
  ]
})

export class LineitemModule {
}
