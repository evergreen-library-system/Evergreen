import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {EgCoreModule} from '@eg/core/core.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {ItemLocationSelectComponent} from './item-location-select.component';
import {ReactiveFormsModule} from '@angular/forms';
import {ItemLocationService} from './item-location-select.service';

@NgModule({
    declarations: [
        ItemLocationSelectComponent
    ],
    imports: [
        EgCommonModule,
        EgCoreModule,
        CommonWidgetsModule,
        ReactiveFormsModule
    ],
    exports: [
        ItemLocationSelectComponent
    ],
    providers: [
        ItemLocationService
    ]
})

export class ItemLocationSelectModule { }

