import { Injectable } from '@angular/core';
import { Router, ActivatedRoute } from '@angular/router';
import { BehaviorSubject, Observable, lastValueFrom } from 'rxjs';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { BucketService } from './bucket.service';
import { BucketClass, BucketConfigService } from './bucket-config.service';
import { Pager } from '@eg/share/util/pager';
import { GridColumnSort } from '@eg/share/grid/grid';

export interface BucketQueryResult {
  bucketIds: number[];
  count: number;
}

export interface BucketView {
  label: string | null;
  sort_key: number | null;
  count: number | null;
  bucketIdQuery: (pager: Pager, sort: GridColumnSort[], justCount: Boolean) => Promise<BucketQueryResult>;
}

export interface BucketStateConfig {
  // Optional custom views to be added to the standard set
  customViews?: {[key: string]: BucketView};
  // URL segment mapping overrides for specific views
  urlMapping?: {[key: string]: string};
  // Base route for navigation
  baseRoute?: string;
  // Initial view to display when loading
  defaultView?: string;
}

@Injectable()
export class BucketStateService {
  private _currentView = new BehaviorSubject<string>('user');
  private _views: {[key: string]: BucketView} = {};
  private _countInProgress = false;
  private _bucketIdToRetrieve: number;
  private _favoriteIds: number[] = [];
  private _bucketClass: BucketClass;
  private _config: BucketStateConfig;

  constructor(
    private router: Router,
    private auth: AuthService,
    private idl: IdlService,
    private pcrud: PcrudService,
    private net: NetService,
    private bucketService: BucketService,
    private bucketConfig: BucketConfigService
  ) {}

  /**
   * Initialize the bucket state service for a specific bucket class
   */
  initialize(bucketClass: BucketClass, config: BucketStateConfig = {}): void {
    this._bucketClass = bucketClass;
    this._config = {
      defaultView: 'user',
      baseRoute: '',
      ...config
    };
    this.currentView = this._config.defaultView;
    this.initViews();
  }

  get currentView(): string {
    return this._currentView.getValue();
  }

  set currentView(view: string) {
    this._currentView.next(view);
  }

  get currentView$(): Observable<string> {
    return this._currentView.asObservable();
  }

  get views(): {[key: string]: BucketView} {
    return this._views;
  }

  get bucketIdToRetrieve(): number {
    return this._bucketIdToRetrieve;
  }

  set bucketIdToRetrieve(id: number) {
    this._bucketIdToRetrieve = id;
  }

  get favoriteIds(): number[] {
    return this._favoriteIds;
  }

  get countInProgress(): boolean {
    return this._countInProgress;
  }

  get bucketClass(): BucketClass {
    return this._bucketClass;
  }

  search_or_count(justCount, hint, query, pcrudOps, pcrudReqOps): Observable<number | any[]> {
    if (justCount) {
      return this.net.request('open-ils.actor', 'open-ils.actor.count_with_pcrud.authoritative',
        this.auth.token(), hint, query);
    } else {
      return this.pcrud.search(hint, query, pcrudOps, pcrudReqOps);
    }
  }

  initViews() {
    const bucketFmClass = this.bucketConfig.getBucketFmClass(this._bucketClass);

    // Initialize standard views
    this._views = {
      all: {
        label: $localize`Visible to me`,
        sort_key: 10,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          let result: BucketQueryResult;
          const response = await lastValueFrom(
            this.search_or_count(justCount, bucketFmClass,
              { id: { '!=' : null } },
              {
                ...(pager?.limit && { limit: pager.limit }),
                ...(pager?.offset && { offset: pager.offset }),
                ...(translatedSort && translatedSort),
              },
              { idlist: true, atomic: true }
            )
          );
          if (justCount) {
            result = { bucketIds: [], count: response as number };
            this._views['all']['count'] = result['count'];
          } else {
            const ids = response as number[];
            result = { bucketIds: ids, count: ids.length };
          }
          return result;
        }
      },
      user: {
        label: $localize`My buckets`,
        sort_key: 1,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          let result: BucketQueryResult;
          const response = await lastValueFrom(
            this.search_or_count(justCount, bucketFmClass,
              { owner: this.auth.user().id() },
              {
                ...(pager?.limit && { limit: pager.limit }),
                ...(pager?.offset && { offset: pager.offset }),
                ...(translatedSort && translatedSort),
              },
              { idlist: true, atomic: true }
            )
          );
          if (justCount) {
            result = { bucketIds: [], count: response as number };
            this._views['user']['count'] = result['count'];
          } else {
            const ids = response as number[];
            result = { bucketIds: ids, count: ids.length };
          }
          return result;
        }
      },
      favorites: {
        label: $localize`Favorites`,
        sort_key: 2,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          this._favoriteIds = this.bucketService.getFavoriteBucketIds(this._bucketClass);
          let result: BucketQueryResult;
          if (this._favoriteIds.length) {
            const response = await lastValueFrom(
              this.search_or_count(justCount, bucketFmClass,
                { id: this._favoriteIds },
                {
                  ...(pager?.limit && { limit: pager.limit }),
                  ...(pager?.offset && { offset: pager.offset }),
                  ...(translatedSort && translatedSort),
                },
                { idlist: true, atomic: true }
              )
            );
            if (justCount) {
              result = { bucketIds: [], count: response as number };
              this._views['favorites']['count'] = result['count'];
            } else {
              const ids = response as number[];
              result = { bucketIds: ids, count: ids.length };
            }
          } else {
            result = { bucketIds: [], count: 0 };
            this._views['favorites']['count'] = 0;
          }
          return result;
        }
      },
      recent: {
        label: $localize`Recent`,
        sort_key: 3,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          const storageKey = this.bucketConfig.getStorageKey(this._bucketClass);
          const recentBucketIds = this.bucketService.getRecentBucketIds(this._bucketClass);
          let result: BucketQueryResult;
          if (recentBucketIds.length) {
            const response = await lastValueFrom(
              this.search_or_count(justCount, bucketFmClass,
                { id: recentBucketIds },
                {
                  ...(pager?.limit && { limit: pager.limit }),
                  ...(pager?.offset && { offset: pager.offset }),
                  ...(translatedSort && translatedSort),
                },
                { idlist: true, atomic: true }
              )
            );
            if (justCount) {
              result = { bucketIds: [], count: response as number };
              this._views['recent']['count'] = result['count'];
            } else {
              const ids = response as number[];
              result = { bucketIds: ids, count: ids.length };
            }
          } else {
            result = { bucketIds: [], count: 0 };
            this._views['recent']['count'] = 0;
          }
          return result;
        }
      },
      shared_with_others: {
        label: $localize`Shared with others`,
        sort_key: 4,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          let result: BucketQueryResult;
          let method: string;
          if (this._bucketClass === 'biblio') {
            // Use biblio_record_entry
            method = justCount
              ? `open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_others.count`
              : `open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_others`;
          } else {
            method = justCount 
            ? `open-ils.actor.container.retrieve_${this._bucketClass}_buckets_shared_with_others.count`
            : `open-ils.actor.container.retrieve_${this._bucketClass}_buckets_shared_with_others`;
          
          }

          const response = await lastValueFrom(
            this.net.request('open-ils.actor', method, this.auth.token())
          );
          
          if (justCount) {
            result = { bucketIds: [], count: response as number };
            this._views['shared_with_others']['count'] = result['count'];
          } else {
            const ids = response as number[];
            result = { bucketIds: ids, count: ids.length };
          }
          return result;
        }
      },
      shared_with_user: {
        label: $localize`Shared with me`,
        sort_key: 5,
        count: -1,
        bucketIdQuery: async (pager, sort, justCount) => {
          const translatedSort = this.pcrud.translateFlatSortComplex(bucketFmClass, sort);
          let result: BucketQueryResult;
          let method: string;
            if (this._bucketClass === 'biblio') {
                // Use biblio_record_entry
                method = justCount
                ? `open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_user.count`
                : `open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_user`;
            } else {
                method = justCount
                ? `open-ils.actor.container.retrieve_${this._bucketClass}_buckets_shared_with_user.count`
                : `open-ils.actor.container.retrieve_${this._bucketClass}_buckets_shared_with_user`;
            }
          const response = await lastValueFrom(
            this.net.request('open-ils.actor', method, this.auth.token())
          );
          
          if (justCount) {
            result = { bucketIds: [], count: response as number };
            this._views['shared_with_user']['count'] = result['count'];
          } else {
            const ids = response as number[];
            result = { bucketIds: ids, count: ids.length };
          }
          return result;
        }
      },
      retrieved_by_id: {
        label: null,
        sort_key: null,
        count: null,
        bucketIdQuery: async (pager, sort, justCount) => {
          const bucketIds = this._bucketIdToRetrieve ? [this._bucketIdToRetrieve] : [];
          return { bucketIds: bucketIds, count: bucketIds.length };
        }
      }
    };

    // Add any custom views from the config
    if (this._config.customViews) {
      this._views = { ...this._views, ...this._config.customViews };
    }
  }

  getViewKeys(): string[] {
    const viewEntries = Object.entries(this._views)
      .filter(([key, view]) => key && view.label !== null)
      .map(([key, view]) => ({ key, sort_key: view.sort_key }))
      .sort((a, b) => a.sort_key - b.sort_key);
    return viewEntries.map(entry => entry.key);
  }

  isCurrentView(view: string): boolean {
    if (this.currentView === view || (!this.currentView && view === this._config.defaultView)) {
      return true;
    }
    return false;
  }

  async updateCounts() {
    if (this._countInProgress) { return; }
    this._countInProgress = true;

    const viewKeys = this.getViewKeys();

    try {
      viewKeys.forEach(v => { this._views[v].count = -1; });
      // Wait for all bucketIdQuery operations for counting to complete
      await Promise.all(viewKeys.map(v => this._views[v].bucketIdQuery(null, [], true)));
    } catch (error) {
      console.error('Error updating counts:', error);
    }
    
    this._countInProgress = false;
  }

  mapUrlToDatasource(url: string): string {
    const defaultMapping = {
      'admin': 'admin',
      'all': 'all',
      'user': 'user',
      'favorites': 'favorites',
      'recent': 'recent',
      'shared-with-others': 'shared_with_others',
      'shared-with-user': 'shared_with_user'
    };
    
    // Override with any custom mappings
    const mapping = { ...defaultMapping, ...(this._config.urlMapping || {}) };
    
    return mapping[url] || 'retrieved_by_id';
  }

  mapDatasourceToUrl(datasource: string): string {
    const defaultMapping = {
      'admin': 'admin',
      'all': 'all',
      'user': 'user',
      'favorites': 'favorites',
      'recent': 'recent',
      'shared_with_others': 'shared-with-others',
      'shared_with_user': 'shared-with-user'
    };
    
    // Override with any custom mappings
    const mapping = { ...defaultMapping, ...(this._config.urlMapping || {}) };
    
    if (datasource === 'retrieved_by_id' && this._bucketIdToRetrieve) {
      return this._bucketIdToRetrieve.toString();
    }
    
    return mapping[datasource] || this._config.defaultView;
  }

  navigateTo(view: string, route: ActivatedRoute) {
    this.currentView = view;
    const relativeTo = this._config.baseRoute ? route : route.parent;
    this.router.navigate([this._config.baseRoute, this.mapDatasourceToUrl(view)].filter(Boolean), { relativeTo });
  }

  buildRetrieveByIdsQuery(bucketIds: number[], filters: any) {
    const query: any = {};
    
    // Query something even if no ids to avoid exception
    query['id'] = bucketIds.length === 0 ? [-1] : bucketIds.map(b => this.idl.pkeyValue(b));
    
    let query_filters = [];
    Object.keys(filters || {}).forEach(key => {
      query_filters = query_filters.concat(filters[key]);
    });
    
    if (query_filters.length > 0) {
      query['-and'] = query_filters;
    }
    
    return query;
  }
}
