import {IdlService} from './idl.service';
import {EventService} from './event.service';
import {DbStoreService} from './db-store.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';
import {StoreService} from './store.service';
import {OrgService} from './org.service';
import {HatchService} from './hatch.service';

describe('OrgService', () => {
    let idlService: IdlService;
    let netService: NetService;
    let authService: AuthService;
    let pcrudService: PcrudService;
    let orgService: OrgService;
    let evtService: EventService;
    let storeService: StoreService;
    let hatchService: HatchService;
    let dbStoreService: DbStoreService;

    beforeEach(() => {
        idlService = new IdlService();
        evtService = new EventService();
        hatchService = new HatchService();
        storeService = new StoreService(null /* CookieService */, hatchService);
        netService = new NetService(evtService);
        authService = new AuthService(evtService, netService, storeService);
        pcrudService = new PcrudService(idlService, netService, authService);
        dbStoreService = new DbStoreService();
        orgService = new OrgService(dbStoreService, netService, authService, pcrudService);
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


