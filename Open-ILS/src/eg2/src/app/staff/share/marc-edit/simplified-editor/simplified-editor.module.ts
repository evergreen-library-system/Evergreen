import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {MarcSimplifiedEditorComponent} from './simplified-editor.component';
import {MarcSimplifiedEditorFieldComponent} from './simplified-editor-field.component';
import {MarcSimplifiedEditorSubfieldComponent} from './simplified-editor-subfield.component';
import {TagTableService} from '../tagtable.service';

@NgModule({
    imports: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldComponent,
        MarcSimplifiedEditorSubfieldComponent,
        StaffCommonModule,
        CommonWidgetsModule
    ],
    exports: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldComponent,
        MarcSimplifiedEditorSubfieldComponent
    ],
    providers: [
        TagTableService
    ]
})

export class MarcSimplifiedEditorModule { }

