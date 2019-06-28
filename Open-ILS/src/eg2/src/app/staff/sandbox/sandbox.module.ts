import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {SandboxRoutingModule} from './routing.module';
import {SandboxComponent} from './sandbox.component';
import {ReactiveFormsModule} from '@angular/forms';

@NgModule({
  declarations: [
    SandboxComponent
  ],
  imports: [
    StaffCommonModule,
    SandboxRoutingModule,
    ReactiveFormsModule
  ],
  providers: [
  ]
})

export class SandboxModule {

}
