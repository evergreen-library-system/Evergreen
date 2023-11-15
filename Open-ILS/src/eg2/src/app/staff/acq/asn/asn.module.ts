import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {LineitemModule} from '@eg/staff/acq/lineitem/lineitem.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {AsnRoutingModule} from './routing.module';
import {AsnService} from './asn.service';
import {AsnComponent} from './asn.component';
import {AsnReceiveComponent} from './receive.component';


@NgModule({
    declarations: [
        AsnComponent,
        AsnReceiveComponent
    ],
    imports: [
        StaffCommonModule,
        CatalogCommonModule,
        LineitemModule,
        HoldingsModule,
        AsnRoutingModule
    ],
    providers: [
        AsnService
    ]
})

export class AsnModule {
}
