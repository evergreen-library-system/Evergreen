import {Component, OnInit} from '@angular/core';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';

@Component({
    templateUrl: './openathens-identity.component.html'
})
export class OpenAthensIdentityComponent extends AdminPageComponent implements OnInit {

    idlClass = 'coai';
    classLabel: string;

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
    };
}