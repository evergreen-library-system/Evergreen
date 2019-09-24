import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {SurveyComponent} from './survey.component';
import {FormsModule} from '@angular/forms';
import {SurveyEditComponent} from './survey-edit.component';
import {SurveyRoutingModule} from './survey-routing.module';

@NgModule({
  declarations: [
    SurveyComponent,
    SurveyEditComponent
  ],
  imports: [
    AdminCommonModule,
    SurveyRoutingModule,
    FormsModule,
  ],
  exports: [
  ],
  providers: [
  ]
})

export class SurveyModule {
}
