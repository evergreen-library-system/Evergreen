import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {UploadComponent} from './picklist/upload.component';

@NgModule({
    declarations: [
        UploadComponent
    ],
    exports: [
        UploadComponent
    ],
    imports: [
        StaffCommonModule
    ],
    providers: []
})

export class AcqCommonModule {
}
