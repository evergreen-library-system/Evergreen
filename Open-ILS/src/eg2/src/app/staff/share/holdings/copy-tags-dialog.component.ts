
import { Component } from '@angular/core';
import { lastValueFrom, Observable, EMPTY, map, defaultIfEmpty, tap } from 'rxjs';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { ToastService } from '@eg/share/toast/toast.service';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import {VolCopyContext} from '@eg/staff/cat/volcopy/volcopy';
import {
    CopyThingsDialogComponent,
    IThingObject,
    IThingChanges,
    IThingConfig
} from './copy-things-dialog.component';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { TagMapListComponent } from './tag-map-list.component';

// Interface for tag maps with the composite match functionality
export interface ICopyTagMap extends IThingObject {
    tag(val?: IdlObject): IdlObject;
    copy(val?: number): number;
}

// For batch operations, we track original tag map IDs
interface ProxyTagMap extends ICopyTagMap {
    originalTagMapIds: number[];
}

// Changes structure following the base pattern
export interface ICopyTagMapChanges extends IThingChanges<ICopyTagMap> {
    newThings: ICopyTagMap[];
    changedThings: ICopyTagMap[];
    deletedThings: ICopyTagMap[];
}

@Component({
    selector: 'eg-copy-tags-dialog',
    templateUrl: 'copy-tags-dialog.component.html',
    styles: [
        'kbd:first-letter { text-transform: none; }',
        '.new-tag-actions button[disabled] { display: none; }',
        '.dl-grid { grid-template-columns: auto 1fr; }'
    ]
})
export class CopyTagsDialogComponent extends
    CopyThingsDialogComponent<ICopyTagMap, ICopyTagMapChanges> {

    protected thingType = 'tag maps';
    protected successMessage = $localize`Successfully Modified Item Tag Maps`;
    protected errorMessage = $localize`Failed To Modify Item Tag Maps`;
    protected batchWarningMessage = '';

    context: VolCopyContext;

    // Tag-specific properties
    allTags = [];
    allTagsInCommon = [];
    tagMaps = [];
    tagTypes: ComboboxEntry[];
    tagMapsInCommon: ICopyTagMap[] = [];
    newTagMap: ICopyTagMap;
    curTag: ComboboxEntry = null;
    curTagType: ComboboxEntry = null;
    id2tag: {[id: number]: IdlObject} = {};
    code2type: {[id: string]: IdlObject} = {};
    autoId = -1;
    tagDataSource: (term: string) => Observable<ComboboxEntry>;
    tagDataSourceForEdits: { [key: number]: (term: string) => Observable<ComboboxEntry> } = {};

    // ViewChild does not work in this context; see trickeryPendingMapsList
    combinedTagMapsList: TagMapListComponent;

    allMapRows: ICopyTagMap[] = [];
    allTagIds: number[] = [];

    liveAllTagIds() { return this.allTags.map(t => t.id()); }
    liveAllTagsInCommon() { return this.allTagsInCommon.map(t => t.id()); }
    liveTagMapIds() { return this.tagMaps.map(m => m.id()); }

    constructor(
        modal: NgbModal,
        toast: ToastService,
        idl: IdlService,
        pcrud: PcrudService,
        org: OrgService,
        auth: AuthService
    ) {
        const config: IThingConfig<ICopyTagMap> = {
            idlClass: 'acptcm',
            thingField: 'tags',
            fleshDepth: 3,
            fleshFields: {'acp':['tags'], 'acptcm': ['tag'], 'acpt': ['tag_type'] },
            defaultValues: {}
        };
        super(modal, toast, idl, pcrud, org, auth, config);

        this.setupTagDataSource();
        this.newTagMap = this.createNewThing();
        this.context = new VolCopyContext();
        this.context.org = org; // inject
        this.context.idl = idl; // inject
    }

    public async initialize(): Promise<void> {
        await this.getTagTypes();
        if (!this.newTagMap) {
            this.newTagMap = this.createNewThing();
        }
        await super.initialize();

        this.allMapRows = this.allMaps();
        this.allTagIds = [...new Set(this.getTagIdsFromMaps(this.allMaps()).concat(this.getTagIdsFromMaps(this.newThings)))];
        // console.debug('allTagIds: ', this.allTagIds);

        this.newThings.forEach(tagMap => this.setupTagDataSourceForEdits(tagMap));
        (this.inBatch() ? this.tagMapsInCommon : (this.copies.length ? this.copies[0].tags() : [])).forEach(
            tagMap => this.setupTagDataSourceForEdits(tagMap));
    }

    getTagIdsFromMaps(tagMaps: ICopyTagMap[]): number[] {
        if (!tagMaps || !tagMaps.length) {return [];}

        return tagMaps.map(tagMap => tagMap.tag().id());
    }

    trickeryExistingTagMapsList = (that: any) => {
        // console.debug('trickeryExistingTagMapsList, that', that);
        this.combinedTagMapsList = that;
    };

    // Typeahead data for Add New tag value
    private setupTagDataSource() {
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
            ).pipe(map(tag => {
                this.id2tag[tag.id()] = tag;
                if (!this.allTagIds.includes(tag.id())) {
                    return {id: tag.id(), label: tag.label()};
                }
            }));
        };
    }

    private setupTagDataSourceForEdits(tagMap) {
        // console.debug('setupTagDataSourceForEdits',tagMap);
        if (this.tagDataSourceForEdits[tagMap.id()]) { return; }

        this.tagDataSourceForEdits[tagMap.id()] = term => {
            if (!tagMap.tag().tag_type()) { return EMPTY; }

            return this.pcrud.search(
                'acpt', {
                    tag_type: tagMap.tag().tag_type(),
                    '-or': [
                        {value: {'ilike': `%${term}%`}},
                        {label: {'ilike': `%${term}%`}}
                    ],
                    owner: this.org.ancestors(this.auth.user().ws_ou(), true)
                },
                {order_by: {acpt: 'label'}}
            ).pipe(map(tag => {
                this.id2tag[tag.id()] = tag;
                return {id: tag.id(), label: tag.label()};
            }));
        };
    }

    private async getTagTypes(): Promise<void> {
        if (this.tagTypes) { return; }

        const types = await this.pcrud.search('cctt',
            {owner: this.org.ancestors(this.auth.user().ws_ou(), true)},
            {order_by: {cctt: 'label'}},
            {atomic: true}
        ).toPromise();

        this.tagTypes = types.map(type => ({
            id: type.code(),
            label: type.label()
        }));

        types.forEach(type => this.code2type[type.code()] = type);
    }

    protected async getThings(): Promise<void> {
        if (this.copyIds.length === 0) { return; }

        if (this.tagMaps.length > 0) {
            // console.debug('already have tagMaps, trimming newThings from existing. newThings=', this.newThings);
            this.copies.forEach( c => {
                const newThingIds = this.newThings.map( aa => aa.id() );
                c.tags(
                    (c.tags() || []).filter( a => !newThingIds.includes(a.id()) )
                );
            });
            return;
        } // need to make sure this is cleared after a save. It is; the page reloads
        /***/

        // (note: then we also need to update counts in copy-attrs.component.html
        // to count tags, not maps)
        this.tagMaps = await this.pcrud.search('acptcm',
            {copy: this.copyIds},
            {flesh: 2, flesh_fields: {acptcm: ['tag'], acpt: ['tag_type']}},
            {atomic: true}
        ).toPromise();

        this.copies.forEach(c => c.tags([]));
        this.allTags = [];
        const seenTagIds = new Map();
        this.tagMaps.forEach(tagMap => {
            const copy = this.copies.find(c => c.id() === tagMap.copy());
            copy.tags( copy.tags().concat(tagMap) );

            const tag = tagMap.tag();
            if (tag) {
                const tagId = this.idl.pkeyValue(tag);
                if (tagId && !seenTagIds.has(tagId)) {
                    seenTagIds.set(tagId, true);
                    this.allTags.push(tag);
                }
            }
        });
    }

    protected compositeMatch(a: ICopyTagMap, b: ICopyTagMap): boolean {
        const aTag = a.tag();
        const bTag = b.tag();
        return this.idl.pkeyValue( aTag ) === this.idl.pkeyValue( bTag );
        /* return aTag.tag_type() === bTag.tag_type()
            && aTag.label() === bTag.label()
            && aTag.value() === bTag.value()
            && aTag.staff_note() === bTag.staff_note()
            && aTag.pub() === bTag.pub()
            && aTag.owner() === bTag.owner()
            && aTag.url() === bTag.url();*/
    }

    protected async processCommonThings(): Promise<void> {
        if (!this.inBatch()) { return; }

        let potentialMatches = this.copies[0].tags();

        this.copies.slice(1).forEach(copy => {
            potentialMatches = potentialMatches.filter(mapFromFirstCopy =>
                copy.tags().some(mapFromCurrentCopy =>
                    this.compositeMatch(mapFromFirstCopy, mapFromCurrentCopy)
                )
            );
        });
        if (potentialMatches.find( m => !m)) {
            console.error('Falsy element in potentialMatches', this.idl.clone(potentialMatches));
        }

        const seenTagIds = new Map();
        this.allTagsInCommon = [];
        this.tagMapsInCommon = potentialMatches
            .filter(match => match)
            .map(match => {
                const proxy = this.cloneMapForBatchProxy(match) as ProxyTagMap;
                proxy.originalTagMapIds = [];
                this.copies.forEach(copy => {
                    copy.tags().forEach(tagMap => {
                        if (this.compositeMatch(tagMap, match)) {
                            proxy.originalTagMapIds.push(tagMap.id());
                            const tag = tagMap.tag();
                            if (tag) {
                                const tagId = this.idl.pkeyValue(tag);
                                if (tagId && !seenTagIds.has(tagId)) {
                                    seenTagIds.set(tagId, true);
                                    this.allTagsInCommon.push(tag);
                                }
                            }
                        }
                    });
                });
                if (!proxy) {
                    console.error('proxy undefined when match =', this.idl.clone(match));
                }
                return proxy;
            })
            .filter(proxy => proxy && proxy.originalTagMapIds && proxy.originalTagMapIds.length > 0);
    }

    private cloneMapForBatchProxy(source: ICopyTagMap): ICopyTagMap {
        const target = this.createNewThing();
        target.id(source.id());
        target.tag(source.tag());
        return target;
    }

    protected createNewThing(): ICopyTagMap {
        const newThing = super.createNewThing();
        // console.debug('createNewThing, newThing', newThing.id(), newThing);
        return newThing;
    }

    async addThenRefresh() {
        await this.addNew().then(
            resolve => {
                // console.debug('addThenRefresh succeeded: ', resolve);
                if (this.combinedTagMapsList) {this.combinedTagMapsList.reload(this.allMapRows, this.newThings);}
                this.curTag = null;
            },
            reject => {
                // console.debug('addThenRefresh failed: ', reject);
            }
        );
    }

    async addNew(): Promise<void> {
        if (!this.validate()) { return; }

        if (!this.curTagType || !this.curTag) { return; }

        let selectedTag;
        if (!this.curTag.id && this.curTag.freetext) {
            selectedTag = await this.insertNewTag();
        } else {
            selectedTag = this.id2tag[this.curTag.id];
        }
        if (typeof selectedTag.tag_type() === 'string') {
            selectedTag.tag_type( this.code2type[ selectedTag.tag_type() ] );
        }
        // console.debug('addNew, selectedTag', selectedTag);

        this.copies.forEach(copy => {
            if (copy.tags().includes(selectedTag.id())) {
                // console.debug(`Copy ${copy.id()} already has tag ${selectedTag.id()}`);
            }

        });
        this.newTagMap.id(this.autoId--);
        this.newTagMap.isnew(true);
        this.newTagMap.tag(selectedTag); // what was a stub now gets filled in and added to newThings
        this.newThings.push( this.newTagMap );
        this.newTagMap = this.createNewThing(); // this preps an entry for the new tag map form
        /*
        if (!this.allTagIds.includes(selectedTag)) {
            this.allMapRows.unshift(this.newTagMap);
            this.allTagIds.unshift(this.newTagMap.tag().id());
        }
        /** */

        this.setupTagDataSourceForEdits(this.newTagMap);
        // console.debug('New Things: ', this.newThings);
        // addThenRefresh() will reload so we don't reload for every copy in a batch
    }

    protected async insertNewTag(): Promise<number> {
        const id = null;
        const newTag = this.idl.create('acpt');
        newTag.id(null);
        newTag.isnew(true);
        newTag.label(this.curTag.label);
        newTag.value(this.curTag.label);
        newTag.owner(this.auth.user().ws_ou());
        newTag.tag_type(this.curTagType.id);
        newTag.pub('t');

        const resp = await lastValueFrom(
            this.pcrud.autoApply([newTag])
                .pipe(
                    tap({
                        next: (val) => console.debug('CopyTagsDialog, insertNewTag, pcrud.autoApply next', val),
                        error: (err: unknown) => console.error('CopyTagsDialog, insertNewTag, pcrud.autoApply err', err),
                        complete: () => console.debug('CopyTagsDialog, insertNewTag, pcrud.autoApply completed')
                    }),
                    defaultIfEmpty(null)
                )
        );
        // console.debug('insertNewTag, pcrud resp', resp);
        resp.tag_type(this.code2type[ resp.tag_type() ]);

        return resp;
    }

    protected validate(): boolean {
        if (!this.curTagType) {
            this.toast.danger($localize`Tag type is required`);
            return false;
        }
        if (!this.curTag) {
            this.toast.danger($localize`Tag selection is required`);
            return false;
        }
        return true;
    }

    undeleteTagMap(tagMap: ICopyTagMap): void {
        // send to delete and it just acts as a toggle in copy-things-dialog
        // console.debug('undeleteTagMap, tagMap', tagMap);
        this.removeThing([tagMap]);
    }

    removeTagMap(tagMap: ICopyTagMap): void {
        // console.debug('removeTagMap, tagMap', tagMap);
        this.removeThing([tagMap]);
    }

    removeThing(maps: ICopyTagMap[]): void {
        // console.debug('tags, removeThing, maps', maps);
        super.removeThing(maps);
        // console.debug('back from super.removeThing');
        // refresh display
        if (this.combinedTagMapsList) {
            // console.debug('attempting to reload combinedTagMapsList');
            this.combinedTagMapsList.reload(this.allMapRows, this.newThings);
        } else {
            // console.debug('no combinedTagMapsList to reload');
        }
    }

    protected async applyChanges(): Promise<void> {
        try {
            // console.debug('CopyTagsDialog, applyChanges, changedThings prior to rebuild', this.changedThings);
            // console.debug('CopyTagsDialog, applyChanges, deletedThings prior to rebuild', this.deletedThings);
            // console.debug('CopyTagsDialog, applyChanges, copies', this.copies);
            this.changedThings = [];
            this.deletedThings = [];

            // Find tagMaps that have been modified
            if (this.inBatch()) {
                // For batch mode, look at tagMapsInCommon for changes
                this.changedThings = this.tagMapsInCommon.filter(m => m.ischanged());
                this.deletedThings = this.tagMapsInCommon.filter(m => m.isdeleted());
                // console.debug('CopyTagsDialog, applyChanges, changedThings rebuilt in batch context', this.changedThings);
                // console.debug('CopyTagsDialog, applyChanges, deletedThings rebuilt in batch context', this.deletedThings);
            } else if (this.copies.length) {
                // For single mode, look at the copy's tags
                this.changedThings = this.copies[0].tags()
                    .filter(m => m.ischanged());
                this.deletedThings = this.copies[0].tags()
                    .filter(m => m.isdeleted());
                // console.debug('CopyTagsDialog, applyChanges, changedThings rebuilt in non-batch context', this.changedThings);
                // console.debug('CopyTagsDialog, applyChanges, deletedThings rebuilt in non-batch context', this.deletedThings);
            } else {
                // console.debug('CopyTagsDialog, applyChanges, inBatch() == false and this.copies.length == false');
            }

            if (this.inPlaceCreateMode) {
                this.close(this.gatherChanges());
                return;
            }

            // console.debug('here', this);

            this.context.newTagMaps = this.newThings;
            this.context.changedTagMaps = this.changedThings;
            this.context.deletedTagMaps = this.deletedThings;

            this.copies.forEach( c => this.context.updateInMemoryCopyWithTags(c) );

            // console.debug('copies', this.copies);

            // Handle persistence ourselves
            const result = await this.saveChanges();
            // console.debug('CopyTagsDialogComponent, saveChanges() result', result);
            if (result) {
                this.showSuccess();
                this.tagMaps = []; this.copies = []; this.copyIds = [];
                this.close(this.gatherChanges());
            } else {
                this.showError('saveChanges failed');
            }
        } catch (err) {
            this.showError(err);
        }
    }

    updateTagMapTagType(tagMap, $event) {
        // console.debug('updateTagMapType, tagMap, $event', tagMap, $event);
        tagMap.tag().tag_type( this.code2type[$event.id] );
        if (! (tagMap.isnew() ?? false)) {
            tagMap.ischanged(true);
        }
    }

    updateTagMap(tagMap, $event) {
        // console.debug('updateTagMap, tagMap, $event', tagMap, $event);
        tagMap.tag( this.id2tag[$event.id] );
        if (typeof tagMap.tag().tag_type() === 'string') {
            tagMap.tag().tag_type( this.code2type[ tagMap.tag().tag_type() ] );
        }
        if (! (tagMap.isnew() ?? false)) {
            tagMap.ischanged(true);
        }
    }

    tagMapTagType2ComboId(tagMap) {
        if (!tagMap) { return null; }
        if (!tagMap.tag()) { return null; }
        if (!tagMap.tag().tag_type()) { return null; }
        if (typeof tagMap.tag().tag_type() === 'string') {
            return tagMap.tag().tag_type();
        } else {
            return tagMap.tag().tag_type().code();
        }
    }

    allMaps() {
        const allMaps = this.inBatch() ? this.tagMapsInCommon : this.copies[0]?.tags();
        if (typeof allMaps !== 'undefined' && allMaps.length) {
            allMaps.forEach(m => {
                if (!m.id()) {return;}

                if (this.deletedThings.map(t => t.id()).includes(m.id())) {
                    m.isdeleted(true);
                }
            });
        }
        // console.debug('Existing maps: ', allMaps);
        return allMaps;
    }
}
