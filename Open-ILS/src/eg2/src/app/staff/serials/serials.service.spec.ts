import { MockGenerators } from 'test_data/mock_generators';
import { SerialsService } from './serials.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { TestBed } from '@angular/core/testing';
import { switchMap } from 'rxjs';
import { StoreService } from '@eg/core/store.service';
import { OrgService } from '@eg/core/org.service';

const mockCallNumber = MockGenerators.idlObject({
    id: 12,
    label: 'MAGAZINES',
    prefix: null,
    suffix: MockGenerators.idlObject({id: 7, label: 'DOWNSTAIRS'})
});

const mockPcrud = MockGenerators.pcrudService({search: [mockCallNumber]});

describe('SerialsService', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({ providers: [
            SerialsService,
            {useValue: MockGenerators.storeService(null), provide: StoreService},
            { provide: PcrudService, useValue: mockPcrud },
            { provide: OrgService, useValue: MockGenerators.orgService() }
        ] });
    });
    describe('callNumbersAsComboboxEntries$()', () => {
        it('returns an array of combobox entries', () => {
            const serialsService = TestBed.inject(SerialsService);
            serialsService.callNumbersAsComboboxEntries$(10, 3).subscribe(callNumbers => {
                expect(callNumbers).toEqual(
                    [
                        {id: 12, label: 'MAGAZINES'}
                    ]
                );
            });
        });
        it('caches the pcrud call', () => {
            mockPcrud.search.calls.reset();
            const serialsService = TestBed.inject(SerialsService);
            const getArrayThreeTimes$ =
                serialsService.callNumbersAsComboboxEntries$(10, 3).pipe(
                    switchMap(() => serialsService.callNumbersAsComboboxEntries$(10, 3)),
                    switchMap(() => serialsService.callNumbersAsComboboxEntries$(10, 3))
                );
            getArrayThreeTimes$.subscribe(() => {
                expect(mockPcrud.search).toHaveBeenCalledTimes(1);
            });
        });
    });
    describe('defaultCallNumberPrefix$()', () => {
        it('returns null if no prefix on most recent call number', () => {
            const serialsService = TestBed.inject(SerialsService);
            serialsService.defaultCallNumberPrefix$(10, 3).subscribe(prefix => {
                expect(prefix).toBeNull();
            });
        });
    });
    describe('defaultCallNumber$()', () => {
        it('returns the most recent call number as a combobox entry', () => {
            const serialsService = TestBed.inject(SerialsService);
            serialsService.defaultCallNumber$(10, 3).subscribe(callNumber => {
                expect(callNumber).toEqual({id: 12, label: 'MAGAZINES'});
            });
        });
    });
    describe('defaultCallNumberSuffix$()', () => {
        it('returns the suffix attached to the most recent call number', () => {
            const serialsService = TestBed.inject(SerialsService);
            serialsService.defaultCallNumberSuffix$(10, 3).subscribe(suffix => {
                expect(suffix).toEqual({id: 7, label: 'DOWNSTAIRS'});
            });
        });
    });
    describe('shouldShowCallNumberAffixes()', () => {
        describe('when no user preference has been stored', () => {
            it('returns true', () => {
                const serialsService = TestBed.inject(SerialsService);
                expect(serialsService.shouldShowCallNumberAffixes()).toBeTrue();
            });
        });
        describe('when a false preference has been stored', () => {
            beforeEach(() => {
                TestBed.configureTestingModule({ providers: [
                    SerialsService,
                    {useValue: MockGenerators.storeService(false), provide: StoreService},
                    { provide: PcrudService, useValue: mockPcrud },
                    { provide: OrgService, useValue: MockGenerators.orgService() }
                ] });
            });
            it('returns false', () => {
                const serialsService = TestBed.inject(SerialsService);
                expect(serialsService.shouldShowCallNumberAffixes()).toBeFalse();
            });
        });
        describe('when a true preference has been stored', () => {
            beforeEach(() => {
                TestBed.configureTestingModule({ providers: [
                    SerialsService,
                    {useValue: MockGenerators.storeService(true), provide: StoreService},
                    { provide: PcrudService, useValue: mockPcrud },
                    { provide: OrgService, useValue: MockGenerators.orgService() }
                ] });
            });
            it('returns true', () => {
                const serialsService = TestBed.inject(SerialsService);
                expect(serialsService.shouldShowCallNumberAffixes()).toBeTrue();
            });
        });
    });
});
