import {Injectable} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {BibRecordSummary} from '@eg/share/catalog/bib-record.service';

/**
 * Shared bits needed by the staff version of the catalog.
 */

@Injectable()
export class StaffCatalogService {

    searchContext: CatalogSearchContext;
    routeIndex = 0;
    defaultSearchOrg: IdlObject;
    defaultSearchLimit: number;
    // Track the current template through route changes.
    selectedTemplate: string;

    // TODO: does unapi support pref-lib for result-page copy counts?
    prefOrg: IdlObject;

    // Default search tab
    defaultTab: string;

    // Cache the currently selected detail record (i.g. catalog/record/123)
    // summary so the record detail component can avoid duplicate fetches
    // during record tab navigation.
    currentDetailRecordSummary: any;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService
    ) { }

    createContext(): void {
        // Initialize the search context from the load-time URL params.
        // Do this here so the search form and other context data are
        // applied on every page, not just the search results page.  The
        // search results pages will handle running the actual search.
        this.searchContext =
            this.catUrl.fromUrlParams(this.route.snapshot.queryParamMap);

        this.searchContext.org = this.org; // service, not searchOrg
        this.searchContext.isStaff = true;
        this.applySearchDefaults();
    }

    cloneContext(context: CatalogSearchContext): CatalogSearchContext {
        const params: any = this.catUrl.toUrlParams(context);
        return this.catUrl.fromUrlHash(params);
    }

    applySearchDefaults(): void {
        if (!this.searchContext.searchOrg) {
            this.searchContext.searchOrg =
                this.defaultSearchOrg || this.org.root();
        }

        if (!this.searchContext.pager.limit) {
            this.searchContext.pager.limit = this.defaultSearchLimit || 10;
        }
    }

    /**
     * Redirect to the search results page while propagating the current
     * search paramters into the URL.  Let the search results component
     * execute the actual search.
     */
    search(): void {
        if (!this.searchContext.isSearchable()) { return; }

        const params = this.catUrl.toUrlParams(this.searchContext);

        // Force a new search every time this method is called, even if
        // it's the same as the active search.  Since router navigation
        // exits early when the route + params is identical, add a
        // random token to the route params to force a full navigation.
        // This also resolves a problem where only removing secondary+
        // versions of a query param fail to cause a route navigation.
        // (E.g. going from two query= params to one).  Investigation
        // pending.
        params.ridx = '' + this.routeIndex++;

        this.router.navigate(
          ['/staff/catalog/search'], {queryParams: params});
    }

    /**
     * Redirect to the browse results page while propagating the current
     * browse paramters into the URL.  Let the browse results component
     * execute the actual browse.
     */
    browse(): void {
        if (!this.searchContext.browseSearch.isSearchable()) { return; }
        const params = this.catUrl.toUrlParams(this.searchContext);

        // Force a new browse every time this method is called, even if
        // it's the same as the active browse.  Since router navigation
        // exits early when the route + params is identical, add a
        // random token to the route params to force a full navigation.
        // This also resolves a problem where only removing secondary+
        // versions of a query param fail to cause a route navigation.
        // (E.g. going from two query= params to one).
        params.ridx = '' + this.routeIndex++;

        this.router.navigate(
            ['/staff/catalog/browse'], {queryParams: params});
    }

    // Call number browse.
    // Redirect to cn browse page and let its component perform the search
    cnBrowse(): void {
        if (!this.searchContext.cnBrowseSearch.isSearchable()) { return; }
        const params = this.catUrl.toUrlParams(this.searchContext);
        params.ridx = '' + this.routeIndex++; // see comments above
        this.router.navigate(['/staff/catalog/cnbrowse'], {queryParams: params});
    }

    // Params to genreate a new author search based on a reset
    // clone of the current page params.
    getAuthorSearchParams(summary: BibRecordSummary): any {
        const tmpContext = this.cloneContext(this.searchContext);
        tmpContext.reset();
        tmpContext.termSearch.fieldClass = ['author'];
        tmpContext.termSearch.query = [summary.display.author];
        return this.catUrl.toUrlParams(tmpContext);
    }
}


