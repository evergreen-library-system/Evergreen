import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {SandboxRoutingModule} from './routing.module';
import {SandboxComponent} from './sandbox.component';
import {FormsModule, ReactiveFormsModule} from '@angular/forms';

@NgModule({
  declarations: [
    SandboxComponent
  ],
  imports: [
    StaffCommonModule,
    SandboxRoutingModule,
    FormsModule,
    ReactiveFormsModule,
  ],
  providers: [
  ]
})

export class SandboxModule {

}
