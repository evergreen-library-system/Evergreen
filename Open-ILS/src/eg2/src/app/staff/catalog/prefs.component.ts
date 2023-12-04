import {Component, OnInit, ViewChild} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {StaffCatalogService} from './catalog.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Component for managing catalog preferences */

const CATALOG_PREFS = [
    'eg.search.search_lib',
    'eg.search.pref_lib',
    'eg.search.adv_pane',
    'eg.catalog.results.count',
    'eg.staffcat.exclude_electronic',
    'eg.staffcat.course_materials_selector',
    'circ.course_materials_opt_in'
];

@Component({
    templateUrl: 'prefs.component.html'
})
export class PreferencesComponent implements OnInit {

    settings: Object = {};

    @ViewChild('successMsg', {static: false}) successMsg: StringComponent;
    @ViewChild('failMsg', {static: false}) failMsg: StringComponent;

    constructor(
        private store: ServerStoreService,
        private toast: ToastService,
        private staffCat: StaffCatalogService,
    ) {}

    ngOnInit() {
        this.staffCat.createContext();

        // Pre-fetched by the resolver.
        return this.store.getItemBatch(CATALOG_PREFS)
            .then(settings => this.settings = settings);
    }

    showCoursePreferences() {
        return this.settings['circ.course_materials_opt_in'];
    }

    orgChanged(org: IdlObject, setting: string) {
        const localVar = setting === 'eg.search.search_lib' ?
            'defaultSearchOrg' : 'prefOrg';

        if (org.id()) {
            this.updateValue(setting, org ? org.id() : null)
                .then(val => this.staffCat[localVar] = val);
        }
    }

    paneChanged(entry: ComboboxEntry) {
        this.updateValue('eg.search.adv_pane', entry ? entry.id : null)
            .then(value => this.staffCat.defaultTab = value);
    }

    countChanged() {
        this.updateValue('eg.catalog.results.count',
            this.settings['eg.catalog.results.count'] || null)
            .then(value => {
                // eslint-disable-next-line no-magic-numbers
                this.staffCat.searchContext.pager.limit = value || 20;
            });
    }

    checkboxChanged(setting: string) {
        const value = this.settings[setting];
        this.updateValue(setting, value || null);

        if (setting === 'eg.staffcat.exclude_electronic') {
            this.staffCat.showExcludeElectronic = value;
        }
    }

    updateValue(setting: string, value: any): Promise<any> {
        const promise = (value === null) ?
            this.store.removeItem(setting) :
            this.store.setItem(setting, value);

        return promise
            .then(_ => this.toast.success(this.successMsg.text))
            .then(_ => value);
    }

    hasNoHistory(): boolean {
        return history.length === 0;
    }

    goBack() {
        history.back();
    }
}

