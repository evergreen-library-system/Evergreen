import {ArrayUtil} from './array';

describe('ArrayUtil', () => {

    const arr1 = [1, '2', true, undefined, null];
    const arr2 = [1, '2', true, undefined, null];
    const arr3 = [1, '2', true, undefined, null, 'foo'];
    const arr4 = [[1, 2, 3], [4, 3, 2]];
    const arr5 = [[1, 2, 3], [4, 3, 2]];
    const arr6 = [[1, 2, 3], [1, 2, 3]];

    it('Compare matching arrays', () => {
        expect(ArrayUtil.equals(arr1, arr2)).toBe(true);
    });

    it('Compare non-matching arrays', () => {
        expect(ArrayUtil.equals(arr1, arr3)).toBe(false);
    });

    // Using ArrayUtil.equals as a comparator -- testception!
    it('Compare matching arrays with comparator', () => {
        expect(ArrayUtil.equals(arr4, arr5, ArrayUtil.equals)).toBe(true);
    });

    it('Compare non-matching arrays with comparator', () => {
        expect(ArrayUtil.equals(arr5, arr6, ArrayUtil.equals)).toBe(false);
    });

});
