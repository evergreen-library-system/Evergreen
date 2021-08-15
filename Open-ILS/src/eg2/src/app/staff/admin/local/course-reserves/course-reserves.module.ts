import {NgModule} from '@angular/core';
import {TreeModule} from '@eg/share/tree/tree.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {CourseListComponent} from './course-list.component';
import {CoursePageComponent} from './course-page.component';
import {CourseAssociateMaterialComponent} from './course-associate-material.component';
import {CourseAssociateUsersComponent} from './course-associate-users.component';
import {CourseReservesRoutingModule} from './routing.module';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import {MarcSimplifiedEditorModule} from '@eg/staff/share/marc-edit/simplified-editor/simplified-editor.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {CourseTermMapComponent} from './course-term-map.component';
import {CourseTermMapGridComponent} from './course-term-map-grid.component';

@NgModule({
  declarations: [
    CourseListComponent,
    CoursePageComponent,
    CourseAssociateMaterialComponent,
    CourseAssociateUsersComponent,
    CourseTermMapComponent,
    CourseTermMapGridComponent
  ],
  imports: [
    StaffCommonModule,
    AdminCommonModule,
    CourseReservesRoutingModule,
    ItemLocationSelectModule,
    MarcSimplifiedEditorModule,
    PatronModule,
    TreeModule
  ],
  exports: [
  ],
  providers: [
  ]
})

export class CourseReservesModule {
}
