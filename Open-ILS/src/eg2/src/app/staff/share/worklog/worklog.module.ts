import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {WorkLogService} from './worklog.service';
import {WorkLogStringsComponent} from './strings.component';

@NgModule({
    declarations: [
        WorkLogStringsComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
        WorkLogStringsComponent
    ],
    providers: [
        WorkLogService
    ]
})

export class WorkLogModule {}
