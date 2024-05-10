/* eslint-disable */
import {Component, Input} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {ReporterService, SRTemplate} from '../share/reporter.service';
import * as moment from 'moment-timezone';

@Component({
    selector: 'eg-reporter-output-options',
    templateUrl: './reporter-output-options.component.html'
})

export class ReporterOutputOptionsComponent {

    @Input() advancedMode = false;
    @Input() disabled = false;
    @Input() templ: SRTemplate;
    @Input() readyToSchedule: () => boolean;
    @Input() saveTemplate: (args: any) => void;
    @Input() closeForm: (args: any) => void;

    constructor(
        private idl: IdlService,
        public RSvc: ReporterService
    ) { }

    canPivot() {
        return this.advancedMode
                && this.templ.aggregateDisplayFields().length > 0
                && this.templ.nonAggregateDisplayFields().length > 0;
    }

    folderNodeSelected(node) {
        if (node.callerData.folderIdl) { // folder clicked
            if (node.callerData.folderIdl.classname === 'rrf') { // report folder
                this.RSvc.reportFolder = node.callerData.folderIdl;
            } else { // output folder
                this.RSvc.outputFolder = node.callerData.folderIdl;
            }
        }
    }

    defaultTime() {
        // When changing to Later for the first time default minutes to the quarter hour
        if (this.templ.runNow === 'later' && this.templ.runTime === null) {
            const now = moment();
            const nextQ = now.add(15 - (now.minutes() % 15), 'minutes');
            this.templ.runTime = nextQ;
        }
    }

}
