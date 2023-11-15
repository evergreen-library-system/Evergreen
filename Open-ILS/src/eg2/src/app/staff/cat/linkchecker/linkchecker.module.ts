import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {LinkCheckerRoutingModule} from './routing.module';
import {LinkCheckerComponent} from './linkchecker.component';
import {LinkCheckerUrlsComponent} from './urls.component';
import {LinkCheckerAttemptsComponent} from './attempts.component';
import {NewSessionDialogComponent} from './new-session-dialog.component';
import {HttpClientModule} from '@angular/common/http';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';

@NgModule({
    declarations: [
        LinkCheckerComponent,
        LinkCheckerUrlsComponent,
        LinkCheckerAttemptsComponent,
        NewSessionDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AdminCommonModule,
        HttpClientModule,
        CommonWidgetsModule,
        OrgFamilySelectModule,
        LinkCheckerRoutingModule
    ],
    providers: [
    ]
})

export class LinkCheckerModule {
}
