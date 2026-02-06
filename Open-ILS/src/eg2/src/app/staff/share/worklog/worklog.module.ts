import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {WorkLogService} from './worklog.service';
import {WorkLogStringsComponent} from './strings.component';

@NgModule({
    imports: [
        StaffCommonModule,
        WorkLogStringsComponent
    ],
    exports: [
        WorkLogStringsComponent
    ],
    providers: [
        WorkLogService
    ]
})

export class WorkLogModule {}
