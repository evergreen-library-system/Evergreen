import {Component, ViewChild, Input, OnInit} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {MarcField} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {Pager} from '@eg/share/util/pager';
import {MarcEditorDialogComponent} from './editor-dialog.component';

/**
 * MARC Authority Linking Dialog
 */

@Component({
    selector: 'eg-authority-linking-dialog',
    templateUrl: './authority-linking-dialog.component.html'
})

export class AuthorityLinkingDialogComponent
    extends DialogComponent implements OnInit {

    @Input() bibField: MarcField;
    @Input() thesauri: string = null;
    @Input() controlSet: number = null;
    @Input() pager: Pager;
    @Input() context: MarcEditContext;

    browseData: any[] = [];

    // If false, show the raw MARC field data.
    showAs: 'heading' | 'marc' = 'heading';

    authMeta: any;

    selectedSubfields: string[] = [];

    cni: string; // Control Number Identifier

    @ViewChild('marcEditDialog', {static: false})
        marcEditDialog: MarcEditorDialogComponent;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private net: NetService) {
        super(modal);
    }

    ngOnInit() {
        if (!this.pager) {
            this.pager = new Pager();
            this.pager.limit = 5;
        }

        this.onOpen$.subscribe(_ => this.initData());
    }

    fieldHash(field?: MarcField): any {
        if (!field) { field = this.bibField; }

        return {
            tag: field.tag,
            ind1: field.ind1,
            ind2: field.ind2,
            subfields: field.subfields.map(sf => [sf[0], sf[1]])
        };
    }

    initData() {

        this.pager.offset = 0;

        this.org.settings(['cat.marc_control_number_identifier']).then(s => {
            this.cni = s['cat.marc_control_number_identifier'] ||
                'Set cat.marc_control_number_identifier in Library Settings';
        });

        this.pcrud.search('acsbf',
            {
                tag: this.bibField.tag,
                // we're only interested in the authority fields
                // that are linked to a heading field; i.e., we're not
                // interested in subdivision authorities at this time
                authority_field: {
                    in: {
                        select: { acsaf: ['id'] },
                        from: 'acsaf',
                        where: {
                            heading_field: { '!=' : null }
                        }
                    }
                }
            },
            {flesh: 1, flesh_fields: {acsbf: ['authority_field']}},
            {atomic:  true, anonymous: true}

        ).subscribe(bibMetas => {
            if (bibMetas.length === 0) { return; }

            let bibMeta;
            if (this.controlSet) {
                bibMeta = bibMetas.filter(b =>
                    this.controlSet === +b.authority_field().control_set());
            } else {
                bibMeta = bibMetas[0];
            }

            if (bibMeta) {
                this.authMeta = bibMeta.authority_field();
                this.bibField.subfields.forEach(sf =>
                    this.selectedSubfields[sf[0]] =
                        this.isControlledBibSf(sf[0])
                );
            }

            this.getPage(0);
        });
    }

    getPage(direction: number) {
        this.browseData = [];

        if (direction > 0) {
            this.pager.offset++;
        } else if (direction < 0) {
            this.pager.offset--;
        } else {
            this.pager.offset = 0;
        }

        const hash = this.fieldHash();

        // Only search the selected subfields
        hash.subfields =
            hash.subfields.filter(sf => this.selectedSubfields[sf[0]]);

        if (hash.subfields.length === 0) { return; }

        this.net.request(
            'open-ils.cat',
            'open-ils.cat.authority.bib_field.linking_browse',
            hash, this.pager.limit,
            this.pager.offset, this.thesauri
        ).subscribe(entry => this.browseData.push(entry));
    }

    applyHeading(authField: MarcField, authId?: number) {
        this.net.request(
            'open-ils.cat',
            'open-ils.cat.authority.bib_field.overlay_authority',
            this.fieldHash(), this.fieldHash(authField), this.controlSet
        ).subscribe(field => {
            if (authId) {
                // If an authId is provided, it means we are using
                // a main entry heading and we should set the bib
                // field's subfield 0 to refer to the main entry record.
                this.setSubfieldZero(authId, field);
            }
            this.close(field);
        });
    }

    isControlledBibSf(sf: string): boolean {
        return this.authMeta ?
            this.authMeta.sf_list().includes(sf) : false;
    }

    setSubfieldZero(authId: number, bibField?: MarcField) {

        if (!bibField) { bibField = this.bibField; }

        const sfZero = bibField.subfields.filter(sf => sf[0] === '0')[0];
        if (sfZero) {
            this.context.deleteSubfield(bibField, sfZero);
        }
        this.context.insertSubfield(bibField,
            ['0', `(${this.cni})${authId}`, bibField.subfields.length]);

        // Reset the validation state.
        bibField.authChecked = null;
        bibField.authValid = null;
    }

    createNewAuthority(editFirst?: boolean) {

        const method = editFirst ?
            'open-ils.cat.authority.record.create_from_bib.readonly' :
            'open-ils.cat.authority.record.create_from_bib';

        this.net.request(
            'open-ils.cat', method,
            this.fieldHash(), this.cni, this.auth.token()
        ).subscribe(record => {
            if (editFirst) {
                this.marcEditDialog.recordXml = record;
                this.marcEditDialog.open({size: 'xl'})
                    // eslint-disable-next-line rxjs-x/no-nested-subscribe
                    .subscribe(saveEvent => {
                        if (saveEvent && saveEvent.recordId) {
                            this.setSubfieldZero(saveEvent.recordId);
                        }
                        this.close();
                    });
            } else {
                this.setSubfieldZero(record.id());
                this.close();
            }
        });
    }
}


