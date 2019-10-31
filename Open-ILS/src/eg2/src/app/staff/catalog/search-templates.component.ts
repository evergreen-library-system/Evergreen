import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {StringService} from '@eg/share/string/string.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from './catalog.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

const SAVED_TEMPLATES_SETTING = 'eg.catalog.search_templates';
const RECENT_SEARCHES_KEY = 'eg.catalog.recent_searches';

class SearchTemplate {
    name: string;
    params: any = {}; // routerLink-compatible URL params object
    addTime?: number;
    constructor(name: string, params: any) {
        this.name = name;
        this.params = params;
    }
}

@Component({
  selector: 'eg-catalog-search-templates',
  templateUrl: 'search-templates.component.html'
})
export class SearchTemplatesComponent extends DialogComponent implements OnInit {

    recentSearchesCount = 0;
    context: CatalogSearchContext;
    templates: SearchTemplate[] = [];
    searches: SearchTemplate[] = [];
    searchesCacheKey: string;
    templateName: string;

    @Input() searchTab: string;

    @ViewChild('confirmDelete', { static: true }) confirmDelete: ConfirmDialogComponent;
    @ViewChild('confirmDeleteAll', { static: true }) confirmDeleteAll: ConfirmDialogComponent;
    @ViewChild('confirmDeleteSearches', { static: true }) confirmDeleteSearches: ConfirmDialogComponent;

    constructor(
        private org: OrgService,
        private store: StoreService,             // anon cache key
        private serverStore: ServerStoreService, // search templates
        private cache: AnonCacheService,         // recent searches
        private strings: StringService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private modal: NgbModal) {
        super(modal);

        this.store.addLoginSessionKey(RECENT_SEARCHES_KEY);
    }

    ngOnInit() {
        this.context = this.staffCat.searchContext;

        this.serverStore.getItem('opac.staff_saved_search.size')
        .then(size => {
            if (!size) { return; }

            this.recentSearchesCount = Number(size);

            this.getSearches().then(_ => {
                this.searches.forEach(
                    s => s.params.ridx = ++this.staffCat.routeIndex);

                // Save the search that runs on page load.
                this.saveSearch(this.context);
                // Watch for new searches
                this.cat.onSearchComplete.subscribe(ctx => this.saveSearch(ctx));
            });
        });

        this.getTemplates();
    }

    selectedTemplate(): string {
        return this.staffCat.selectedTemplate;
    }

    getSearches(): Promise<any> {
        this.searches = [];

        if (this.searchesCacheKey) {
            // We've already started saving searches in the current instance.

            return this.cache.getItem(this.searchesCacheKey, 'searches')
                .then(searches => this.searches = searches || []);
        }

        const cacheKey = this.store.getLoginSessionItem(RECENT_SEARCHES_KEY);

        if (cacheKey) {
            // We have a saved search key, see if we have any searches.

            this.searchesCacheKey = cacheKey;
            return this.cache.getItem(this.searchesCacheKey, 'searches')
                .then(searches => this.searches = searches || []);

        } else {
            // No saved searches in progress.  Start from scratch.

            return this.cache.setItem(null, 'searches', []) // generates cache key
            .then(cKey => {
                this.searchesCacheKey = cKey;
                this.store.setLoginSessionItem(RECENT_SEARCHES_KEY, cKey);
            });
        }
    }

    searchSelected(search: SearchTemplate) {
        // increment the router index in case the template is used
        // twice in a row.
        search.params.ridx = ++this.staffCat.routeIndex;
    }

    // Returns searches most recent first
    sortSearches(): SearchTemplate[] {
        return this.searches.sort((a, b) => a.addTime > b.addTime ? -1 : 1);
    }

    deleteSearches() {
        this.confirmDeleteSearches.open().subscribe(yes => {
            if (!yes) { return; }
            this.searches = [];
            this.cache.setItem(this.searchesCacheKey, 'searches', []);
        });
    }

    getSearchPath(search: SearchTemplate): string {
        return search.params.searchTab === 'browse' ?
            '/staff/catalog/browse' : '/staff/catalog/search';
    }

    saveSearch(context: CatalogSearchContext) {

        let matchFound = false;
        this.searches.forEach(sch => {
            const tmpCtx = this.catUrl.fromUrlHash(sch.params);
            if (tmpCtx.equals(context)) {
                matchFound = true;
            }
        });

        if (matchFound) { return; }

        let query: string;
        switch (this.searchTab) {
            case 'term':
                query = context.termSearch.query[0];
                break;
            case 'marc':
                query = context.marcSearch.values[0];
                break;
            case 'ident':
                query = context.identSearch.value;
                break;
            case 'browse':
                query = context.browseSearch.value;
                break;
            case 'cnbrowse':
                query = context.cnBrowseSearch.value;
                break;
        }

        if (!query) {
            // no query means nothing was searchable.
            return;
        }

        this.strings.interpolate(
            'eg.catalog.recent_search.label',
            {query: query, tab: this.searchTab}

        ).then(txt => {

            const urlParams = this.prepareSearch(context);
            const search = new SearchTemplate(txt, urlParams);
            search.addTime = new Date().getTime();

            this.searches.unshift(search);

            if (this.searches.length > this.recentSearchesCount) {
                // this bit of magic will lop off the end of the array.
                this.searches.length = this.recentSearchesCount;
            }

            this.cache.setItem(
                this.searchesCacheKey, 'searches', this.searches)
            .then(_ => search.params.ridx = ++this.staffCat.routeIndex);
        });
    }

    getTemplates(): Promise<any> {
        this.templates = [];

        return this.serverStore.getItem(SAVED_TEMPLATES_SETTING).then(
            templates => {
                if (templates && templates.length) {
                    this.templates = templates;

                    // route index required to force the route to take
                    // effect.  See ./catalog.service.ts
                    this.templates.forEach(tmpl =>
                        tmpl.params.ridx = ++this.staffCat.routeIndex);
                }
            }
        );
    }

    sortTemplates(): SearchTemplate[] {
        return this.templates.sort((a, b) =>
            a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
    }

    templateSelected(tmpl: SearchTemplate) {
        this.staffCat.selectedTemplate = tmpl.name;
        // increment the router index in case the template is used
        // twice in a row.
        tmpl.params.ridx = ++this.staffCat.routeIndex;
        console.log('selected template = ', this.staffCat.selectedTemplate);
    }

    // Adds dummy query content to the context object so the
    // CatalogUrlService will recognize the content as searchable
    // and therefor URL-encodable.
    addDummyQueries(context: CatalogSearchContext) {
        context.termSearch.query = context.termSearch.query.map(q => 'x');
        context.marcSearch.values = context.marcSearch.values.map(q => 'x');
        context.browseSearch.value = 'x';
        context.identSearch.value = 'x';
    }

    // Remove the dummy query content before saving the search template.
    removeDummyQueries(urlParams: any) {

        if (Array.isArray(urlParams.query)) {
            const arr = urlParams.query as Array<string>;
            urlParams.query = arr.map(q => '');
        } else {
            urlParams.query = '';
        }

        if (Array.isArray(urlParams.marcValue)) {
            const arr = urlParams.marcValue as Array<string>;
            urlParams.marcValue = arr.map(q => '');
        } else {
            urlParams.marcValue = '';
        }

        urlParams.identQuery = '';
        urlParams.browseTerm = '';
    }

    // Prepares a save-able URL params hash from the current context.
    prepareSearch(ctx: CatalogSearchContext,
        withDummyData?: boolean): {[key: string]: string | string[]} {

        const context = ctx.clone();

        if (withDummyData) {
            this.addDummyQueries(context);
        }

        context.scrub(this.searchTab);

        const urlParams = this.catUrl.toUrlParams(context);

        if (withDummyData) {
            this.removeDummyQueries(urlParams);
        }

        // Some data should not go into the template.
        delete urlParams.org;
        delete urlParams.ridx;

        urlParams.searchTab = this.searchTab;

        return urlParams;
    }

    saveTemplate(): Promise<any> {
        if (!this.templateName) { return Promise.resolve(); }

        this.staffCat.selectedTemplate = this.templateName;

        const urlParams = this.prepareSearch(this.context, true);

        this.templates.push(
            new SearchTemplate(this.templateName, urlParams));

        return this.applyTemplateChanges().then(_ => this.close());
    }

    applyTemplateChanges(): Promise<any> {
        return this.serverStore.setItem(SAVED_TEMPLATES_SETTING, this.templates);
    }

    deleteTemplate() {
        this.confirmDelete.open().subscribe(yes => {
            if (!yes) { return; }

            const templates: SearchTemplate[] = [];
            this.templates.forEach(tmpl => {
                if (tmpl.name !== this.staffCat.selectedTemplate) {
                    templates.push(tmpl);
                }
            });

            this.templates = templates;
            this.staffCat.selectedTemplate = '';
            this.applyTemplateChanges();
        });
    }

    deleteAllTemplates() {
        this.confirmDeleteAll.open().subscribe(yes => {
            if (!yes) { return; }
            this.templates = [];
            this.staffCat.selectedTemplate = '';
            this.applyTemplateChanges();
        });
    }
}


