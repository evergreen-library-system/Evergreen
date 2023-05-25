import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {AcqCommonModule} from '@eg/staff/acq/acq-common.module';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {ClaimRoutingModule} from './routing.module';
import {ClaimService} from './claim.service';
import {ClaimEligibleListComponent} from './list.component';


@NgModule({
    declarations: [
        ClaimEligibleListComponent,
    ],
    imports: [
        StaffCommonModule,
        CatalogCommonModule,
        AcqCommonModule,
        LineitemModule,
        HoldingsModule,
        ClaimRoutingModule,
    ],
    providers: [
        ClaimService
    ]
})

export class ClaimModule {
}
