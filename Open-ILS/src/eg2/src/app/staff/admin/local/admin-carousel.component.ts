import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Location} from '@angular/common';
import {FormatService} from '@eg/core/format.service';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {GridCellTextGenerator} from '@eg/share/grid/grid';
import {StringComponent} from '@eg/share/string/string.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    templateUrl: './admin-carousel.component.html'
})

export class AdminCarouselComponent extends AdminPageComponent implements OnInit {

    idlClass = 'cc';
    classLabel: string;

    refreshSelected: (idlThings: IdlObject[]) => void;
    mungeCarousel: (editMode: string, rec: IdlObject) => void;
    postSave: (rec: IdlObject) => void;
    createNew: () => void;
    deleteSelected: (idlThings: IdlObject[]) => void;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('refreshString', { static: true }) refreshString: StringComponent;
    @ViewChild('refreshErrString', { static: true }) refreshErrString: StringComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;
    
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
        private net: NetService
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast);
    }

    ngOnInit() {
        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
        this.cellTextGenerator = {
            bucket: row => row.bucket().name()
        };

        this.createNew = () => {
            super.createNew();
        };

        this.deleteSelected = (idlThings: IdlObject[]) => {
            this.delConfirm.open().subscribe(confirmed => {
                if (!confirmed) { return; }
                super.doDelete(idlThings);
            });
        };

        this.refreshSelected = (idlThings: IdlObject[]) =>  {
            idlThings.forEach(cc => {
                if (cc.type().automatic() === 't') {
                    this.net.request(
                        'open-ils.actor',
                        'open-ils.actor.carousel.refresh',
                        this.auth.token(), cc.id()
                    ).toPromise(); // fire and forget, as this could take a couple minutes
                    this.refreshString.current({ name: cc.name() }).then(str => this.toast.success(str));
                } else {
                    this.refreshErrString.current({ name: cc.name() }).then(str => this.toast.warning(str));
                }
            });
        };

        this.editSelected = (carouselFields: IdlObject[]) => {
            // Edit each IDL thing one at a time
            const editOneThing = (carousel: IdlObject) => {
            if (!carousel) { return; }

            this.showEditDialog(carousel).then(
                () => editOneThing(carouselFields.shift()));
            };

            editOneThing(carouselFields.shift());
        };

        this.mungeCarousel = (editMode: string, rec: IdlObject) => {
            if (editMode === 'create') {
                rec.creator(this.auth.user().id());
            }
            rec.editor(this.auth.user().id());
            rec.edit_time('now');
    
            // convert empty string to nulls as needed
            // for int[] columns
            if (rec.owning_lib_filter() === '') {
                rec.owning_lib_filter(null);
            }
            if (rec.copy_location_filter() === '') {
                rec.copy_location_filter(null);
            }
        };
    
        this.postSave = (rec: IdlObject) => {
            if (rec._isfieldmapper) {
                // if we got an actual IdlObject back, the
                // record had just been created, not just
                // edited. therefore, we probably need
                if (rec.bucket() == null) {
                    const bucket = this.idl.create('cbreb');
                    bucket.owner(this.auth.user().id());
                    bucket.name('System-generated bucket for carousel: ' + rec.id()); // FIXME I18N
                    bucket.btype('carousel');
                    bucket.pub('t');
                    bucket.owning_lib(rec.owner());
                    rec.bucket(bucket);
                    this.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.create',
                        this.auth.token(), 'biblio', bucket
                    ).toPromise().then(
                        newBucket => {
                            const ccou = this.idl.create('ccou');
                            ccou.carousel(rec.id());
                            ccou.org_unit(rec.owner());
                            ccou.seq(0);
                            rec.bucket(newBucket);
                            this.pcrud.create(ccou).subscribe(
                                ok => {
                                    this.pcrud.update(rec).subscribe(
                                        ok2 => console.debug('updated'),
                                        err => console.error(err),
                                        () => { this.grid.reload(); }
                                    );
                                },
                                err => console.error(err),
                                () => { this.grid.reload(); }
                            );
                        }
                    );
                }
            }
        };

    }
}
