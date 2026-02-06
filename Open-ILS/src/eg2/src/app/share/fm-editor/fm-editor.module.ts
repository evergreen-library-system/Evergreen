import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {StringModule} from '@eg/share/string/string.module';
import {FmRecordEditorComponent} from './fm-editor.component';
import {FmRecordEditorActionComponent} from './fm-editor-action.component';
import { TranslateComponent } from '../translate/translate.component';
import { MaxValidatorDirective, MinValidatorDirective } from './validators.directive';


@NgModule({
    imports: [
        EgCommonModule,
        FmRecordEditorComponent,
        FmRecordEditorActionComponent,
        MaxValidatorDirective,
        MinValidatorDirective,
        StaffCommonModule,
        StringModule,
        TranslateComponent,
        CommonWidgetsModule
    ],
    exports: [
        FmRecordEditorComponent,
        FmRecordEditorActionComponent
    ]
})

export class FmRecordEditorModule { }

