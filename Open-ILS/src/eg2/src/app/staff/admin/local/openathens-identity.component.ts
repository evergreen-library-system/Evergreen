import {Component, OnInit} from '@angular/core';
import {Location} from '@angular/common';
import {ActivatedRoute} from '@angular/router';
import {FormatService} from '@eg/core/format.service';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './openathens-identity.component.html'
})
export class OpenAthensIdentityComponent extends AdminPageComponent implements OnInit {

    idlClass = 'coai';
    classLabel: string;

    constructor(
        route: ActivatedRoute,
        ngLocation: Location,
        format: FormatService,
        idl: IdlService,
        org: OrgService,
        auth: AuthService,
        pcrud: PcrudService,
        perm: PermService,
        toast: ToastService,
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast);
    }

    ngOnInit() {
        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
    }

    createNew = () => {
        this.editDialog.recordId = null;
        this.editDialog.record = null;

        const rec = this.idl.create('coai');
        rec.active(true);
        rec.auto_signon_enabled(true);
        rec.unique_identifier(1);
        rec.display_name(1);
        this.editDialog.record = rec;

        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    }

    deleteSelected = (entries: IdlObject[]) => {
        super.deleteSelected(entries);
    }
}
