import {Component, OnInit, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService } from '@eg/core/idl.service';
import {NgbNavChangeEvent, NgbNavModule} from '@ng-bootstrap/ng-bootstrap';
import { FmRecordEditorModule } from '@eg/share/fm-editor/fm-editor.module';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: './survey-edit.component.html',
    imports: [
        FmRecordEditorModule,
        NgbNavModule,
        StaffCommonModule
    ]
})

export class SurveyEditComponent implements OnInit {
    surveyId: number;
    surveyObj: IdlObject;
    localArray: any;
    newAnswerArray: object[];
    newQuestionText: string;
    surveyTab: string;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;

    constructor(
        private auth: AuthService,
        private net: NetService,
        private route: ActivatedRoute,
        private toast: ToastService,
        private idl: IdlService,
    ) {
    }

    ngOnInit() {
        this.surveyId = parseInt(this.route.snapshot.paramMap.get('id'), 10);
        this.updateData();
    }

    updateData() {
        this.newQuestionText = '';
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.fleshed.retrieve',
            this.surveyId
        ).subscribe(res => {
            this.setRecord(res);
            return res;
        });
    }

    onNavChange(event: NgbNavChangeEvent) {
        this.surveyTab = event.nextId;
    }

    setRecord(record: IdlObject) {
        // Unlike most PCRUD calls, this API uses 0 and 1 (rather than 'f' and 't') to represent boolean values
        // We need to normalize them before the FieldMapper Editor (which can handle booleans or 'f' and 't') sees them.
        const normalizeBooleanValue = (value: number) => {
            switch (value) {
                case 0:
                    return false;
                case 1:
                    return true;
                default:
                    return value;
            }
        };
        this.booleanFieldNames.forEach(field => record[field](normalizeBooleanValue(record[field]())));
        this.surveyObj = record;
        this.buildLocalArray(record);
    }

    buildLocalArray(res) {
        this.localArray = [];
        this.newAnswerArray = [];
        const allQuestions = res.questions();
        allQuestions.forEach((question, index) => {
            this.newAnswerArray.push({inputText: ''});
            question.words = question.question();
            question.answers = question.answers();
            this.localArray.push(question);
            question.answers.forEach(answer => {
                answer.words = answer.answer();
            });
            this.sortAnswers(index);
        });
        this.sortQuestions();
    }

    sortQuestions() {
        this.localArray.sort(function(a, b) {
            const q1 = a.question().toUpperCase();
            const q2 = b.question().toUpperCase();
            return (q1 < q2) ? -1 : (q1 > q2) ? 1 : 0;
        });
    }

    sortAnswers(questionIndex) {
        this.localArray[questionIndex].answers.sort(function(a, b) {
            const a1 = a.answer().toUpperCase();
            const a2 = b.answer().toUpperCase();
            return (a1 < a2) ? -1 : (a1 > a2) ? 1 : 0;
        });
    }

    updateQuestion(questionToChange) {
        if (this.surveyHasBegun()) {
            return;
        }
        questionToChange.question(questionToChange.words);
        questionToChange.ischanged(true);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Survey Question update failed`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`Survey Question updated`);
                return res;
            }
        });
    }

    deleteQuestion(questionToDelete) {
        if (this.surveyHasBegun()) {
            return;
        }
        questionToDelete.isdeleted(true);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Survey Question deletion failed`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`Survey Question deleted`);
                return res;
            }

        });
    }

    createQuestion(newQuestionText) {
        if (this.surveyHasBegun()) {
            return;
        }
        const newQuestion = this.idl.create('asvq');
        newQuestion.question(newQuestionText);
        newQuestion.isnew(true);
        let questionObjects = [];
        questionObjects = this.surveyObj.questions();
        questionObjects.push(newQuestion);
        this.surveyObj.questions(questionObjects);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.newQuestionText = '';
                this.toast.warning($localize`Failed to Create New Question`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.newQuestionText = '';
                this.toast.success($localize`New Question Added`);
                return res;
            }

        });
    }

    deleteAnswer(answerObj) {
        if (this.surveyHasBegun()) {
            return;
        }
        answerObj.isdeleted(true);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Survey Answer deletion failed`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`Survey Answer deleted`);
                return res;
            }
        });
    }

    updateAnswer(answerObj) {
        if (this.surveyHasBegun()) {
            return;
        }
        answerObj.answer(answerObj.words);
        answerObj.ischanged(true);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Survey Answer update failed`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`Survey Answer updated`);
                return res;
            }
        });
    }

    createAnswer(newAnswerText, questionObj) {
        // Create answer *is* allowed if survey has already begun
        const questionId = questionObj.id();
        const newAnswer = this.idl.create('asva');
        newAnswer.answer(newAnswerText);
        newAnswer.question(questionId);
        newAnswer.isnew(true);
        questionObj.answers.push(newAnswer);
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), this.surveyObj
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Failed to Create New Answer`);
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`New Answer Added`);
                return res;
            }
        });
    }

    endSurvey() {
        const today = new Date().toISOString();
        this.surveyObj.end_date(today);
        this.surveyObj.ischanged(true);
        // to get fm-editor to display changed date we need to set
        // this.surveyObj to null temporarily
        const surveyClone = this.idl.clone(this.surveyObj);
        this.surveyObj = null;
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.survey.update',
            this.auth.token(), surveyClone
        ).subscribe(res => {
            if (res.debug) {
                this.toast.warning($localize`Ending Survey failed or was not allowed`);
                return res;
            } else {
                this.surveyObj = res;
                this.surveyObj.ischanged(false);
                this.buildLocalArray(this.surveyObj);
                this.toast.success($localize`Survey ended`);
                return res;
            }
        });
    }

    surveyHasBegun() {
        const surveyStartDate = new Date(this.surveyObj.start_date());
        const now = new Date();
        if (surveyStartDate <= now) {
            this.toast.warning(
                $localize`The survey Start Date must be set for the future to add new questions or modify existing questions.`
            );
            return true;
        }
        return false;
    }

    private get booleanFieldNames(): string[] {
        return this.idl.classes['asv'].fields
            .filter((field: any) => field.datatype === 'bool')
            .map((field: any) => field.name);
    }
}

