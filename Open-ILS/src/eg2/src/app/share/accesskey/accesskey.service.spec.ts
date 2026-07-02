import { fakeAsync, tick } from '@angular/core/testing';
import { AccessKeyAssignment, AccessKeyService } from './accesskey.service';

const mockKeyEvent = (partial: Partial<KeyboardEvent> = {}): KeyboardEvent => ({
    key: 'a', ctrlKey: false, altKey: false, shiftKey: false,
    preventDefault: () => {},
    ...partial
} as unknown as KeyboardEvent);

const mockAssignment = (
    partial: Partial<AccessKeyAssignment> = {}
): AccessKeyAssignment => ({
    key: 'ctrl+a', desc: 'Do something', ctx: 'base', action: () => {},
    ...partial
});

let service: AccessKeyService;

describe('AccessKeyService', () => {
    beforeEach(() => {
        service = new AccessKeyService();
    });

    describe('assign', () => {
        it('stores assignment', () => {
            const assignment = mockAssignment();
            service.assign(assignment);
            expect(service.assignments).toEqual([assignment]);
        });

        it('replaces assignment if same key and context', () => {
            const original = mockAssignment();
            const desc = `${original.desc} else`;
            const replacement = mockAssignment({ desc });

            service.assign(original);
            service.assign(replacement);

            expect(service.assignments).toEqual([replacement]);
        });

        it('shadows assignment if same key and different context', () => {
            const shadowed = mockAssignment();
            const ctx = `not ${shadowed.ctx}`;
            const active = mockAssignment({ ctx });

            service.assign(shadowed);
            service.assign(active);

            expect(service.assignments.length).toBe(2);
            expect(service.assignments[0]).toBe(active);
            expect(service.assignments[1]).toBe(shadowed);
            expect(service.assignments[1].shadowed).toBeTrue();
        });
    });

    describe('compressKeys', () => {
        it('returns null when key is falsy', () => {
            const event = mockKeyEvent({ key: '' });
            expect(service.compressKeys(event)).toBeNull();
        });

        it('prefixes compressed string with ctrl', () => {
            const ctrl = mockKeyEvent({ ctrlKey: true });
            const meta = mockKeyEvent({ ctrlKey: true });
            expect(service.compressKeys(ctrl)).toBe(`ctrl+${ctrl.key}`);
            expect(service.compressKeys(meta)).toBe(`ctrl+${meta.key}`);
        });

        it('prefixes compressed string with alt', () => {
            const event = mockKeyEvent({ altKey: true });
            expect(service.compressKeys(event)).toBe(`alt+${event.key}`);
        });

        it('prefixes compressed string with shift', () => {
            const event = mockKeyEvent({ shiftKey: true });
            expect(service.compressKeys(event)).toBe(`shift+${event.key}`);
        });

        it('lowercases compressed string key', () => {
            const event = mockKeyEvent({ key: 'A' });
            expect(service.compressKeys(event)).toBe('a');
        });
    });

    describe('fire', () => {
        it('fires the matching action', fakeAsync(() => {
            const action = jasmine.createSpy('action');
            const nonMatchingAction = jasmine.createSpy('nonMatchingAction');

            const matching = mockAssignment(
                { key: 'ctrl+a', action }
            );
            const nonMatching = mockAssignment(
                { key:'ctrl+b', action: nonMatchingAction }
            );

            service.assign(matching);
            service.assign(nonMatching);

            const event = mockKeyEvent({ key: 'a', ctrlKey: true });
            service.fire(event);

            tick();

            expect(nonMatchingAction).not.toHaveBeenCalled();
            expect(action).toHaveBeenCalled();
        }));
    });

    describe('infoIze', () => {
        it('returns assignments without actions', () => {
            const shadowed = false;
            const assignment = mockAssignment({ shadowed });
            const { key, desc, ctx } = assignment;
            service.assign(assignment);

            const info = service.infoIze();
            expect(info.length).toBe(1);
            expect(info[0]).toEqual({ key, desc, ctx, shadowed });
        });
    });
});
