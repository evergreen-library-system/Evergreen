import { Component, OnInit, Input, Output, ViewChild, EventEmitter } from '@angular/core';
import { firstValueFrom, Observable, from } from 'rxjs';
import { OrgService } from '@eg/core/org.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { BroadcastService } from '@eg/share/util/broadcast.service';
import { GridComponent } from '@eg/share/grid/grid.component';
import { GridDataSource, GridCellTextGenerator, GridColumnSort } from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';

@Component({
    selector: 'eg-tag-map-list',
    templateUrl: './tag-map-list.component.html',
    styleUrls: ['./tag-map-list.component.css']
})
export class TagMapListComponent implements OnInit {
    @Input() maps: IdlObject[] = [];
    @Input() newThings: IdlObject[] = [];
    @Input() headerText: string;
    @Input() buttonText: string;
    @Input() code2cctt: {[id: string]: IdlObject};
    @Input() trickery: Function;
    @Input() showIsDeleted?: boolean = false;
    @Input() copyIds: number[] = [];
    @Output() remove = new EventEmitter<any>();
    @Output() removeTag = new EventEmitter<any>();

    @ViewChild('tagMapGrid', { static: false }) tagMapGrid: GridComponent;
    @ViewChild('tagGrid', { static: false }) tagGrid: GridComponent;
    tagMapSource: GridDataSource = new GridDataSource();
    tagSource: GridDataSource = new GridDataSource();
    tagMapCellTextGenerator: GridCellTextGenerator;
    tagCellTextGenerator: GridCellTextGenerator;

    allTagMaps: IdlObject[] = [];
    allTagIds: number[] = [];
    mapIds: number[] = [];
    newThingIds: number[] = [];
    representativeTagMaps: IdlObject[] = [];

    // noSelectedRows: (rows: IdlObject[]) => boolean;
    noSelectedTagMaps: (rows: IdlObject[]) => boolean;
    noSelectedTags: (rows: IdlObject[]) => boolean;

    constructor(
        private org: OrgService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private broadcaster: BroadcastService
    ) {}

    ngOnInit() {
        // console.debug('TagMapListComponent, ngOnInit, this', this);
        if (this.trickery) {
            this.trickery(this);
        }

        // eslint-disable-next-line rxjs/no-async-subscribe
        this.broadcaster.listen('eg.acpt_updated').subscribe(async (data) => {
            // console.debug('TagMapListComponent listener received',data);
            if (typeof data.result === 'string' || typeof data.result === 'number') {
                const flesh = {
                    flesh: 1,
                    flesh_fields: {
                        acpt: ['tag_type']
                    }
                };
                const actualTag = await firstValueFrom(this.pcrud.retrieve('acpt', data.result, flesh));
                // console.debug('TagMapListComponent actualTag', actualTag);
                if (actualTag) {
                    let found = false;
                    this.allTagMaps.forEach( tagMap => {
                        if (tagMap.tag().id() === actualTag.id()) {
                            const isdeleted = tagMap.tag().isdeleted();
                            actualTag.isdeleted( isdeleted );
                            tagMap.tag( actualTag );
                            found = true;
                        }
                    });
                    if (found) {
                        this.tagMapGrid.reload();
                    }
                }
            }
        });

        this.noSelectedTagMaps = (rows: IdlObject[]) => (rows.length === 0);
        this.tagMapSource.getRows = (pager: Pager, sort: GridColumnSort[]): Observable<any> => {
            console.error('TagMapListComponent, tagMapSource getRows called with maps, newThings', this.maps, this.newThings);
            if ((!this.maps || !this.maps.length) && (!this.newThings || !this.newThings.length)) {
                // console.debug('TagMapListComponent, no maps available yet');
                return from([]); // Return empty array if maps aren't loaded yet
            }

            const allRows = this.getRows();

            const startIndex = pager.offset;
            const endIndex = startIndex + pager.limit;
            const pagedRows =  allRows.slice(startIndex, endIndex);

            // console.debug('TagMapListComponent, returning tagMapSource rows:', pagedRows);
            return from(pagedRows);
        };

        this.tagMapCellTextGenerator = {
            combined_label_value: row => this.getCombinedLabelValueText(row),
            tagmap_status: row => this.getStatusText(row),
            tagmap_ids: row => this.getTagMapIdsColumn(row)
        };
    }

    getRows() {
        this.maps = this.maps.filter(m => m.id() !== null);
        this.newThings = this.newThings.filter(m => m.id() !== null);

        this.allTagMaps = [];
        if (this.newThings && this.newThings.length) {
            this.allTagMaps = this.newThings.filter(m => m.id() !== null);
        }
        this.allTagMaps = this.allTagMaps.concat(this.maps);

        this.mapIds = [...new Set(this.allTagMaps.map(m => m.id()))];
        this.allTagIds = this.getTagIdsFromMaps(this.allTagMaps);
        // console.debug('allTagIds: ', this.allTagIds);
        return this.copyIds.length > 1 ? this.getRepresentativeRows() : this.allTagMaps;
    }

    getTagIdsFromMaps(tagMaps: IdlObject[]): number[] {
        if (!tagMaps || !tagMaps.length) {return [];}

        const set = [...new Set(tagMaps.map(tagMap => tagMap.tag().id()))];
        // console.debug('getTagIdsFromMaps, ', tagMaps, set);

        return set;
    }

    getTagMapIdsFromTag(tagId) {
        const allMapIds = this.allTagMaps.filter(m => m.tag().id() === tagId).map(m => m.id());
        return [...new Set(allMapIds)];
    }

    getTagMapIdsColumn(tagMap) {
        if (this.copyIds.length <= 1) {
            return tagMap.id();
        }

        // return this.getTagMapIdsFromTag(tagMap.tag().id()).join(', ');
        // in batch, let's not pretend we're showing real tagMap IDs, since
        // they are not all set until volcopy.updateInMemoryCopyWithTags() runs
        return '*';
    }

    getRepresentativeRows(): IdlObject[] {
        const rows = [];
        this.allTagIds.forEach(t => { rows.push(this.getRepresentativeTagMap(t)); });
        return rows;
    }

    // In batch, all tagMaps for a given tag ID should have the same pending / deleted status
    // In single or template, we have only one tagMap per tag ID anyway
    getRepresentativeTagMap(tagId: number): IdlObject {
        const firstMatchingMap = this.allTagMaps.find((m) => m.tag().id() === tagId);
        // console.debug('First matching map for tag: ', tagId, firstMatchingMap);
        return firstMatchingMap;
    }

    getCombinedLabelValueText(tag: IdlObject): string {
        return [tag.label(), tag.value()].join(' / ');
    }

    getStatusText(tagMap: IdlObject): string {
        if (tagMap.isdeleted()) {
            return $localize`Deleted`;
        }

        if (!tagMap.id() || this.newThings?.includes(tagMap.id())) {
            return $localize`Pending`;
        }
    }

    reload(maps, newThings) {
        // console.debug('tagMapGrid reload()', maps, newThings);
        this.maps = maps;
        this.newThings = newThings;
        setTimeout( () => {
            this.tagMapGrid.reload();
        }, 1 );
    }

    removeRow(map: any, $event: Event) {
        $event.preventDefault();
        $event.stopPropagation();
        // in batch, removing one row should remove all other rows with the same tag ID
        if (this.copyIds.length > 1) {
            const selectedMaps = this.allTagMaps.filter(m => m.tag().id() === map.tag().id());
            const selectedMapIds = selectedMaps.map(m => m.id());
            // console.debug('Removing maps via single row action on one map in a batch: ', selectedMapIds);
            this.remove.emit(selectedMaps);
        } else {
            // console.debug('Removing map via single row action: ', map);
            this.remove.emit([map]);
        }
        // removeThing() will reload for us
        // this.reload();
    }

    onRemove(selectedMaps: any) {
        this.remove.emit(selectedMaps);
    }

}
