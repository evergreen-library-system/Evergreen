import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {PicklistRoutingModule} from './routing.module';
import {PicklistComponent} from './picklist.component';
import {PicklistSummaryComponent} from './summary.component';
import {HttpClientModule} from '@angular/common/http';
import {AcqCommonModule} from '../acq-common.module';
import {Z3950SearchModule} from '@eg/staff/share/z3950-search/z3950-search.module';

@NgModule({
    declarations: [
        PicklistComponent,
        PicklistSummaryComponent
    ],
    imports: [
        Z3950SearchModule,
        StaffCommonModule,
        CatalogCommonModule,
        LineitemModule,
        HoldingsModule,
        PicklistRoutingModule,
        HttpClientModule,
        AcqCommonModule
    ],
    providers: []
})

export class PicklistModule {}
