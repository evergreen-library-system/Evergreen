import { ServerStoreService } from '@eg/core/server-store.service';
import { LinkTargetService } from './link-target.service';
import { fakeAsync, flushMicrotasks, TestBed } from '@angular/core/testing';

interface TestContext {
    store: jasmine.SpyObj<ServerStoreService>;
    service: LinkTargetService;
}

const DISABLE_NEW_TABS_KEY = 'ui.staff.disable_links_newtabs';

function createTestContext(initialSetting: boolean | null): TestContext {
    const store = jasmine.createSpyObj<ServerStoreService>(['getItem', 'setItem']);
    store.getItem.and.returnValue(Promise.resolve(initialSetting));
    store.setItem.and.callFake((_, value) => {
        return Promise.resolve(value);
    });

    TestBed.configureTestingModule({
        providers: [
            LinkTargetService,
            { provide: ServerStoreService, useValue: store }
        ]
    });
    const service = TestBed.inject(LinkTargetService);

    return { store, service };
}

describe('LinkTargetService', () => {
    describe('newTabsDisabled$', () => {
        it('should get and multicast the setting value', fakeAsync(() => {
            const { store, service } = createTestContext(true);

            const sub1: boolean[] = [];
            const sub2: boolean[] = [];
            service.newTabsDisabled$.subscribe(value => sub1.push(value));
            service.newTabsDisabled$.subscribe(value => sub2.push(value));
            flushMicrotasks();

            expect(store.getItem).toHaveBeenCalledOnceWith(DISABLE_NEW_TABS_KEY);
            expect(sub1).toEqual([true]);
            expect(sub2).toEqual([true]);
        }));
    });

    describe('disableNewTabs()', () => {
        it('should enable the setting and emit true', fakeAsync(() => {
            const { store, service } = createTestContext(null);

            const values: boolean[] = [];
            service.newTabsDisabled$.subscribe(value => values.push(value));
            flushMicrotasks();
            service.disableNewTabs();
            flushMicrotasks();

            expect(store.setItem).toHaveBeenCalledWith(DISABLE_NEW_TABS_KEY, true);
            expect(values).toEqual([false, true]);
        }));
    });

    describe('enableNewTabs()', () => {
        it('should remove the setting and emit false', fakeAsync(() => {
            const { store, service } = createTestContext(true);

            const values: boolean[] = [];
            service.newTabsDisabled$.subscribe(value => values.push(value));
            flushMicrotasks();
            service.enableNewTabs();
            flushMicrotasks();

            expect(store.setItem).toHaveBeenCalledWith(DISABLE_NEW_TABS_KEY, null);
            expect(values).toEqual([true, false]);
        }));
    });
});
