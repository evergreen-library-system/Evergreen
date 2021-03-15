import {NgModule} from '@angular/core';
import {PatronRoutingModule} from './routing.module';
import {PatronResolver} from './resolver.service';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';
import {BillingModule} from '@eg/staff/share/billing/billing.module';
import {CircModule} from '@eg/staff/share/circ/circ.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {BookingModule} from '@eg/staff/share/booking/booking.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {PatronContextService} from './patron.service';
import {PatronComponent} from './patron.component';
import {PatronAlertsComponent} from './alerts.component';
import {SummaryComponent} from './summary.component';
import {CheckoutComponent} from './checkout.component';
import {HoldsComponent} from './holds.component';
import {EditComponent} from './edit.component';
import {EditToolbarComponent} from './edit-toolbar.component';
import {BcSearchComponent} from './bcsearch.component';
import {BarcodesModule} from '@eg/staff/share/barcodes/barcodes.module';
import {ItemsComponent} from './items.component';
import {BillsComponent} from './bills.component';
import {BillStatementComponent} from './bill-statement.component';
import {TestPatronPasswordComponent} from './test-password.component';

@NgModule({
  declarations: [
    PatronComponent,
    PatronAlertsComponent,
    SummaryComponent,
    CheckoutComponent,
    HoldsComponent,
    EditComponent,
    EditToolbarComponent,
    BcSearchComponent,
    ItemsComponent,
    BillsComponent,
    BillStatementComponent,
    TestPatronPasswordComponent
  ],
  imports: [
    StaffCommonModule,
    FmRecordEditorModule,
    BillingModule,
    CircModule,
    HoldsModule,
    HoldingsModule,
    BookingModule,
    PatronModule,
    PatronRoutingModule,
    BarcodesModule
  ],
  providers: [
    PatronResolver,
    PatronContextService
  ]
})

export class PatronManagerModule {}

