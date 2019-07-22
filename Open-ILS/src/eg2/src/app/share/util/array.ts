
/* Utility code for arrays */

export class ArrayUtil {

    // Returns true if the two arrays contain the same values as
    // reported by the provided comparator function or ===
    static equals(arr1: any[], arr2: any[],
        comparator?: (a: any, b: any) => boolean): boolean {

        if (!Array.isArray(arr1) || !Array.isArray(arr2)) {
            return false;
        }

        if (arr1 === arr2) {
            // Same array
            return true;
        }

        if (arr1.length !== arr2.length) {
            return false;
        }

        for (let i = 0; i < arr1.length; i++) {
            if (comparator) {
                if (!comparator(arr1[i], arr2[i])) {
                    return false;
                }
            } else {
                if (arr1[i] !== arr2[i]) {
                    return false;
                }
            }
        }

        return true;
    }
}

