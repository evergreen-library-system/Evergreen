import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CourseListComponent} from './course-list.component';
import {CourseReservesRoutingModule} from './routing.module';

@NgModule({
  declarations: [
    CourseListComponent
  ],
  imports: [
    AdminCommonModule,
    CourseReservesRoutingModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class CourseReservesModule {
}
