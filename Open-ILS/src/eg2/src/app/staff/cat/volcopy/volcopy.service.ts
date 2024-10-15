import {Injectable, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {VolCopyContext} from './volcopy';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {StoreService} from '@eg/core/store.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Managing volcopy data */

interface VolCopyDefaults {
    // Default values per field.
    values: {[field: string]: any};
    // Most fields are visible by default.
    hidden: {[field: string]: boolean};
    // ... But some fields are hidden by default.
    visible: {[field: string]: boolean};
}

@Injectable()
export class VolCopyService {

    autoId = -1;

    localOrgs: number[];
    defaults: VolCopyDefaults = null;
    copyStatuses: {[id: number]: IdlObject} = {};
    bibParts: {[bibId: number]: IdlObject[]} = {};

    // This will be all 'local' copy locations plus any remote
    // locations that we are required to interact with.
    copyLocationMap: {[id: number]: IdlObject} = {};

    // Track this here so it can survive route changes.
    currentContext: VolCopyContext;

    statCatEntryMap: {[id: number]: IdlObject} = {}; // entry id => entry

    templateNames: ComboboxEntry[] = [];
    templates: any = {};

    commonData: {[key: string]: IdlObject[]} = {};
    magicCopyStats: number[] = [];

    hideVolOrgs: number[] = [];

    // Currently spans from volcopy.component to vol-edit.component.
    genBarcodesRequested: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private evt: EventService,
        private net: NetService,
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private holdings: HoldingsService,
        private store: StoreService,
        private serverStore: ServerStoreService
    ) {}


    // Fetch the data that is always needed.
    load(): Promise<any> {

        if (this.commonData.acp_item_type_map) { return Promise.resolve(); }

        this.localOrgs = this.org.fullPath(this.auth.user().ws_ou(), true);

        this.hideVolOrgs = this.org.list()
            .filter(o => !this.org.canHaveVolumes(o)).map(o => o.id());

        return this.net.request(
            'open-ils.cat', 'open-ils.cat.volcopy.data', this.auth.token()
        ).pipe(tap(dataset => {
            const key = Object.keys(dataset)[0];
            this.commonData[key] = dataset[key];
        })).toPromise()
            .then(_ => this.ingestCommonData())

        // These will come up later -- prefetch.
            .then(_ => this.serverStore.getItemBatch([
                'cat.copy.templates',
                'eg.cat.volcopy.defaults',
                'eg.cat.record.summary.collapse'
            ]))

            .then(_ => this.holdings.getMagicCopyStatuses())
            .then(stats => this.magicCopyStats = stats)
            .then(_ => this.fetchDefaults())
            .then(_ => this.fetchTemplates());
    }

    ingestCommonData() {

        this.commonData.acp_location.forEach(
            loc => this.copyLocationMap[loc.id()] = loc);

        // Remove the -1 prefix and suffix so they can be treated
        // specially in the markup.
        this.commonData.acn_prefix =
            this.commonData.acn_prefix.filter(pfx => pfx.id() !== -1);

        this.commonData.acn_suffix =
            this.commonData.acn_suffix.filter(sfx => sfx.id() !== -1);

        this.commonData.acp_status.forEach(
            stat => this.copyStatuses[stat.id()] = stat);

        this.commonData.acp_stat_cat.forEach(cat => {
            cat.entries().forEach(
                entry => this.statCatEntryMap[entry.id()] = entry);
        });
    }

    getLocation(id: number): Promise<IdlObject> {
        if (this.copyLocationMap[id]) {
            return Promise.resolve(this.copyLocationMap[id]);
        }

        return this.pcrud.retrieve('acpl', id)
            .pipe(tap(loc => this.copyLocationMap[loc.id()] = loc))
            .toPromise();
    }

    fetchTemplates(): Promise<any> {

        return this.serverStore.getItem('cat.copy.templates')
            .then(templates => {

                if (!templates) { return null; }

                this.templates = templates;

                this.templateNames = Object.keys(templates)
                    .sort((n1, n2) => n1 < n2 ? -1 : 1)
                    .map(name => ({id: name, label: name}));

                this.store.removeLocalItem('cat.copy.templates');
            });
    }


    saveTemplates(): Promise<any> {
        return this.serverStore.setItem('cat.copy.templates', this.templates)
            .then(() => this.fetchTemplates());
    }

    fetchDefaults(): Promise<any> {
        if (this.defaults) { return Promise.resolve(); }

        return this.serverStore.getItem('eg.cat.volcopy.defaults').then(
            (defaults: VolCopyDefaults) => {
                this.defaults = defaults || {values: {}, hidden: {}, visible: {}};
                if (!this.defaults.values)  { this.defaults.values  = {}; }
                if (!this.defaults.hidden)  { this.defaults.hidden  = {}; }
                if (!this.defaults.visible) { this.defaults.visible = {}; }
            }
        );
    }

    // Fetch vol labels for a single record based on the defeault
    // classification scheme
    fetchRecordVolLabels(id: number): Promise<string[]> {
        if (!id) { return Promise.resolve([]); }

        // NOTE: see https://bugs.launchpad.net/evergreen/+bug/1874897
        // for more on MARC call numbers and classification scheme.
        // If there is no workstation-default value, pass null
        // to use the org unit default.

        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.marc_cn.retrieve',
            id, this.defaults.values.classification || null
        ).toPromise().then(res => {
            return Object.values(res)
                .map(blob => Object.values(blob)[0]).sort();
        });
    }

    createStubVol(recordId: number, orgId: number, options?: any): IdlObject {
        if (!options) { options = {}; }

        const vol = this.idl.create('acn');
        vol.id(this.autoId--);
        vol.isnew(true);
        vol.record(recordId);
        vol.label(null);
        vol.owning_lib(Number(orgId));
        vol.prefix(this.defaults.values.prefix || -1);
        vol.suffix(this.defaults.values.suffix || -1);

        return vol;
    }

    createStubCopy(vol: IdlObject, options?: any): IdlObject {
        if (!options) { options = {}; }

        const copy = this.idl.create('acp');
        copy.id(this.autoId--);
        copy.isnew(true);
        copy.call_number(vol); // fleshed
        copy.price('0.00');
        copy.deposit_amount('0.00');
        copy.fine_level(2);     // Normal
        copy.loan_duration(2);  // Normal
        copy.location(this.commonData.acp_default_location); // fleshed
        copy.circ_lib(Number(options.circLib || vol.owning_lib()));

        copy.deposit('f');
        copy.circulate('t');
        copy.holdable('t');
        copy.opac_visible('t');
        copy.ref('f');
        copy.mint_condition('t');

        copy.parts([]);
        copy.tags([]);
        copy.notes([]);
        copy.copy_alerts([]);
        copy.stat_cat_entries([]);

        copy.barcode(options.barcode || '');

        return copy;
    }


    // Applies label_class values to a batch of volumes, followed by
    // applying labels to vols that need it.
    setVolClassLabels(vols: IdlObject[]): Promise<any> {

        return this.applyVolClasses(vols)
            .then(_ => this.applyVolLabels(vols));
    }

    // Apply label_class values to any vols that need it based either on
    // the workstation default value or the org setting for the
    // owning lib library.
    applyVolClasses(vols: IdlObject[]): Promise<any> {

        vols = vols.filter(v => !v.label_class());

        const orgIds: any = {};
        vols.forEach(vol => orgIds[vol.owning_lib()] = true);

        let promise = Promise.resolve(); // Serialization

        if (this.defaults.values.classification) {
            // Workstation default classification overrides the
            // classification that might be used at the owning lib.

            vols.forEach(vol =>
                vol.label_class(this.defaults.values.classification));

            return promise;

        } else {

            // Get the label class default for each owning lib and
            // apply to the volumes owned by that lib.

            Object.keys(orgIds).map(orgId => Number(orgId))
                .forEach(orgId => {
                    promise = promise.then(_ => {

                        return this.org.settings(
                            'cat.default_classification_scheme', orgId)
                            .then(sets => {

                                const orgVols = vols.filter(v => v.owning_lib() === orgId);
                                orgVols.forEach(vol => {
                                    vol.label_class(
                                        // Strip quotes resulting from old style ou settings
                                        Number(sets['cat.default_classification_scheme']) || 1
                                    );
                                });
                            });
                    });
                });
        }

        return promise;
    }

    // Apply labels to volumes based on the appropriate MARC call number.
    applyVolLabels(vols: IdlObject[]): Promise<any> {

        vols = vols.filter(v => !v.label());

        // Serialize
        let promise = Promise.resolve();

        vols.forEach(vol => {

            // Avoid unnecessary lookups.
            // Note the label may have been applied to this volume
            // in a previous iteration of this loop.
            if (vol.label()) { return; }

            // Avoid applying call number labels to existing call numbers
            // that don't already have a label.  This allows the user to
            // see that an action needs to be taken on the volume.
            if (!vol.isnew()) { return; }

            promise = promise.then(_ => {
                return this.net.request(
                    'open-ils.cat',
                    'open-ils.cat.biblio.record.marc_cn.retrieve',
                    vol.record(), vol.label_class()).toPromise()

                    .then(cnList => {
                    // Use '_' as a placeholder to indicate when a
                    // vol has already been addressed.
                        let label = '_';

                        if (cnList.length > 0) {
                            const field = Object.keys(cnList[0])[0];
                            label = cnList[0][field];
                        }

                        // Avoid making duplicate marc_cn calls by applying
                        // the label to all vols that apply.
                        vols.forEach(vol2 => {
                            if (vol2.record() === vol.record() &&
                            vol2.label_class() === vol.label_class()) {
                                vol.label(label);
                            }
                        });
                    });
            });
        });

        return promise.then(_ => {
            // Remove the placeholder label
            vols.forEach(vol => {
                if (vol.label() === '_') { vol.label(''); }
            });
        });
    }

    // Sets the default copy status for a batch of copies.
    setCopyStatus(copies: IdlObject[]): Promise<any> {

        const fastAdd = this.currentContext.fastAdd;

        const setting = fastAdd ?
            'cat.default_copy_status_fast' :
            'cat.default_copy_status_normal';

        const orgs: any = {};
        copies.forEach(copy => orgs[copy.circ_lib()] = 1);

        let promise = Promise.resolve(); // Seralize

        // Pre-fetch needed org settings
        Object.keys(orgs).forEach(org => {
            promise = promise.then(_ => {
                return this.org.settings(setting, +org)
                    .then(sets => {
                        // eslint-disable-next-line no-magic-numbers
                        orgs[org] = sets[setting] || (fastAdd ? 0 : 5);
                    });
            });
        });

        promise.then(_ => {
            Object.keys(orgs).forEach(org => {
                copies.filter(copy => copy.circ_lib() === +org)
                    .forEach(copy => copy.status(orgs[org]));
            });
        });

        return promise;
    }

    saveDefaults(): Promise<any> {

        // Scrub unnecessary content before storing.

        Object.keys(this.defaults.values).forEach(field => {
            if (this.defaults.values[field] === null) {
                delete this.defaults.values[field];
            }
        });

        Object.keys(this.defaults.hidden).forEach(field => {
            if (this.defaults.hidden[field] !== true) {
                delete this.defaults.hidden[field];
            }
        });

        return this.serverStore.setItem(
            'eg.cat.volcopy.defaults', this.defaults);
    }

    fetchBibParts(recordIds: number[]) {

        if (recordIds.length === 0) { return; }

        // All calls fetch updated data since we may be creating
        // new mono parts during editing.

        this.pcrud.search('bmp',
            {record: recordIds, deleted: 'f'})
            .subscribe(
                part => {
                    if (!this.bibParts[part.record()]) {
                        this.bibParts[part.record()] = [];
                    }
                    if (this.bibParts[part.record()].every(existingPart => {return existingPart.label() !== part.label();})){
                        this.bibParts[part.record()].push(part);
                    }
                },
                (err: unknown) => {},
                () => {
                    recordIds.forEach(bibId => {
                        if (this.bibParts[bibId]) {
                            this.bibParts[bibId] = this.bibParts[bibId]
                                .sort((p1, p2) =>
                                    p1.label_sortkey() < p2.label_sortkey() ? -1 : 1);
                        }
                    });
                }
            );
    }


    copyStatIsMagic(statId: number): boolean {
        return this.magicCopyStats.includes(statId);
    }

    restrictCopyDelete(statId: number): boolean {
        return this.copyStatuses[statId] &&
               this.copyStatuses[statId].restrict_copy_delete() === 't';
    }

    // Returns true if any items are missing values for a required stat cat.
    missingRequiredStatCat(): boolean {
        let missing = false;

        this.currentContext.copyList().forEach(copy => {
            if (!copy.barcode()) { return; }

            this.commonData.acp_stat_cat.forEach(cat => {
                if (cat.required() !== 't') { return; }

                const matches = copy.stat_cat_entries()
                    .filter(e => e.stat_cat() === cat.id());

                if (matches.length === 0) {
                    missing = true;
                }
            });
        });

        return missing;
    }
}

