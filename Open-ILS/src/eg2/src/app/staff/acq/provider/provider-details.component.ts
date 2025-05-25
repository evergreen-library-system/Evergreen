import {Component, OnInit, Output, EventEmitter, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ProviderRecordService} from './provider-record.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    selector: 'eg-provider-details',
    templateUrl: 'provider-details.component.html',
})
export class ProviderDetailsComponent implements OnInit {

    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('editDialog', { static: false}) editDialog: FmRecordEditorComponent;

    provider: IdlObject;

    permissions: {[name: string]: boolean};

    @Output() desireSummarize: EventEmitter<number> = new EventEmitter<number>();

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private idl: IdlService,
        private auth: AuthService,
        private providerRecord: ProviderRecordService,
        private toast: ToastService) {
    }

    ngOnInit() {
        this.refresh();
    }

    _deflesh() {
        if (!this.provider) {
            return;
        }
        // unflesh the currency type and edi_default fields so that the
        // record editor can display them
        // TODO: make fm-editor be able to handle fleshed linked fields
        if (this.provider.currency_type()) {
            this.provider.currency_type(this.provider.currency_type().code());
        }
        if (this.provider.edi_default() && typeof this.provider.edi_default() !== 'number') {
            this.provider.edi_default(this.provider.edi_default().id());
        }
    }

    updateProvider(providerId: any) {
        this.desireSummarize.emit(this.provider.id());
    }

    refresh() {
        this.provider = this.idl.clone(this.providerRecord.current());
        this._deflesh();
    }

    permittedMode(): string {
        // TODO - looks like fm-editor may have (via its modePerms) incompletely-implemented
        //        work to vary the mode depending on whether the user has permission
        //        to update a record, which would make this moot.
        if (!this.providerRecord.currentProviderRecord()) {
            return 'view';
        }
        return this.providerRecord.currentProviderRecord().canAdmin ? 'update' : 'view';
    }

    isDirty(): boolean {
        return (this.editDialog) ? this.editDialog.isDirty() : false;
    }
}
