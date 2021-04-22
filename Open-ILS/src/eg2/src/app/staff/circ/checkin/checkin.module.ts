import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CheckinRoutingModule} from './routing.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';
import {BillingModule} from '@eg/staff/share/billing/billing.module';
import {CircModule} from '@eg/staff/share/circ/circ.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {BookingModule} from '@eg/staff/share/booking/booking.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {BarcodesModule} from '@eg/staff/share/barcodes/barcodes.module';
import {CheckinComponent} from './checkin.component';
import {WorkLogModule} from '@eg/staff/share/worklog/worklog.module';

@NgModule({
  declarations: [
    CheckinComponent
  ],
  imports: [
    StaffCommonModule,
    CheckinRoutingModule,
    FmRecordEditorModule,
    BillingModule,
    CircModule,
    HoldsModule,
    HoldingsModule,
    BookingModule,
    PatronModule,
    BarcodesModule,
    WorkLogModule
  ],
  providers: [
  ]
})

export class CheckinModule {}

