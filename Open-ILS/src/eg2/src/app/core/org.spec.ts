import {IdlService} from './idl.service';
import {DbStoreService} from './db-store.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';
import {OrgService} from './org.service';
import { TestBed } from '@angular/core/testing';
import { MockGenerators } from 'test_data/mock_generators';

describe('OrgService', () => {
    let idlService: IdlService;
    let orgService: OrgService;

    beforeEach(() => {
        idlService = new IdlService();
        TestBed.configureTestingModule({providers: [
            {provide: AuthService, useValue: MockGenerators.authService()},
            DbStoreService,
            {provide: NetService, useValue: MockGenerators.netService({})},
            OrgService,
            {provide: PcrudService, useValue: null}
        ]});
        orgService = TestBed.inject(OrgService);
    });

    const initTestData = () => {
        idlService.parseIdl();
        const win: any = window; // trick TS
        win._eg_mock_data.generateOrgTree(idlService, orgService);
    };

    it('should provide get by ID', () => {
        initTestData();
        expect(orgService.get(orgService.tree().id())).toBe(orgService.root());
    });

    it('should provide get by node', () => {
        initTestData();
        expect(orgService.get(orgService.tree())).toBe(orgService.root());
    });

    it('should provide ancestors', () => {
        initTestData();
        expect(orgService.ancestors(2, true)).toEqual([2, 1]);
    });

    it('should provide descendants', () => {
        initTestData();
        expect(orgService.descendants(2, true)).toEqual([2, 4]);
    });

    it('should provide full path', () => {
        initTestData();
        expect(orgService.fullPath(4, true)).toEqual([4, 2, 1]);
    });

    it('should provide root', () => {
        initTestData();
        expect(orgService.root().id()).toEqual(1);
    });

    it('should sort tree by shortname', () => {
        initTestData();
        orgService.sortTree('shortname');
        expect(orgService.root().children()[0].shortname()).toEqual('A');
    });

});


