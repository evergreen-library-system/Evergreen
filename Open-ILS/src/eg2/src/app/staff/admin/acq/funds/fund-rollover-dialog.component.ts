import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';
import {OrgService} from '@eg/core/org.service';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-fund-rollover-dialog',
    templateUrl: './fund-rollover-dialog.component.html'
})

export class FundRolloverDialogComponent
    extends DialogComponent implements OnInit {

    doneLoading = false;

    @Input() contextOrgId: number;

    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('rolloverProgress', { static: true })
    private rolloverProgress: ProgressInlineComponent;

    includeDescendants = false;
    doCloseout = false;
    showEncumbOnly = false;
    limitToEncumbrances = false;
    dryRun = true;
    contextOrg: IdlObject;
    isProcessing = false;
    showResults = false;
    years: ComboboxEntry[];
    year: number;

    count: number;
    amount_rolled: number;
    encumb_rolled: number;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private perm: PermService,
        private toast: ToastService,
        private org: OrgService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(() => this._initDialog());
        this.doneLoading = true;
    }

    private _initDialog() {
        this.contextOrg = this.org.get(this.contextOrgId);
        this.includeDescendants = false;
        this.doCloseout = false;
        this.limitToEncumbrances = false;
        this.showResults = false;
        this.dryRun = true;
        this.years = null;
        this.year = null;
        let maxYear = 0;
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.fund.org.years.retrieve',
            this.auth.token(),
            {},
            { limit_perm: 'VIEW_FUND' }
        ).subscribe(
            years => {
                this.years = years.map(y => {
                    if (maxYear < y) { maxYear = y; }
                    return { id: y, label: y };
                });
                this.year = maxYear;
            }
        );
        this.showEncumbOnly = false;
        this.org.settings('acq.fund.allow_rollover_without_money', this.contextOrgId).then((ous) => {
            this.showEncumbOnly = ous['acq.fund.allow_rollover_without_money'];
        });
    }

    rollover() {
        this.isProcessing = true;

        const rolloverResponses: any = [];

        let method = 'open-ils.acq.fiscal_rollover';
        if (this.doCloseout) {
            method += '.combined';
        } else {
            method += '.propagate';
        }
        if (this.dryRun) { method += '.dry_run'; }

        this.count = 0;
        this.amount_rolled = 0;
        this.encumb_rolled = 0;

        this.net.request(
            'open-ils.acq',
            method,
            this.auth.token(),
            this.year,
            this.contextOrgId,
            this.includeDescendants,
            { encumb_only : this.limitToEncumbrances }
        ).subscribe(
            { next: r => {
                rolloverResponses.push(r.fund);
                this.count++;
                this.amount_rolled += Number(r.rollover_amount);
                this.encumb_rolled += Number(r.encumb_amount);
            }, error: (err: unknown) => {}, complete: () => {
                this.isProcessing = false;
                this.showResults = true;
                if (!this.dryRun) {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                }
                // note that we're intentionally not closing the dialog
                // so that user can view the results
            } }
        );
    }

}
