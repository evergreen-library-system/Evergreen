import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {EdiAttrSetsRoutingModule} from './routing.module';
import {EdiAttrSetsComponent} from './edi-attr-sets.component';
import {EdiAttrSetProvidersDialogComponent} from './edi-attr-set-providers-dialog.component';
import {EdiAttrSetProvidersComponent} from './edi-attr-set-providers.component';
import {EdiAttrSetEditDialogComponent} from './edi-attr-set-edit-dialog.component';

@NgModule({
    declarations: [
        EdiAttrSetsComponent,
        EdiAttrSetProvidersDialogComponent,
        EdiAttrSetProvidersComponent,
        EdiAttrSetEditDialogComponent
    ],
    imports: [
        StaffCommonModule,
        AdminCommonModule,
        EdiAttrSetsRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class EdiAttrSetsModule {
}
