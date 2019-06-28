import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {MarcEditorComponent} from './editor.component';
import {MarcRichEditorComponent} from './rich-editor.component';
import {MarcFlatEditorComponent} from './flat-editor.component';

@NgModule({
    declarations: [
        MarcEditorComponent,
        MarcRichEditorComponent,
        MarcFlatEditorComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
        MarcEditorComponent
    ],
    providers: [
    ]
})

export class MarcEditModule { }

