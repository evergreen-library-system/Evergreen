import { noSuch } from './no-such';

describe('noSuch', () => {
    it('returns true if array is empty', () => {
        const data = [];
        expect(noSuch((element) => element === 'dog')(data)).toBeTrue();
    });
    it('returns true if array has one non-matching element', () => {
        const data = ['crab'];
        expect(noSuch((element) => element === 'dog')(data)).toBeTrue();
    });
    it('returns true if array has many non-matching elements', () => {
        const data = ['crab', 'lobster', 'orca'];
        expect(noSuch((element) => element === 'dog')(data)).toBeTrue();
    });
    it('returns false if array has one matching elements', () => {
        const data = ['dog'];
        expect(noSuch((element) => element === 'dog')(data)).toBeFalse();
    });
    it('returns false if array has many matching elements', () => {
        const data = ['dog', 'dog', 'dog'];
        expect(noSuch((element) => element === 'dog')(data)).toBeFalse();
    });
    it('returns false if array has a mix of matching and non-matching elements', () => {
        const data = ['lobster', 'dog', 'crab', 'dog'];
        expect(noSuch((element) => element === 'dog')(data)).toBeFalse();
    });
});
