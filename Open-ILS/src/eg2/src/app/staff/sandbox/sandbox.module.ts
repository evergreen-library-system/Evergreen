import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {SandboxRoutingModule} from './routing.module';
import {SandboxComponent} from './sandbox.component';
import {ReactiveFormsModule} from '@angular/forms';
import {SampleDataService} from '@eg/share/util/sample-data.service';

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
    SampleDataService
  ]
})

export class SandboxModule {

}
