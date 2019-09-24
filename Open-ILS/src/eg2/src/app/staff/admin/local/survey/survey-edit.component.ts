import {Component, OnInit, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService } from '@eg/core/idl.service';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './survey-edit.component.html'
})

export class SurveyEditComponent implements OnInit {
    surveyId: number;
    surveyObj: IdlObject;
    localArray: any;
    newAnswerArray: object[];
    newQuestionText: string;
    surveyTab: string;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;

    @ViewChild('createAnswerString', { static: true })
        createAnswerString: StringComponent;
    @ViewChild('createAnswerErrString', { static: true })
        createAnswerErrString: StringComponent;
    @ViewChild('createQuestionString', { static: true })
        createQuestionString: StringComponent;
    @ViewChild('createQuestionErrString', { static: true })
        createQuestionErrString: StringComponent;

    @ViewChild('updateQuestionSuccessStr', { static: true })
        updateQuestionSuccessStr: StringComponent;
    @ViewChild('updateQuestionFailStr', { static: true })
        updateQuestionFailStr: StringComponent;
    @ViewChild('updateAnswerSuccessStr', { static: true })
        updateAnswerSuccessStr: StringComponent;
    @ViewChild('updateAnswerFailStr', { static: true })
        updateAnswerFailStr: StringComponent;

    @ViewChild('delAnswerSuccessStr', { static: true })
        delAnswerSuccessStr: StringComponent;
    @ViewChild('delAnswerFailStr', { static: true })
        delAnswerFailStr: StringComponent;
    @ViewChild('delQuestionSuccessStr', { static: true })
        delQuestionSuccessStr: StringComponent;
    @ViewChild('delQuestionFailStr', { static: true })
        delQuestionFailStr: StringComponent;

    @ViewChild('endSurveyFailedString', { static: true })
        endSurveyFailedString: StringComponent;
    @ViewChild('endSurveySuccessString', { static: true })
        endSurveySuccessString: StringComponent;
    @ViewChild('questionAlreadyStartedErrString', { static: true })
        questionAlreadyStartedErrString: StringComponent;

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
            this.surveyObj = res;
            this.buildLocalArray(res);
            return res;
        });
    }

    onTabChange(event: NgbTabChangeEvent) {
        this.surveyTab = event.nextId;
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
                this.updateQuestionFailStr.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.updateQuestionSuccessStr.current().then(msg => this.toast.success(msg));
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
                this.delQuestionFailStr.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.delQuestionSuccessStr.current().then(msg => this.toast.success(msg));
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
                this.createQuestionErrString.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.newQuestionText = '';
                this.createQuestionString.current().then(msg => this.toast.success(msg));
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
                this.delAnswerFailStr.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.delAnswerSuccessStr.current().then(msg => this.toast.success(msg));
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
                this.updateAnswerFailStr.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.updateAnswerSuccessStr.current().then(msg => this.toast.success(msg));
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
                this.createAnswerErrString.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.buildLocalArray(this.surveyObj);
                this.createAnswerString.current().then(msg => this.toast.success(msg));
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
                this.endSurveyFailedString.current().then(msg => this.toast.warning(msg));
                return res;
            } else {
                this.surveyObj = res;
                this.surveyObj.ischanged(false);
                this.buildLocalArray(this.surveyObj);
                this.endSurveySuccessString.current().then(msg => this.toast.success(msg));
                return res;
            }
        });
    }

    surveyHasBegun() {
        const surveyStartDate = new Date(this.surveyObj.start_date());
        const now = new Date();
        if (surveyStartDate <= now) {
            this.questionAlreadyStartedErrString.current().then(msg =>
                this.toast.warning(msg));
            return true;
        }
        return false;
    }
}

