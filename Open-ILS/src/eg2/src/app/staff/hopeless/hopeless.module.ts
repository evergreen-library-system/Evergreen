import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CatalogCommonModule} from '@eg/share/catalog/catalog-common.module';
import {HopelessRoutingModule} from './routing.module';
import {HopelessComponent} from './hopeless.component';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';

@NgModule({
  declarations: [
    HopelessComponent
  ],
  imports: [
    StaffCommonModule,
    CatalogCommonModule,
    HopelessRoutingModule,
    HoldsModule
  ],
  providers: [
  ]
})

export class HopelessModule {

}
