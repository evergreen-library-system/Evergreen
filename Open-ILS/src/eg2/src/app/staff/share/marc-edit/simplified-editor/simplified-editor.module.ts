import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {MarcSimplifiedEditorComponent} from './simplified-editor.component';
import {MarcSimplifiedEditorFieldComponent} from './simplified-editor-field.component';
import {TagTableService} from '../tagtable.service';

@NgModule({
    declarations: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldComponent,
    ],
    imports: [
        StaffCommonModule,
        CommonWidgetsModule
    ],
    exports: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldComponent,
    ],
    providers: [
        TagTableService
    ]
})

export class MarcSimplifiedEditorModule { }

