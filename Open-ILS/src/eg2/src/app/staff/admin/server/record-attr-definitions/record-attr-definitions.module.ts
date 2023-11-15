import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {RecordAttrDefinitionsComponent} from './record-attr-definitions.component';
import {RecordAttrDefinitionsRoutingModule} from './record-attr-definitions-routing.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';

@NgModule({
    declarations: [
        RecordAttrDefinitionsComponent
    ],
    imports: [
        StaffCommonModule,
        FmRecordEditorModule,
        AdminPageModule,
        RecordAttrDefinitionsRoutingModule
    ],
    exports: [
    ],
    providers: [
    ]
})

export class RecordAttrDefinitionsModule {
}
