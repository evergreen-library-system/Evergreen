import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';

import {StaffComponent} from './staff.component';
import {StaffRoutingModule} from './routing.module';
import {StaffNavComponent} from './nav.component';
import {StaffLoginComponent} from './login.component';
import {StaffSplashComponent} from './splash.component';
import {AboutComponent} from './about.component';

@NgModule({
  declarations: [
    StaffComponent,
    StaffNavComponent,
    StaffSplashComponent,
    StaffLoginComponent,
    AboutComponent
  ],
  imports: [
    StaffCommonModule.forRoot(),
    StaffRoutingModule
  ]
})

export class StaffModule {}

