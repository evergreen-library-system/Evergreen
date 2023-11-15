import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {ShelvingLocationGroupsComponent} from './shelving_location_groups.component';
import {ShelvingLocationGroupsRoutingModule} from './shelving_location_groups_routing.module';

@NgModule({
    declarations: [
        ShelvingLocationGroupsComponent,
    ],
    imports: [
        AdminCommonModule,
        ShelvingLocationGroupsRoutingModule,
    ],
    exports: [],
    providers: []
})

export class ShelvingLocationGroupsModule {}
