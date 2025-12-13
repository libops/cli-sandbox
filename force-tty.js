Object.defineProperty(process.stdin, 'isTTY', {
    value: true,
    writable: false,
    enumerable: true,
    configurable: true
});

Object.defineProperty(process.stdout, 'isTTY', {
    value: true,
    writable: false,
    enumerable: true,
    configurable: true
});

process.stdout.columns = process.env.COLUMNS ? parseInt(process.env.COLUMNS) : 80;
process.stdout.rows = process.env.ROWS ? parseInt(process.env.ROWS) : 24;

if (!process.stdin.setRawMode) {
    process.stdin.setRawMode = () => {};
}
