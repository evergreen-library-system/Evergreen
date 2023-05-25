import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {AcqCommonModule} from '@eg/staff/acq/acq-common.module';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {PoRoutingModule} from './routing.module';
import {PoService} from './po.service';
import {PoComponent} from './po.component';
import {PrintComponent} from './print.component';
import {PoSummaryComponent} from './summary.component';
import {PoHistoryComponent} from './history.component';
import {PoEdiMessagesComponent} from './edi.component';
import {PoNotesComponent} from './notes.component';
import {PoCreateComponent} from './create.component';
import {PoChargesComponent} from './charges.component';
import {PicklistUploadService} from '../picklist/upload.service';
import {DisencumberChargeDialogComponent} from './disencumber-charge-dialog.component';

@NgModule({
    declarations: [
        PoComponent,
        PoSummaryComponent,
        PoHistoryComponent,
        PoEdiMessagesComponent,
        PoNotesComponent,
        PoCreateComponent,
        PoChargesComponent,
        PrintComponent,
        DisencumberChargeDialogComponent
    ],
    imports: [
        StaffCommonModule,
        CatalogCommonModule,
        AcqCommonModule,
        LineitemModule,
        HoldingsModule,
        PoRoutingModule
    ],
    providers: [
        PoService,
        PicklistUploadService
    ]
})

export class PoModule {
}
