import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {SurveyComponent} from './survey.component';
import {FormsModule} from '@angular/forms';
import {SurveyEditComponent} from './survey-edit.component';
import {SurveyRoutingModule} from './survey-routing.module';

@NgModule({
    imports: [
        AdminCommonModule,
        SurveyComponent,
        SurveyEditComponent,
        SurveyRoutingModule,
        FormsModule,
    ]
})

export class SurveyModule {
}
