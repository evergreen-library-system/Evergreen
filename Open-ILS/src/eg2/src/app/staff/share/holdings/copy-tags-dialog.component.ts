import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from, EMPTY} from 'rxjs';
import {tap, map, switchMap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/**
 * Dialog for managing copy tags.
 */

export interface CopyTagChanges {
    newTags: IdlObject[];
    deletedMaps: IdlObject[];
}

@Component({
    selector: 'eg-copy-tags-dialog',
    templateUrl: 'copy-tags-dialog.component.html'
})

export class CopyTagsDialogComponent
    extends DialogComponent implements OnInit {

    // If there are multiple copyIds, only new tags may be applied.
    // If there is only one copyId, then tags may be applied or removed.
    @Input() copyIds: number[] = [];

    mode: string; // create | manage

    // If true, no attempt is made to save the new tags to the
    // database.  It's assumed this takes place in the calling code.
    @Input() inPlaceCreateMode = false;

    // In 'create' mode, we may be adding notes to multiple copies.
    copies: IdlObject[] = [];

    // In 'manage' mode we only handle a single copy.
    copy: IdlObject;

    tagTypes: ComboboxEntry[];

    curTag: ComboboxEntry = null;
    curTagType: ComboboxEntry = null;
    newTags: IdlObject[] = [];
    deletedMaps: IdlObject[] = [];
    tagMap: {[id: number]: IdlObject} = {};
    tagTypeMap: {[id: number]: IdlObject} = {};

    tagDataSource: (term: string) => Observable<ComboboxEntry>;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {

        this.tagDataSource = term => {
            if (!this.curTagType) { return EMPTY; }

            return this.pcrud.search(
                'acpt', {
                    tag_type: this.curTagType.id,
                    '-or': [
                        {value: {'ilike': `%${term}%`}},
                        {label: {'ilike': `%${term}%`}}
                    ],
                    owner: this.org.ancestors(this.auth.user().ws_ou(), true)
                },
                {order_by: {acpt: 'label'}}
            ).pipe(map(copyTag => {
                this.tagMap[copyTag.id()] = copyTag;
                return {id: copyTag.id(), label: copyTag.label()};
            }));
        };
    }

    /**
     */
    open(args: NgbModalOptions): Observable<CopyTagChanges> {
        this.copy = null;
        this.copies = [];
        this.newTags = [];
        this.deletedMaps = [];

        if (this.copyIds.length === 0 && !this.inPlaceCreateMode) {
            return throwError('copy ID required');
        }

        // In manage mode, we can only manage a single copy.
        // But in create mode, we can add tags to multiple copies.
        // We can only manage copies that already exist in the database.
        if (this.copyIds.length === 1 && this.copyIds[0] > 0) {
            this.mode = 'manage';
        } else {
            this.mode = 'create';
        }

        // Observify data loading
        const obs = from(this.getTagTypes().then(_ => this.getCopies()));

        // Return open() observable to caller
        return obs.pipe(switchMap(_ => super.open(args)));
    }

    getTagTypes(): Promise<any> {
        if (this.tagTypes) { return Promise.resolve(); }

        this.tagTypes = [];
        return this.pcrud.search('cctt',
            {owner: this.org.ancestors(this.auth.user().ws_ou(), true)},
            {order_by: {cctt: 'label'}}
        ).pipe(tap(tag => {
            this.tagTypeMap[tag.code()] = tag;
            this.tagTypes.push({id: tag.code(), label: tag.label()});
        })).toPromise();
    }

    getCopies(): Promise<any> {
        return this.pcrud.search('acp', {id: this.copyIds},
            {flesh: 3, flesh_fields: {
                acp: ['tags'], acptcm: ['tag'], acpt: ['tag_type']}},
            {atomic: true}
        )
            .toPromise().then(copies => {
                this.copies = copies;
                if (copies.length === 1) {
                    this.copy = copies[0];
                }
            });
    }

    removeTag(tag: IdlObject) {
        this.newTags = this.newTags.filter(t => t.id() !== tag.id());

        if (tag.isnew() || this.mode === 'create') { return; }

        const existing = this.copy.tags().filter(m => m.tag().id() === tag.id())[0];
        if (!existing) { return; }

        existing.isdeleted(true);
        this.deletedMaps.push(existing);
        this.copy.tags(this.copy.tags().filter(m => m.tag().id() !== tag.id()));
        this.copy.ischanged(true);
    }

    addNew() {
        if (!this.curTagType || !this.curTag) { return; }

        let tag;

        if (this.curTag.freetext) {
            // Create a new tag w/ the provided tag text.
            tag = this.idl.create('acpt');
            tag.isnew(true);
            tag.tag_type(this.curTagType.id);
            tag.label(this.curTag.label);
            tag.owner(this.auth.user().ws_ou());
            tag.pub('t');
        } else {
            tag = this.tagMap[this.curTag.id];
        }

        this.newTags.push(tag);
    }

    createNewTags(): Promise<any> {
        let promise = Promise.resolve();

        this.newTags.forEach(tag => {
            if (!tag.isnew()) { return; }

            promise = promise.then(_ => {
                return this.pcrud.create(tag).toPromise().then(id => {
                    console.log('create returned ', id);
                    tag.id(id);
                });
            });
        });

        return promise;
    }

    deleteMaps(): Promise<any> {
        if (this.deletedMaps.length === 0) { return Promise.resolve(); }
        return this.pcrud.remove(this.deletedMaps).toPromise();
    }

    applyChanges() {

        if (this.inPlaceCreateMode) {
            this.close({ newTags: this.newTags, deletedMaps: this.deletedMaps });
            return;
        }

        let promise = this.deleteMaps().then(_ => this.createNewTags());

        this.newTags.forEach(tag => {
            this.copies.forEach(copy => {

                if (copy.tags() && copy.tags().filter(
                    m => m.tag().id() === tag.id()).length > 0) {
                    return; // map already exists
                }

                promise = promise.then(_ => {
                    const tagMap = this.idl.create('acptcm');
                    tagMap.isnew(true);
                    tagMap.copy(copy.id());
                    tagMap.tag(tag.id());
                    return this.pcrud.create(tagMap).toPromise();
                });
            });
        });

        promise.then(_ => {
            this.successMsg.current().then(msg => this.toast.success(msg));
            this.close({ newTags: this.newTags, deletedMaps: this.deletedMaps });
        });
    }
}

