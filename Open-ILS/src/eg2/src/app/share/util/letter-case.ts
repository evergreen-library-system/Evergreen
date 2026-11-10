export function upcaseFirst(string: string): string {
    if (string.length) {
        return string.charAt(0).toLocaleUpperCase() + string.slice(1);
    } else {
        return '';
    }
}
