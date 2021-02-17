import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BarcodeSelectComponent} from './barcode-select.component';

@NgModule({
    declarations: [
        BarcodeSelectComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
        BarcodeSelectComponent
    ],
    providers: [
    ]
})

export class BarcodesModule {}
