import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {MarcEditorComponent} from './editor.component';
import {MarcRichEditorComponent} from './rich-editor.component';
import {MarcFlatEditorComponent} from './flat-editor.component';
import {FixedFieldsEditorComponent} from './fixed-fields-editor.component';
import {FixedFieldComponent} from './fixed-field.component';
import {TagTableService} from './tagtable.service';
import {EditableContentComponent} from './editable-content.component';

@NgModule({
    declarations: [
        MarcEditorComponent,
        MarcRichEditorComponent,
        MarcFlatEditorComponent,
        FixedFieldsEditorComponent,
        FixedFieldComponent,
        EditableContentComponent
    ],
    imports: [
        StaffCommonModule,
        CommonWidgetsModule
    ],
    exports: [
        MarcEditorComponent
    ],
    providers: [
        TagTableService
    ]
})

export class MarcEditModule { }

