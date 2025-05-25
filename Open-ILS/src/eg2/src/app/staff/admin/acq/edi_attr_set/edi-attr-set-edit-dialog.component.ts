import {Component, Input, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-edi-attr-set-edit-dialog',
    templateUrl: './edi-attr-set-edit-dialog.component.html'
})

export class EdiAttrSetEditDialogComponent
    extends DialogComponent implements OnInit {

    @Input() mode = 'create';
    @Input() attrSetId: number;
    @Input() cloneSource: number;
    attrSet: IdlObject;
    attrInputs: any = [];
    clonedLabel = '';

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(() => this._initRecord());
    }

    private _initRecord() {
        this.attrSet = null;
        this.attrInputs = [];
        this.clonedLabel = '';
        if (this.mode === 'update') {
            this.pcrud.retrieve('aeas', this.attrSetId, {
                flesh: 1,
                flesh_fields: { aeas: ['attr_maps'] }
            }).subscribe(res => {
                this.attrSet = res;
                this._generateAttrInputs();
            });
        } else if (this.mode === 'clone') {
            this.pcrud.retrieve('aeas', this.cloneSource, {
                flesh: 1,
                flesh_fields: { aeas: ['attr_maps'] }
            }).subscribe(res => {
                this.clonedLabel = res.label();
                this.attrSet = this.idl.create('aeas');
                this.attrSet.attr_maps([]);
                res.attr_maps().forEach((m) => {
                    const newMap = this.idl.create('aeasm');
                    newMap.attr(m.attr());
                    this.attrSet.attr_maps().push(newMap);
                });
                this._generateAttrInputs();
            });
        } else if (this.mode === 'create') {
            this.attrSet = this.idl.create('aeas');
            this.attrSet.attr_maps([]);
            this._generateAttrInputs();
        }
    }

    _generateAttrInputs() {
        const hasAttr: {[key: string]: boolean} = {};
        const hasAttrId: {[key: string]: number} = {};
        this.attrSet.attr_maps().forEach((m) => {
            hasAttr[m.attr()] = true;
            hasAttrId[m.attr()] = m.id();
        });
        this.pcrud.retrieveAll('aea', {order_by: {aea: 'key'}}).subscribe(attr => {
            const inp = {
                key: attr.key(),
                label: attr.label(),
                id: null,
                selected: false
            };
            if (attr.key() in hasAttr) {
                inp.selected = true;
                inp.id = hasAttrId[attr.key()];
            }
            this.attrInputs.push(inp);
        });
    }

    save() {
        if (this.attrSet.id() === undefined || this.attrSet.id() === null) {
            this.attrSet.isnew(true);
        } else {
            this.attrSet.ischanged(true);
        }
        this.pcrud.autoApply([this.attrSet]).subscribe({ next: res => {
            const setId = this.mode === 'update' ? res : res.id();
            const updates: IdlObject[] = [];
            if (this.mode === 'create' || this.mode === 'clone') {
                this.attrInputs.forEach((inp) => {
                    if (inp.selected) {
                        const aesm = this.idl.create('aeasm');
                        aesm.attr(inp.key);
                        aesm.attr_set(setId);
                        aesm.isnew(true);
                        updates.push(aesm);
                    }
                });
            } else {
                // updating an existing set
                this.attrInputs.forEach((inp) => {
                    if (inp.id) {
                        if (!inp.selected) {
                            // used to be wanted, but no longer
                            const aesm = this.idl.create('aeasm');
                            aesm.id(inp.id);
                            aesm.isdeleted(true);
                            updates.push(aesm);
                        }
                    } else if (inp.selected) {
                        // no ID, must be newly checked
                        const aesm = this.idl.create('aeasm');
                        aesm.attr(inp.key);
                        aesm.attr_set(setId);
                        aesm.isnew(true);
                        updates.push(aesm);
                    }
                });
            }
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            this.pcrud.autoApply(updates).subscribe(
                { next: ret => this.close(true), error: (err: unknown) => this.close(err), complete: () => this.close(true) }
            );
        }, error: (err: unknown) => this.close(false) });
    }

}
