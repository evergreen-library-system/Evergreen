import {DatePipe, CurrencyPipe} from '@angular/common';
import {IdlService} from './idl.service';
import {EventService} from './event.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';
import {StoreService} from './store.service';
import {OrgService} from './org.service';
import {FormatService} from './format.service';


describe('FormatService', () => {

    let currencyPipe: CurrencyPipe;
    let datePipe: DatePipe;
    let idlService: IdlService;
    let netService: NetService;
    let authService: AuthService;
    let pcrudService: PcrudService;
    let orgService: OrgService;
    let evtService: EventService;
    let storeService: StoreService;
    let service: FormatService;

    beforeEach(() => {
        currencyPipe = new CurrencyPipe('en');
        datePipe = new DatePipe('en');
        idlService = new IdlService();
        evtService = new EventService();
        storeService = new StoreService(null /* CookieService */);
        netService = new NetService(evtService);
        authService = new AuthService(evtService, netService, storeService);
        pcrudService = new PcrudService(idlService, netService, authService);
        orgService = new OrgService(netService, authService, pcrudService);
        service = new FormatService(
            datePipe,
            currencyPipe,
            idlService,
            orgService
        );
    });

    const initTestData = () => {
        idlService.parseIdl();
        const win: any = window; // trick TS
        win._eg_mock_data.generateOrgTree(idlService, orgService);
    };

    it('should format an org unit name', () => {
        initTestData();
        const str = service.transform({
            value: orgService.root(),
            datatype: 'org_unit',
            orgField: 'shortname' // currently the default
        });
        expect(str).toBe('ROOT');  // from eg_mock.js
    });

    it('should format a date', () => {
        initTestData();
        const str = service.transform({
            value: new Date(2018, 6, 5),
            datatype: 'timestamp',
        });
        expect(str).toBe('7/5/18');
    });

    it('should format a date plus time', () => {
        initTestData();
        const str = service.transform({
            value: new Date(2018, 6, 5, 12, 30, 1),
            datatype: 'timestamp',
            datePlusTime: true
        });
        expect(str).toBe('7/5/18, 12:30 PM');
    });



    it('should format money', () => {
        initTestData();
        const str = service.transform({
            value: '12.1',
            datatype: 'money'
        });
        expect(str).toBe('$12.10');
    });

    it('should transform M/d/yy, h:mm a Angular format string to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('M/d/yy, h:mm a');
        expect(momentVersion).toBe('M/D/YY, h:mm a');
    });
    it('should transform MMM d, y, h:mm:ss a Angular format string to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('MMM d, y, h:mm:ss a');
        expect(momentVersion).toBe('MMM D, Y, h:mm:ss a');
    });
    it('should transform MMMM d, y, h:mm:ss a z Angular format strings to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('MMMM d, y, h:mm:ss a z');
        expect(momentVersion).toBe('MMMM D, Y, h:mm:ss a [GMT]Z');
    });
    it('should transform full Angular format strings to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('full');
        expect(momentVersion).toBe('dddd, MMMM D, Y, h:mm:ss a [GMT]Z');
    });
    it('can create a valid Momentjs object given a valid datetime string and correct format', () => {
        const moment = service['momentize']('7/3/12, 6:06 PM', 'M/D/YY, h:mm a', 'Africa/Addis_Ababa', false);
        expect(moment.isValid()).toBe(true);
    });
    it('can create a valid Momentjs object given a valid datetime string and a dateTimeFormat from org settings', () => {
        service['dateTimeFormat'] = 'M/D/YY, h:mm a';
        const moment = service.momentizeDateTimeString('7/3/12, 6:06 PM', 'Africa/Addis_Ababa', false);
        expect(moment.isValid()).toBe(true);
    });

});

