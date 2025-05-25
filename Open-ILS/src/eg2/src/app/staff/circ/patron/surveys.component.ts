import {Component, Input, OnInit} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';

@Component({
    templateUrl: 'surveys.component.html',
    selector: 'eg-patron-survey-responses',
    styles: ['thead th { padding: 0.5rem; }']
})
export class PatronSurveyResponsesComponent implements OnInit {

    @Input() patronId: number;
    surveys: IdlObject[] = [];

    constructor(
        private router: Router,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
        this.surveys = [];

        const collection: {[survey_id: string]: {[question_id: string]: IdlObject}} = {};

        const myOrgs = this.org.fullPath(this.auth.user().ws_ou(), true);

        this.pcrud.search('asvr', {usr: 113}, {
            flesh: 1,
            flesh_fields: {asvr: ['survey', 'question', 'answer']}
        }).subscribe(
            { next: response => {

                const sid = response.survey().id();
                const qid = response.question().id();

                // Out of scope
                if (!myOrgs.includes(response.survey().owner())) { return; }

                if (!collection[sid]) { collection[sid] = {}; }

                if (!collection[sid][qid]) {
                    collection[sid][qid] = response;

                // We only care about the most recent response
                } else if (response.effective_date() >
                    collection[sid][qid].effective_date()) {
                    collection[sid][qid] = response;
                }
            }, error: (err: unknown) => console.error(err), complete: () => {

                Object.keys(collection).forEach(sid => {
                    const oneSurvey: any = {responses: []};
                    Object.keys(collection[sid]).forEach(qid => {
                        oneSurvey.survey = collection[sid][qid].survey();
                        oneSurvey.responses.push(collection[sid][qid]);
                    });
                    this.surveys.push(oneSurvey);
                });
            } }
        );
    }
}
