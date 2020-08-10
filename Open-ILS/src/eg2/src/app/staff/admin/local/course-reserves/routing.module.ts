import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {CourseListComponent} from './course-list.component';
import {CoursePageComponent} from './course-page.component';

const routes: Routes = [{
    path: ':id',
    component: CoursePageComponent
}, {
    path: '',
    component: CourseListComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CourseReservesRoutingModule {}
