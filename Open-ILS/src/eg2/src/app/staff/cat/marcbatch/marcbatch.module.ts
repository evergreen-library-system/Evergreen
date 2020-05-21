import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {MarcBatchRoutingModule} from './routing.module';
import {MarcBatchComponent} from './marcbatch.component';
import {HttpClientModule} from '@angular/common/http';

@NgModule({
  declarations: [
    MarcBatchComponent
  ],
  imports: [
    StaffCommonModule,
    HttpClientModule,
    CommonWidgetsModule,
    MarcBatchRoutingModule
  ],
  providers: [
  ]
})

export class MarcBatchModule {
}
