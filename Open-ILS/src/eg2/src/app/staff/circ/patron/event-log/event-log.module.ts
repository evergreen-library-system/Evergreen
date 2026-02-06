import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {EventLogRoutingModule} from './routing.module';
import {EventGridComponent} from './event-grid.component';
import {EventLogComponent} from './event-log.component';

@NgModule({
    imports: [
        EventGridComponent,
        EventLogComponent,
        StaffCommonModule,
        EventLogRoutingModule,
    ],
})

export class EventLogModule {}

