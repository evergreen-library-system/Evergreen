import {QRCodeComponent} from 'angularx-qrcode';

import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';

import {StaffComponent} from './staff.component';
import {StaffRoutingModule} from './routing.module';
import {StaffNavComponent} from './nav.component';
import {StaffLoginComponent} from './login.component';
import {StaffMFAComponent} from './mfa.component';
import {StaffSplashComponent, AutofocusDirective} from './splash.component';
import {AboutComponent} from './about.component';
import {StaffLoginNotAllowedComponent} from './login-not-allowed.component';
import { CommonWidgetsModule } from '@eg/share/common-widgets.module';

@NgModule({
    imports: [
        AboutComponent,
        AutofocusDirective,
        StaffCommonModule.forRoot(),
        StaffComponent,
        StaffLoginComponent,
        StaffLoginNotAllowedComponent,
        StaffMFAComponent,
        StaffNavComponent,
        StaffRoutingModule,
        StaffSplashComponent,
        QRCodeComponent,
        CommonWidgetsModule
    ]
})

export class StaffModule {}

