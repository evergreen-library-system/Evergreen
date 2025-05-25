/* eslint-disable max-len, no-prototype-builtins */
import {Injectable, EventEmitter, OnDestroy} from '@angular/core';
import {Subject, tap, takeUntil} from 'rxjs';
import {SafeUrl} from '@angular/platform-browser';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {AuthService} from '@eg/core/auth.service';
import {VolCopyContext} from './volcopy';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {FileExportService} from '@eg/share/util/file-export.service';
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
export class VolCopyService implements OnDestroy {

    autoId = -1;

    localOrgs: number[];
    defaults: VolCopyDefaults = null;
    copyStatuses: {[id: number]: IdlObject} = {};
    acnLabelClasses: {[id: number]: IdlObject} = {};
    acnPrefixes: {[id: number]: IdlObject} = {};
    acnSuffixes: {[id: number]: IdlObject} = {};
    bibParts: {[bibId: number]: IdlObject[]} = {};

    // This will be all 'local' copy locations plus any remote
    // locations that we are required to interact with.
    copyLocationMap: {[id: number]: IdlObject} = {};

    // Track this here so it can survive route changes.
    currentContext: VolCopyContext;

    statCatEntryMap: {[id: number]: IdlObject} = {}; // entry id => entry

    private destroy$ = new Subject<void>;
    private templatesRefreshed = new Subject<void>();
    templatesRefreshed$ = this.templatesRefreshed.asObservable();

    templateNames: ComboboxEntry[] = [];
    templates: any = {};
    templatesToExport: any = {};

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
        private fileExport: FileExportService,
        private store: StoreService,
        private serverStore: ServerStoreService
    ) {
        // Listen for ServerStoreService cache invalidation completions within this tab
        this.serverStore.cacheCleared$
            .pipe(takeUntil(this.destroy$))
            .subscribe(() => {
                this.fetchTemplates().then(() => {
                    this.templatesRefreshed.next();
                });
            });
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }

    // Fetch the data that is always needed.
    load(): Promise<any> {
        console.debug('VolCopyService.load() starting');

        if (this.commonData.acp_item_type_map) {
            console.debug('VolCopyService.load() - commonData already loaded, returning early');
            return Promise.resolve();
        }

        this.localOrgs = this.org.fullPath(this.auth.user().ws_ou(), true);
        console.debug('VolCopyService.load() - localOrgs set:', this.localOrgs);

        this.hideVolOrgs = this.org.list()
            .filter(o => !this.org.canHaveVolumes(o)).map(o => o.id());
        console.debug('VolCopyService.load() - hideVolOrgs set:', this.hideVolOrgs);

        return this.net.request(
            'open-ils.cat', 'open-ils.cat.volcopy.data', this.auth.token()
        ).pipe(tap(dataset => {
            console.debug('VolCopyService.load() - received dataset:', dataset);
            const key = Object.keys(dataset)[0];
            this.commonData[key] = dataset[key];
        })).toPromise()
            .then(result => {
                console.debug('VolCopyService.load() - after initial data fetch:', result);
                return this.ingestCommonData();
            })
            .then(result => {
                console.debug('VolCopyService.load() - after ingestCommonData');
                return this.serverStore.getItemBatch([
                    'cat.copy.templates',
                    'eg.cat.volcopy.defaults',
                    'eg.cat.record.summary.collapse'
                ]);
            })
            .then(batchResult => {
                console.debug('VolCopyService.load() - after getItemBatch:', batchResult);
                return this.holdings.getMagicCopyStatuses();
            })
            .then(stats => {
                console.debug('VolCopyService.load() - got magicCopyStats:', stats);
                this.magicCopyStats = stats;
                return this.fetchDefaults();
            })
            .then(result => {
                console.debug('VolCopyService.load() - after fetchDefaults');
                return this.fetchTemplates();
            })
            .then(result => {
                console.debug('VolCopyService.load() - after fetchTemplates, templates:', this.templates);
                return result;
            })
            .catch(error => {
                console.error('VolCopyService.load() - Error in promise chain:', error);
                throw error;
            });
    }

    ingestCommonData() {

        this.commonData.acp_location.forEach(
            loc => this.copyLocationMap[loc.id()] = loc);

        // We want the magic -1 id for these
        this.commonData.acn_prefix.forEach(
            prefix => this.acnPrefixes[prefix.id()] = prefix);

        this.commonData.acn_suffix.forEach(
            suffix => this.acnSuffixes[suffix.id()] = suffix);

        // Remove the -1 prefix and suffix so they can be treated
        // specially in the markup.
        this.commonData.acn_prefix =
            this.commonData.acn_prefix.filter(pfx => pfx.id() !== -1);

        this.commonData.acn_suffix =
            this.commonData.acn_suffix.filter(sfx => sfx.id() !== -1);

        this.commonData.acn_class.forEach(
            label_class => this.acnLabelClasses[label_class.id()] = label_class);

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
            .pipe(tap(loc => {
                console.debug(`getLocation(${id})`,loc);
                this.copyLocationMap[loc.id()] = loc;
            }))
            .toPromise();
    }

    fetchTemplates(): Promise<any> {
        console.debug('VolCopyService.fetchTemplates() starting');
        return this.serverStore.getItem('cat.copy.templates')
            .then(templates => {
                console.debug('VolCopyService.fetchTemplates() - received templates:', templates);
                if (!templates) {
                    console.debug('VolCopyService.fetchTemplates() - no templates found');
                    return null;
                }
                this.templates = templates;
                this.templateNames = Object.keys(templates)
                    .sort((n1, n2) => n1 < n2 ? -1 : 1)
                    .map(name => ({id: name, label: name}));
                console.debug('VolCopyService.fetchTemplates() - templateNames set:', this.templateNames);
                this.store.removeLocalItem('cat.copy.templates');
                return templates;
            })
            .catch(error => {
                console.error('VolCopyService.fetchTemplates() - Error:', error);
                throw error;
            });
    }

    saveTemplates(): Promise<any> {
        console.debug('saving cat.copy.templates', this.templates);
        return this.serverStore.setItem('cat.copy.templates', this.templates)
            .then(() => this.templates);
    }

    deleteTemplates(templateNames: string[]): Promise<any> {
        if (!this.templates) {
            return Promise.reject(new Error('Templates not initialized'));
        }

        const deletedTemplates: string[] = [];
        const notFoundTemplates: string[] = [];

        templateNames.forEach(name => {
            if (this.templates.hasOwnProperty(name)) {
                delete this.templates[name];
                deletedTemplates.push(name);
            } else {
                notFoundTemplates.push(name);
            }
        });

        this.templateNames = this.templateNames.filter(entry => !deletedTemplates.includes(entry.id));

        return this.saveTemplates().then(() => ({
            deleted: deletedTemplates,
            notFound: notFoundTemplates
        }));
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
        vol.label_class(this.defaults.values.classification || 1);
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
                { next: part => {
                    const updatedBibParts =  {...this.bibParts};
                    if (!updatedBibParts[part.record()]) {
                        updatedBibParts[part.record()] = [];
                    }
                    if (updatedBibParts[part.record()].every(existingPart => existingPart.label() !== part.label())){
                        updatedBibParts[part.record()].push(part);
                    }
                    this.bibParts = updatedBibParts;
                }, error: (err: unknown) => {}, complete: () => {
                    const finalBibParts = {...this.bibParts};
                    recordIds.forEach(bibId => {
                        if (finalBibParts[bibId]) {
                            finalBibParts[bibId] = finalBibParts[bibId]
                                .sort((p1, p2) =>
                                    p1.label_sortkey() < p2.label_sortkey() ? -1 : 1);
                        }
                    });
                    this.bibParts = finalBibParts;
                } }
            );
    }


    copyStatIsMagic(statId: number): boolean {
        return this.magicCopyStats.includes(statId);
    }

    restrictCopyDelete(statId: number): boolean {
        return this.copyStatuses[statId] && (
            this.copyStatuses[statId].restrict_copy_delete() === 't'
           || this.copyStatuses[statId].restrict_copy_delete() === true
        );
    }

    // Returns true if any items are missing values for a required stat cat.
    missingRequiredStatCat(): boolean {
        let missing = false;

        this.currentContext.copyList().forEach(copy => {
            if (!copy.barcode()) { return; }

            this.commonData.acp_stat_cat.forEach(cat => {
                if (cat.required() !== 't' && cat.required() !== true) { return; }

                const matches = copy.stat_cat_entries()
                    .filter(e => e.stat_cat() === cat.id());

                if (matches.length === 0) {
                    missing = true;
                }
            });
        });

        return missing;
    }

    exportTemplate($event, selected) {
        const exportList = selected ? this.templatesToExport : this.templates;
        // console.debug('We will export templates: ', exportList);
        this.fileExport.exportFile(
            $event, JSON.stringify(exportList), 'text/json');
    }

    importTemplate($event): Promise<{added: string[], overwritten: string[]}> {
        const file: File = $event.target.files[0];
        if (!file) {
            return Promise.resolve({ added: [], overwritten: [] });
        }

        return new Promise((resolve, reject) => {
            const reader = new FileReader();

            reader.addEventListener('load', () => {
                try {
                    const template = JSON.parse(reader.result as string);
                    const added: string[] = [];
                    const overwritten: string[] = [];
                    const theKeys = Object.keys(template);

                    for (let i = 0; i < theKeys.length; i++) {
                        const name = theKeys[i];
                        const data = template[name];

                        // backwards compatibility
                        if (data.copy_notes && !data.notes) {
                            data.notes = data.copy_notes;
                            delete data.copy_notes;
                        }

                        // convert actual booleans to 't' and 'f'
                        Object.keys(data).forEach(key => {
                            if (this.idl.classes.acp.field_map[key]?.datatype === 'bool') {
                                if (data[key] === true) { data[key] = 't'; } else if (data[key] === false) { data[key] = 'f'; }
                            }
                        });

                        // same for alerts, notes, and tags
                        const ant = { alerts: 'aca', notes: 'acpn', tags: 'acpt' };
                        Object.keys(ant).forEach(thing => {
                            if (data[thing] && Array.isArray(data[thing])) {
                                data[thing].forEach(thingElement => {
                                    Object.keys(thingElement).forEach(key => {
                                        if (this.idl.classes[ant[thing]].field_map[key].datatype === 'bool') {
                                            if (thingElement[key] === true) { thingElement[key] = 't'; } else if (thingElement[key] === false) { thingElement[key] = 'f'; }
                                        }
                                    });
                                });
                            }
                        });

                        // Check if template already exists
                        if (this.templates.hasOwnProperty(name)) {
                            overwritten.push(name);
                        } else {
                            added.push(name);
                        }
                        this.templates[name] = data;
                    }

                    this.saveTemplates().then(() => {
                        // Adds the new ones to the list and re-sorts the labels
                        return this.fetchTemplates();
                    }).then(() => {
                        this.templatesRefreshed.next();
                        resolve({ added, overwritten });
                    }).catch(error => {
                        reject(error);
                    });

                } catch (E) {
                    console.error('Invalid Item Attribute template', E);
                    reject(E);
                }
            });

            reader.readAsText(file);
        });
    }

    // Returns null when no export is in progress.
    exportTemplateUrl(): SafeUrl {
        return this.fileExport.safeUrl;
    }
}

