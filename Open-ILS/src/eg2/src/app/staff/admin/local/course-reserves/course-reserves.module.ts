import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CourseListComponent} from './course-list.component';
import {CourseAssociateMaterialComponent} from './course-associate-material.component';
import {CourseReservesRoutingModule} from './routing.module';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import {CourseService} from '@eg/staff/share/course.service';

@NgModule({
  declarations: [
    CourseListComponent,
    CourseAssociateMaterialComponent
  ],
  imports: [
    AdminCommonModule,
    CourseReservesRoutingModule,
    ItemLocationSelectModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
    CourseService
  ]
})

export class CourseReservesModule {
}
