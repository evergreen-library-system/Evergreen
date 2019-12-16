import {Injectable, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {map, tap, distinct} from 'rxjs/operators';
import {StoreService} from '@eg/core/store.service';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {ContextMenuEntry} from '@eg/share/context-menu/context-menu.service';

interface TagTableSelector {
    marcFormat?: string;
    marcRecordType?: string;
}

const defaultTagTableSelector: TagTableSelector = {
    marcFormat     : 'marc21',
    marcRecordType : 'biblio'
};

@Injectable()
export class TagTableService {

    // Current set of tags in list and map form.
    tagMap: {[tag: string]: any} = {};
    ffPosMap: {[rtype: string]: any[]} = {};
    ffValueMap: {[rtype: string]: any} = {};
    controlledBibTags: string[];

    extractedValuesCache:
        {[valueType: string]: {[which: string]: any}} = {};

    constructor(
        private store: StoreService,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService
    ) {

        this.extractedValuesCache = {
            fieldtags: {},
            indicators: {},
            sfcodes: {},
            sfvalues: {},
            ffvalues: {}
        };
    }

    // Various data needs munging for display.  Cached the modified
    // values since they are refernced repeatedly by the UI code.
    fromCache(dataType: string, which?: string, which2?: string): ContextMenuEntry[] {
        const part1 = this.extractedValuesCache[dataType][which];
        if (which2) {
            if (part1) {
                return part1[which2];
            }
        } else {
            return part1;
        }
    }

    toCache(dataType: string, which: string,
        which2: string, values: ContextMenuEntry[]): ContextMenuEntry[] {
        const base = this.extractedValuesCache[dataType];
        const part1 = base[which];

        if (which2) {
            if (!base[which]) { base[which] = {}; }
            base[which][which2] = values;
        } else {
            base[which] = values;
        }

        return values;
    }

    getFfPosTable(rtype: string): Promise<any> {
        const storeKey = 'FFPosTable_' + rtype;

        if (this.ffPosMap[rtype]) {
            return Promise.resolve(this.ffPosMap[rtype]);
        }

        this.ffPosMap[rtype] = this.store.getLocalItem(storeKey);

        if (this.ffPosMap[rtype]) {
            return Promise.resolve(this.ffPosMap[rtype]);
        }

        return this.net.request(
            'open-ils.fielder', 'open-ils.fielder.cmfpm.atomic',
            {query: {tag: {'!=' : '006'}, rec_type: rtype}}

        ).toPromise().then(table => {
            this.store.setLocalItem(storeKey, table);
            return this.ffPosMap[rtype] = table;
        });
    }

    getFfValueTable(rtype: string): Promise<any> {

        const storeKey = 'FFValueTable_' + rtype;

        if (this.ffValueMap[rtype]) {
            return Promise.resolve(this.ffValueMap[rtype]);
        }

        this.ffValueMap[rtype] = this.store.getLocalItem(storeKey);

        if (this.ffValueMap[rtype]) {
            return Promise.resolve(this.ffValueMap[rtype]);
        }

        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.fixed_field_values.by_rec_type', rtype

        ).toPromise().then(table => {
            this.store.setLocalItem(storeKey, table);
            return this.ffValueMap[rtype] = table;
        });
    }

    loadTagTable(selector?: TagTableSelector): Promise<any> {

        if (selector) {
            if (!selector.marcFormat) {
                selector.marcFormat = defaultTagTableSelector.marcFormat;
            }
            if (!selector.marcRecordType) {
                selector.marcRecordType =
                    defaultTagTableSelector.marcRecordType;
            }
        } else {
            selector = defaultTagTableSelector;
        }

        const cacheKey =
            `current_tag_table_${selector.marcFormat}_${selector.marcRecordType}`;

        this.tagMap = this.store.getLocalItem(cacheKey);

        if (this.tagMap) {
            return Promise.resolve(this.tagMap);
        }

        return this.fetchTagTable(selector).then(_ => {
            this.store.setLocalItem(cacheKey, this.tagMap);
            return this.tagMap;
        });
    }

    fetchTagTable(selector?: TagTableSelector): Promise<any> {
        this.tagMap = [];
        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.tag_table.all.retrieve.local',
            this.auth.token(), selector.marcFormat, selector.marcRecordType
        ).pipe(tap(tagData => {
            this.tagMap[tagData.tag] = tagData;
        })).toPromise();
    }

    getSubfieldCodes(tag: string): ContextMenuEntry[] {
        if (!tag || !this.tagMap[tag]) { return null; }

        const cached = this.fromCache('sfcodes', tag);

        const list = this.tagMap[tag].subfields.map(sf => ({
            value: sf.code,
            label: `${sf.code}: ${sf.description}`
        }))
        .sort((a, b) => a.label < b.label ? -1 : 1);

        return this.toCache('sfcodes', tag, null, list);
    }

    getFieldTags(): ContextMenuEntry[] {

        const cached = this.fromCache('fieldtags');
        if (cached) { return cached; }

        return Object.keys(this.tagMap)
        .filter(tag => Boolean(this.tagMap[tag]))
        .map(tag => ({
            value: tag,
            label: `${tag}: ${this.tagMap[tag].name}`
        }))
        .sort((a, b) => a.label < b.label ? -1 : 1);
    }

    getSubfieldValues(tag: string, sfCode: string): ContextMenuEntry[] {
        if (!tag || !this.tagMap[tag]) { return []; }

        const cached = this.fromCache('sfvalues', tag, sfCode);
        if (cached) { return cached; }

        const list: ContextMenuEntry[] = [];

        this.tagMap[tag].subfields
        .filter(sf =>
            sf.code === sfCode && sf.hasOwnProperty('value_list'))
        .forEach(sf => {
            sf.value_list.forEach(value => {

                let label = value.description || value.code;
                const code = value.code || label;
                if (code !== label) { label = `${code}: ${label}`; }

                list.push({value: code, label: label});
            });
        });

        return this.toCache('sfvalues', tag, sfCode, list);
    }

    getIndicatorValues(tag: string, which: 'ind1' | 'ind2'): ContextMenuEntry[] {
        if (!tag || !this.tagMap[tag]) { return; }

        const cached = this.fromCache('indicators', tag, which);
        if (cached) { return cached; }

        let values = this.tagMap[tag][which];
        if (!values) { return; }

        values = values.map(value => ({
            value: value.code,
            label: `${value.code}: ${value.description}`
        }))
        .sort((a, b) => a.label < b.label ? -1 : 1);

        return this.toCache('indicators', tag, which, values);
    }


    getFfFieldMeta(fieldCode: string, recordType: string): Promise<IdlObject> {
        return this.getFfPosTable(recordType).then(table => {

            // Note the AngJS MARC editor stores the full POS table
            // for all record types in every copy of the table, hence
            // the seemingly extraneous check in recordType.
            return table.filter(
                field =>
                    field.fixed_field === fieldCode
                 && field.rec_type === recordType
            )[0];
        });
    }


    // Assumes getFfPosTable and getFfValueTable have already been
    // invoked for the request record type.
    getFfValues(fieldCode: string, recordType: string): ContextMenuEntry[] {

        const cached = this.fromCache('ffvalues', recordType, fieldCode);
        if (cached) { return cached; }

        let values = this.ffValueMap[recordType];

        if (!values || !values[fieldCode]) { return null; }

        // extract the canned set of possible values for our
        // fixed field.  Ignore those whose value exceeds the
        // specified field length.
        values = values[fieldCode]
            .filter(val => val[0].length <= val[2])
            .map(val => ({value: val[0], label: `${val[0]}: ${val[1]}`}))
            .sort((a, b) => a.label < b.label ? -1 : 1);

        return this.toCache('ffvalues', recordType, fieldCode, values);
    }

    getControlledBibTags(): Promise<string[]> {
        if (this.controlledBibTags) {
            return Promise.resolve(this.controlledBibTags);
        }

        this.controlledBibTags = [];
        return this.pcrud.retrieveAll('acsbf', {select: ['tag']})
        .pipe(
            map(field => field.tag()),
            distinct(),
            map(tag => this.controlledBibTags.push(tag))
        ).toPromise().then(_ => this.controlledBibTags);
    }
}



