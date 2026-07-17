import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {ShelvingLocationGroupsComponent} from './shelving_location_groups.component';
import {ShelvingLocationGroupsRoutingModule} from './shelving_location_groups_routing.module';

@NgModule({
    imports: [
        AdminCommonModule,
        ShelvingLocationGroupsComponent,
        ShelvingLocationGroupsRoutingModule,
    ],
    exports: [],
    providers: []
})

export class ShelvingLocationGroupsModule {}
