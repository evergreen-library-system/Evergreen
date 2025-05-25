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
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {Observable, map} from 'rxjs';

@Component({
    selector: 'eg-fund-transfer-dialog',
    templateUrl: './fund-transfer-dialog.component.html'
})

export class FundTransferDialogComponent
    extends DialogComponent implements OnInit {

    @Input() sourceFund: IdlObject;
    doneLoading = false;

    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('fundSelector', { static: false }) tagSelector: ComboboxComponent;

    fundDataSource: (term: string) => Observable<ComboboxEntry>;
    destFund: ComboboxEntry = null;
    sourceAmount = null;
    note = null;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private perm: PermService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.destFund = null;
        this.onOpen$.subscribe(() => this._initRecord());
        this.fundDataSource = term => {
            const field = 'code';
            const args = {};
            const extra_args = { order_by : {} };
            args[field] = {'ilike': `%${term}%`}; // could -or search on label
            args['active'] = 't';
            extra_args['order_by']['acqf'] = field;
            extra_args['limit'] = 100;
            extra_args['flesh'] = 1;
            const flesh_fields: Object = {};
            flesh_fields['acqf'] = ['org'];
            extra_args['flesh_fields'] = flesh_fields;
            return this.pcrud.search('acqf', args, extra_args).pipe(map(data => {
                return {
                    id: data.id(),
                    label: data.code()
                           + ' (' + data.year() + ')'
                           + ' (' + data.org().shortname() + ')',
                    fm: data
                };
            }));
        };
    }

    private _initRecord() {
        this.doneLoading = false;
        this.destFund = { id: null }; // destFund is a ComoboxEntry, so
        // we need to clear it like this
        this.sourceAmount = null;
        this.note = null;
        this.doneLoading = true;
    }

    transfer() {
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.funds.transfer_money',
            this.auth.token(),
            this.sourceFund.id(),
            this.sourceAmount,
            this.destFund.id,
            null,
            this.note
        ).subscribe(
            { next: res => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                this.close(true);
            }, error: (res: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
                this.close(false);
            } }
        );
    }

}
