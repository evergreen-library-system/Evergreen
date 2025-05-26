import {DatePipe, DecimalPipe, registerLocaleData} from '@angular/common';
import {IdlService} from './idl.service';
import {EventService} from './event.service';
import {DbStoreService} from './db-store.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';
import {StoreService} from './store.service';
import {OrgService} from './org.service';
import {LocaleService} from './locale.service';
import {FormatService, WS_ORG_TIMEZONE} from './format.service';
import {HatchService} from './hatch.service';
import {SpyLocation} from '@angular/common/testing';
import localeArJO from '@angular/common/locales/ar-JO';
import localeCs from '@angular/common/locales/cs';
import localeFrCA from '@angular/common/locales/fr-CA';
import { TestBed } from '@angular/core/testing';

describe('FormatService', () => {

    let decimalPipe: DecimalPipe;
    let datePipe: DatePipe;
    let idlService: IdlService;
    let netService: NetService;
    let authService: AuthService;
    let pcrudService: PcrudService;
    let orgService: OrgService;
    let evtService: EventService;
    let storeService: StoreService;
    let dbStoreService: DbStoreService;
    let localeService: LocaleService;
    let hatchService: HatchService;
    // eslint-disable-next-line prefer-const
    let location: SpyLocation;
    let service: FormatService;

    beforeEach(() => {
        decimalPipe = new DecimalPipe('en');
        datePipe = new DatePipe('en');
        idlService = new IdlService();
        evtService = new EventService();
        hatchService = new HatchService();
        storeService = new StoreService(null /* CookieService */, hatchService);
        netService = new NetService(evtService);
        authService = new AuthService(evtService, netService, storeService);
        pcrudService = new PcrudService(idlService, null, netService, authService);
        dbStoreService = new DbStoreService();
        orgService = new OrgService(dbStoreService, netService, authService, pcrudService);
        localeService = new LocaleService(location, null, pcrudService);
        TestBed.configureTestingModule({
            providers: [
                {provide: DatePipe, useValue: datePipe},
                {provide: DecimalPipe, useValue: decimalPipe},
                {provide: IdlService, useValue: idlService},
                {provide: OrgService, useValue: orgService},
                {provide: LocaleService, useValue: localeService},
                {provide: WS_ORG_TIMEZONE, useValue: 'America/Chicago'},
            ]
        });
        service = TestBed.inject(FormatService);
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
            value: Date.parse('2018-07-05T12:30:01.000-05:00'),
            datatype: 'timestamp',
        });
        expect(str).toBe('7/5/18');
    });

    it('should format a date plus time', () => {
        initTestData();
        const str = service.transform({
            value: Date.parse('2018-07-05T12:30:01.000-05:00'),
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
        expect(str).toBe('12.10');
    });

    it('should transform M/d/yy, h:mm a Angular format string to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('M/d/yy, h:mm a', 'en-US');
        expect(momentVersion).toBe('M/D/YY, h:mm a');
    });
    it('should transform MMM d, y, h:mm:ss a Angular format string to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('MMM d, y, h:mm:ss a', 'ar-JO');
        expect(momentVersion).toBe('MMM D, Y, h:mm:ss a');
    });
    it('should transform MMMM d, y, h:mm:ss a z Angular format strings to a valid MomentJS one', () => {
        const momentVersion = service['makeFormatParseable']('MMMM d, y, h:mm:ss a z', 'fr-CA');
        expect(momentVersion).toBe('MMMM D, Y, h:mm:ss a [GMT]Z');
    });
    it('should transform full Angular format strings to a valid MomentJS one using Angular locale en-US', () => {
        const momentVersion = service['makeFormatParseable']('full', 'en-US');
        expect(momentVersion).toBe('dddd, MMMM D, Y [at] h:mm:ss a [GMT]Z');
    });
    it('should transform shortDate Angular format strings to a valid MomentJS one using Angular locale cs-CZ', () => {
        registerLocaleData(localeCs);
        const momentVersion = service['makeFormatParseable']('shortDate', 'cs-CZ');
        expect(momentVersion).toBe('DD.MM.YY');
    });
    it('should transform mediumDate Angular format strings to a valid MomentJS one using Angular locale fr-CA', () => {
        registerLocaleData(localeFrCA);
        const momentVersion = service['makeFormatParseable']('mediumDate', 'fr-CA');
        expect(momentVersion).toBe('D MMM Y');
    });
    it('should transform long Angular format strings to a valid MomentJS one using Angular locale ar-JO', () => {
        registerLocaleData(localeArJO);
        const momentVersion = service['makeFormatParseable']('long', 'ar-JO');
        expect(momentVersion).toBe('D MMMM Y في h:mm:ss a [GMT]Z');
    });
    it('can create a valid Momentjs object given a valid datetime string and correct format', () => {
        const moment = service['momentize']('7/3/12, 6:06 PM', 'M/D/YY, h:mm a', 'Africa/Addis_Ababa', false);
        expect(moment.isValid()).toBe(true);
    });
    it('can create a valid Momentjs object given a valid datetime string and a dateTimeFormat from org settings', () => {
        service['dateTimeFormat'] = 'M/D/YY, h:mm a';
        const moment = service.momentizeDateTimeString('7/3/12, 6:06 PM', 'Africa/Addis_Ababa', false, 'fr-CA');
        expect(moment.isValid()).toBe(true);
    });
    it('can momentize ISO strings', () => {
        const moment = service.momentizeIsoString('2022-07-29T17:56:00.000Z', 'America/New_York');
        expect(moment.isValid()).toBe(true);
        expect(moment.format('YYYY')).toBe('2022');
    });

});

