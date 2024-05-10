/* eslint-disable */
import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import {map, mergeMap, defaultIfEmpty, last} from 'rxjs/operators';
import {EMPTY, Observable, of, from} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {StoreService} from '@eg/core/store.service';

@Injectable()
export class Z3950SearchService {

    targets = [];
    searchFields = {};
    rawSearch = '';
    default_targets = {};

    constructor(
        private store: StoreService,
        private serverStore: ServerStoreService,
        private pcrud: PcrudService,
        private net: NetService,
        private org: OrgService,
        private idl: IdlService,
        private event: EventService,
        private auth: AuthService
    ) {
    }


    loadTargets = () => {
        return this.serverStore.getItem('eg.cat.z3950.default_targets')
            .then( t =>  this.default_targets = t || {})
            .then( () => {
                return this.net.request(
                    'open-ils.search',
                    'open-ils.search.z3950.retrieve_services',
                    this.auth.token()
                ).pipe(map(res => {
                    // empty it
                    this.targets.length = 0;

                    Object.entries(res).forEach(([key,value]) => {

                        if (key === 'native-evergreen-catalog' && !value['label']) {
                            value['label'] = $localize`Local Catalog`;
                        }

                        const tgt = {
                            code:       key,
                            settings:   value,
                            selected:   (key in this.default_targets),
                            username:   '',
                            password:   ''
                        };

                        if (tgt.selected && tgt.settings['auth'] == 't') {
                            tgt['username'] = this.default_targets[tgt.code]['username'] || '';
                            tgt['password'] = this.default_targets[tgt.code]['password'] || '';
                        }
                        this.targets.push(tgt);
                    });

                    return this.targets.sort((a, b) => {
		        		if (a.code === 'native-evergreen-catalog') {return -1;}
        				if (b.code === 'native-evergreen-catalog') {return 1;}

                        a = a.settings.label.toLowerCase();
                        b = b.settings.label.toLowerCase();
                        return a < b ? -1 : (a > b ? 1 : 0);
                    });

                })).toPromise();
            }
            );
    };

    loadActiveSearchFields() {
        const curFormInput = {};
        for (const field in this.searchFields) {
            curFormInput[field] = this.searchFields[field].query;
            delete this.searchFields[field];
        }

        this.selectedTargets().forEach(t => {
            Object.entries(t.settings.attrs).forEach(([key, attr]) => {
                if (!(key in this.searchFields)) {
                    this.searchFields[key] = {
	                    label : attr['label'],
    	                query : (key in curFormInput) ? curFormInput[key] : ''
        	        };
                }
            });
        });
    }

    clearSearchFields() {
        for (const field in this.searchFields) {
            this.searchFields[field].query = '';
        }
    }

    currentQuery() {
        const query = {
            service  : [],
            username : [],
            password : [],
            search   : {}
        };

        this.selectedTargets().forEach(t => {
            query.service.push(t.code);
            query.username.push(t.username);
            query.password.push(t.password);
        });

        if (this.rawSearch) {
            query['raw_search'] = this.rawSearch;
        } else {
            Object.entries(this.searchFields).forEach(([key, value]) => {
                if (value['query'] && value['query'].trim()) {
                    query.search[key] = value['query'].trim();
                }
            });
        }

        return query;
    }

    selectedTargets() {
        return this.targets.filter(t => t.selected);
    }

    rawSearchImpossible() {
        const selList = this.selectedTargets();

        // cannot raw-z-search the EG catalog
        if (selList.find(t => t.code === 'native-evergreen-catalog')) {return true;}

        // return false ONLY if exactly one non-native target is selected
        return !(selList.length == 1);
    }

    saveDefaultZ3950Targets() {
        const saved_targets = {};
        this.selectedTargets().forEach(t => {
            saved_targets[t.code] = {};
            if (t.settings.auth == 't') {
                saved_targets[t.code]['username'] = t.username;
                saved_targets[t.code]['password'] = t.password;
            }
        });
        this.serverStore.setItem('eg.cat.z3950.default_targets', saved_targets);
    }

    // store default field
    saveDefaultField(default_field) {
        this.serverStore.setItem('eg.cat.z3950.default_field', default_field);
    }

    fetchDefaultField() {
        return this.serverStore.getItem('eg.cat.z3950.default_field');
    }


}

