import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SurveyComponent} from './survey.component';
import {SurveyEditComponent} from './survey-edit.component';

const routes: Routes = [{
    path: '',
    component: SurveyComponent
}, {
    path: ':id',
    component: SurveyEditComponent
}];


@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class SurveyRoutingModule {}


