import {NgModule} from '@angular/core';
import {PatronRoutingModule} from './routing.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';
import {CircModule} from '@eg/staff/share/circ/circ.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {BookingModule} from '@eg/staff/share/booking/booking.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {PatronManagerService} from './patron.service';
import {PatronComponent} from './patron.component';
import {SummaryComponent} from './summary.component';
import {CheckoutComponent} from './checkout.component';
import {HoldsComponent} from './holds.component';
import {EditComponent} from './edit.component';
import {EditToolbarComponent} from './edit-toolbar.component';
import {BcSearchComponent} from './bcsearch.component';
import {PrecatCheckoutDialogComponent} from './precat-dialog.component';
import {BarcodesModule} from '@eg/staff/share/barcodes/barcodes.module';
import {ItemsComponent} from './items.component';

@NgModule({
  declarations: [
    PatronComponent,
    SummaryComponent,
    CheckoutComponent,
    HoldsComponent,
    EditComponent,
    EditToolbarComponent,
    BcSearchComponent,
    ItemsComponent,
    PrecatCheckoutDialogComponent
  ],
  imports: [
    StaffCommonModule,
    FmRecordEditorModule,
    CircModule,
    HoldsModule,
    HoldingsModule,
    BookingModule,
    PatronModule,
    PatronRoutingModule,
    BarcodesModule
  ],
  providers: [
    PatronManagerService
  ]
})

export class PatronManagerModule {}

