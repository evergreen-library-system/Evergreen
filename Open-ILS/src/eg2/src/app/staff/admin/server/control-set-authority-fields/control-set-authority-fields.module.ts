import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {CSAuthorityFieldsComponent} from './control-set-authority-fields.component';
import {CSAuthorityFieldsRoutingModule} from './control-set-authority-fields-routing.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';

@NgModule({
    imports: [
        CSAuthorityFieldsComponent,
        StaffCommonModule,
        FmRecordEditorModule,
        AdminPageModule,
        CSAuthorityFieldsRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class CSAuthorityFieldsModule {
}
