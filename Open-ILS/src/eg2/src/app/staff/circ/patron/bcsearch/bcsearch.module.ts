import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BcSearchRoutingModule} from './routing.module';
import {BcSearchComponent} from './bcsearch.component';

@NgModule({
  declarations: [
    BcSearchComponent
  ],
  imports: [
    StaffCommonModule,
    BcSearchRoutingModule,
  ],
})

export class BcSearchModule {}

