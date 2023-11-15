import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {ItemEventLogRoutingModule} from './routing.module';
import {ItemEventGridComponent} from './event-grid.component';
import {ItemEventLogComponent} from './event-log.component';

@NgModule({
    declarations: [
        ItemEventGridComponent,
        ItemEventLogComponent
    ],
    imports: [
        StaffCommonModule,
        ItemEventLogRoutingModule,
    ],
})

export class ItemEventLogModule {}

