
import {Component, OnInit, ViewChild, Input, TemplateRef} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {FormatService} from '@eg/core/format.service';
import {Pager} from '@eg/share/util/pager';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';

@Component({
  templateUrl: 'hopeless.component.html'
})
export class HopelessComponent implements OnInit {

    startDate: any;
    endDate: any;
    workstation_lib: IdlObject;

    changeStartDate(date) {
        this.startDate = date;
    }

    changeEndDate(date) {
        date.setHours(23);
        date.setMinutes(59);
        date.setSeconds(59);
        this.endDate = date;
    }

    constructor(
        private pcrud: PcrudService,
        private auth: AuthService,
        private format: FormatService,
        private bib: BibRecordService,
    ) {}

    ngOnInit() {

        // for the pickup library selector
        this.workstation_lib = this.auth.user().ws_ou();

        // Default startDate to today - 10 years
        const sd = new Date();
        sd.setFullYear( sd.getFullYear() - 10 );
        this.startDate = sd.toISOString();

        // Default endDate to today.
        const ed = new Date();
        ed.setHours(23);
        ed.setMinutes(59);
        ed.setSeconds(59);
        this.endDate = ed.toISOString();

    }

}


