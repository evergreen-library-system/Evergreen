import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {SandboxRoutingModule} from './routing.module';
import {SandboxComponent} from './sandbox.component';

@NgModule({
  declarations: [
    SandboxComponent
  ],
  imports: [
    StaffCommonModule,
    SandboxRoutingModule,
  ],
  providers: [
  ]
})

export class SandboxModule {

}
