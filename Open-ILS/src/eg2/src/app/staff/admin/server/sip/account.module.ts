import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {SipAccountRoutingModule} from './routing.module';
import {SipAccountListComponent} from './account-list.component';
import {SipAccountComponent} from './account.component';
import {DeleteGroupDialogComponent} from './delete-group-dialog.component';

@NgModule({
    imports: [
        AdminCommonModule,
        DeleteGroupDialogComponent,
        SipAccountComponent,
        SipAccountListComponent,
        SipAccountRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class SipAccountModule {
}


