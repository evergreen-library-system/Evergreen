import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {EgCoreModule} from '@eg/core/core.module';
import {TranslateComponent} from './translate.component';


@NgModule({
    declarations: [
        TranslateComponent
    ],
    imports: [
        EgCommonModule,
        EgCoreModule
    ],
    exports: [
        TranslateComponent
    ],
    providers: [
    ]
})

export class TranslateModule { }

