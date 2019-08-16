import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {StringModule} from '@eg/share/string/string.module';
import {TranslateModule} from '@eg/share/translate/translate.module';
import {FmRecordEditorComponent} from './fm-editor.component';
import {FmRecordEditorActionComponent} from './fm-editor-action.component';


@NgModule({
    declarations: [
        FmRecordEditorComponent,
        FmRecordEditorActionComponent
    ],
    imports: [
        EgCommonModule,
        StringModule,
        TranslateModule,
        CommonWidgetsModule
    ],
    exports: [
        FmRecordEditorComponent,
        FmRecordEditorActionComponent
    ],
    providers: [
    ]
})

export class FmRecordEditorModule { }

