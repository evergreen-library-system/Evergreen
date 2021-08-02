import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';

import {StaffComponent} from './staff.component';
import {StaffRoutingModule} from './routing.module';
import {StaffNavComponent} from './nav.component';
import {StaffLoginComponent} from './login.component';
import {StaffSplashComponent, AutofocusDirective} from './splash.component';
import {AboutComponent} from './about.component';

@NgModule({
  declarations: [
    StaffComponent,
    StaffNavComponent,
    StaffSplashComponent,
    AutofocusDirective,
    StaffLoginComponent,
    AboutComponent
  ],
  imports: [
    StaffCommonModule.forRoot(),
    StaffRoutingModule
  ]
})

export class StaffModule {}

