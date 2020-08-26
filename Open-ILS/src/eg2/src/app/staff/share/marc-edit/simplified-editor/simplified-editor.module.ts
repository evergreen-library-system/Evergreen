import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {MarcSimplifiedEditorComponent} from './simplified-editor.component';
import {MarcSimplifiedEditorFieldDirective} from './simplified-editor-field.directive';
import {MarcSimplifiedEditorSubfieldDirective} from './simplified-editor-subfield.directive';
import {TagTableService} from '../tagtable.service';

@NgModule({
    declarations: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldDirective,
        MarcSimplifiedEditorSubfieldDirective,
    ],
    imports: [
        StaffCommonModule,
        CommonWidgetsModule
    ],
    exports: [
        MarcSimplifiedEditorComponent,
        MarcSimplifiedEditorFieldDirective,
        MarcSimplifiedEditorSubfieldDirective
    ],
    providers: [
        TagTableService
    ]
})

export class MarcSimplifiedEditorModule { }

