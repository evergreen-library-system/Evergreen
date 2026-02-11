import {Injectable} from '@angular/core';
import {map, tap, distinct} from 'rxjs/operators';
import {StoreService} from '@eg/core/store.service';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {MARC_RECORD_TYPE} from './editor-context';

const DEFAULT_MARC_FORMAT = 'marc21';

interface TagTableSelector {
    marcFormat?: string;
    marcRecordType: MARC_RECORD_TYPE;

    // MARC record fixed field "Type" value.
    ffType: string;
}

export class TagTable {

    store: StoreService;
    auth: AuthService;
    net: NetService;
    pcrud: PcrudService;

    selector: TagTableSelector;

    // Current set of tags in list and map form.
    tagMap: {[tag: string]: any};
    ffPosTable: any;
    ffCRADTable: any;
    ffValueTable: any;
    fieldTags: ComboboxEntry[];

    // Cache of compiled, sorted, munged data.  Stuff the UI requests
    // frequently for selectors, etc.
    cache: {[valueType: string]: {[which: string]: any}} = {
        indicators: {},
        sfcodes: {},
        sfvalues: {},
        ffvalues: {}
    };

    constructor(
        store: StoreService,
        auth: AuthService,
        net: NetService,
        pcrud: PcrudService,
        selector: TagTableSelector
    ) {
        this.store = store;
        this.auth = auth;
        this.net = net;
        this.pcrud = pcrud;
        this.selector = selector;
    }


    load(): Promise<any> {
        return Promise.all([
            this.loadTagTable(),
            this.getFfPosTable(),
            this.getFfValueTable(),
            this.getFfCRADTable(),
        ]);
    }

    // Various data needs munging for display.  Cached the modified
    // values since they are refernced repeatedly by the UI code.
    fromCache(dataType: string, which?: string, which2?: string): ComboboxEntry[] {
        const part1 = this.cache[dataType][which];
        if (which2) {
            if (part1) {
                return part1[which2];
            }
        } else {
            return part1;
        }
    }

    toCache(dataType: string, which: string,
        which2: string, values: ComboboxEntry[]): ComboboxEntry[] {
        const base = this.cache[dataType];
        const part1 = base[which];

        if (which2) {
            if (!base[which]) { base[which] = {}; }
            base[which][which2] = values;
        } else {
            base[which] = values;
        }

        return values;
    }

    getFfPosTable(): Promise<any> {
        const storeKey = 'FFPosTable_' + this.selector.ffType;

        if (this.ffPosTable) {
            return Promise.resolve(this.ffPosTable);
        }

        this.ffPosTable = this.store.getLocalItem(storeKey);

        if (this.ffPosTable) {
            return Promise.resolve(this.ffPosTable);
        }

        return this.net.request(
            'open-ils.fielder', 'open-ils.fielder.cmfpm.atomic',
            {query: {tag: {'!=' : '006'}, rec_type: this.selector.ffType}}

        ).toPromise().then(table => {
            this.store.setLocalItem(storeKey, table);
            return this.ffPosTable = table;
        });
    }

    getFfCRADTable(): Promise<any> {
        const storeKey = 'FfCRADTable';

        if (this.ffCRADTable) {
            return Promise.resolve(this.ffCRADTable);
        }

        this.ffCRADTable = this.store.getLocalItem(storeKey);

        if (this.ffCRADTable) {
            return Promise.resolve(this.ffCRADTable);
        }

        return this.net.request(
            'open-ils.fielder', 'open-ils.fielder.crad.atomic',
            {query: {fixed_field: {'!=' : null}}}

        ).toPromise().then(table => {
            this.store.setLocalItem(storeKey, table);
            return this.ffCRADTable = table;
        });
    }

    // ffType is the fixed field Type value. BKS, AUT, etc.
    // See config.marc21_rec_type_map
    getFfValueTable(): Promise<any> {

        const storeKey = 'FFValueTable_' + this.selector.ffType;

        if (this.ffValueTable) {
            return Promise.resolve(this.ffValueTable);
        }

        this.ffValueTable = this.store.getLocalItem(storeKey);

        if (this.ffValueTable) {
            return Promise.resolve(this.ffValueTable);
        }

        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.fixed_field_values.by_rec_type',
            this.selector.ffType

        ).toPromise().then(table => {
            this.store.setLocalItem(storeKey, table);
            return this.ffValueTable = table;
        });
    }

    loadTagTable(): Promise<any> {

        const sel = this.selector;

        const cacheKey =
            `current_tag_table_${sel.marcFormat}_${sel.marcRecordType}`;

        this.tagMap = this.store.getLocalItem(cacheKey);

        if (this.tagMap) {
            return Promise.resolve(this.tagMap);
        }

        return this.fetchTagTable().then(_ => {
            this.store.setLocalItem(cacheKey, this.tagMap);
            return this.tagMap;
        });
    }

    fetchTagTable(): Promise<any> {
        this.tagMap = [];
        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.tag_table.all.retrieve.local',
            this.auth.token(), this.selector.marcFormat,
            this.selector.marcRecordType
        ).pipe(tap(tagData => {
            this.tagMap[tagData.tag] = tagData;
        })).toPromise();
    }

    getSubfieldCodes(tag: string): ComboboxEntry[] {
        if (!tag || !this.tagMap[tag]) { return null; }

        const list = this.tagMap[tag].subfields.map(sf => ({
            id: sf.code,
            label: sf.description
        })).sort((a, b) => {
            const aid = String(a.id ?? '');
            const bid = String(b.id ?? '');
            const aNum = /^\d/.test(aid);
            const bNum = /^\d/.test(bid);
            if (aNum !== bNum) { return aNum ? 1 : -1; }
            if (aid === bid) { return 0; }
            return aid < bid ? -1 : 1;
        });

        return this.toCache('sfcodes', tag, null, list);
    }

    getSubfieldValueLabel(tag: string, sfCode: string, sfVal: string): string {
        const entry =
            this.getSubfieldValues(
                tag, sfCode
            ).find( cbe => cbe.id === sfVal);

        if (entry && entry.label) {
            return entry.label;
        }

        return null;
    }

    getIndicatorValueLabel(tag: string, ind: 'ind1' | 'ind2', iVal: string): string {
        const entry =
            this.getIndicatorValues(
                tag, ind
            ).find( cbe => cbe.id === iVal);

        if (entry && entry.label) {
            return entry.label;
        }

        return null;
    }

    getFfValueLabel(ffCode: string, ffVal: string): string {
        const entry =
            this.getFfValues(ffCode).find( cbe => cbe.id === ffVal);

        if (entry && entry.label) {
            return entry.label;
        }

        return null;
    }

    getSubfieldLabel(tag: string, sfCode: string): string {
        if (!tag || !this.tagMap[tag]) { return null; }
        const subfieldResults = this.tagMap[tag].subfields.filter(sf => sf.code === sfCode);
        return subfieldResults.length ? subfieldResults[0].description : null;
    }

    getFieldLabel(tag: string): string {
        if (tag && this.tagMap[tag]) {
            return this.tagMap[tag].name;
        }
        return null;
    }

    getFieldTags(): ComboboxEntry[] {

        if (!this.fieldTags) {
            this.fieldTags = Object.keys(this.tagMap)
                .filter(tag => Boolean(this.tagMap[tag]))
                .map(tag => ({
                    id: tag,
                    label: `${this.tagMap[tag].name}`
                }))
                .sort((a, b) => a.id < b.id ? -1 : 1);
        }

        return this.fieldTags;
    }

    getSubfieldValues(tag: string, sfCode: string): ComboboxEntry[] {
        if (!tag || !this.tagMap[tag]) { return []; }

        const cached = this.fromCache('sfvalues', tag, sfCode);
        if (cached) { return cached; }

        const list: ComboboxEntry[] = [];

        this.tagMap[tag].subfields
            .filter(sf =>
            // eslint-disable-next-line no-prototype-builtins
                sf.code === sfCode && sf.hasOwnProperty('value_list'))
            .forEach(sf => {
                sf.value_list.forEach(value => {
                /*
                let label = value.description || value.code;
                const code = value.code || label;
                if (code !== label) { label = `${label}`; }
                /**/
                    list.push({id: value.code, label: value.description});
                });
            });

        return this.toCache('sfvalues', tag, sfCode, list);
    }

    getIndicatorValues(tag: string, which: 'ind1' | 'ind2'): ComboboxEntry[] {
        if (!tag || !this.tagMap[tag]) { return; }

        const cached = this.fromCache('indicators', tag, which);
        if (cached) { return cached; }

        let values = this.tagMap[tag][which];
        if (!values) { return; }

        values = values.map(value => ({
            id: value.code,
            label: value.description
        }))
            .sort((a, b) => a.id < b.id ? -1 : 1);

        return this.toCache('indicators', tag, which, values);
    }


    getFfFieldMeta(fieldCode: string): Promise<IdlObject> {
        return this.getFfPosTable().then(table => {

            // Best I can tell, the AngJS MARC editor stores the
            // full POS table for all record types in every copy of
            // the table, hence the seemingly extraneous check in ffType.
            const meta = table.find(
                field =>
                    field.fixed_field === fieldCode
                    && field.rec_type === this.selector.ffType
            );

            if (meta) {
                return this.getFfCRADTable().then(ctable => {
                    const crad_value = ctable.find(crad_row => crad_row.fixed_field === fieldCode);
                    if (crad_value) {
                        meta['description'] = crad_value.description;
                    }

                    return meta;
                });
            }

            return meta; // will be null if we get here
        });
    }

    // Assumes getFfPosTable and getFfValueTable have already been
    // invoked for the requested record type.
    getFfValues(fieldCode: string): ComboboxEntry[] {

        const cached = this.fromCache('ffvalues', fieldCode);
        if (cached) { return cached; }

        let values = this.ffValueTable;

        if (!values || !values[fieldCode]) { return null; }

        // extract the canned set of possible values for our
        // fixed field.  Ignore those whose value exceeds the
        // specified field length.
        values = values[fieldCode]
            .filter(val => val[0].length <= val[2])
            .map(val => ({id: val[0], label: `${val[1]}`}))
            .sort((a, b) => a.id < b.id ? -1 : 1);

        return this.toCache('ffvalues', fieldCode, null, values);
    }

}

@Injectable()
export class TagTableService {

    tagTables: {[marcRecordType: string]: TagTable} = {};
    controlledBibTags: string[];

    constructor(
        private store: StoreService,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
    ) {}

    loadTags(selector: TagTableSelector): Promise<TagTable> {
        if (!selector.marcFormat) {
            selector.marcFormat = DEFAULT_MARC_FORMAT;
        }

        const tt = new TagTable(
            this.store, this.auth, this.net, this.pcrud, selector);

        this.tagTables[selector.marcRecordType] = tt;

        return tt.load().then(_ => tt);
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



