const koffi = require('koffi');
const path = require('path');

// --- Titan One GCAPI Constants ---
const GCAPI_OUTPUT_TOTAL = 36;

// Nintendo Switch button indexes (from gcapi.h)
const SWITCH = {
  HOME: 0, MINUS: 1, PLUS: 2,
  R: 3, ZR: 4, SR: 5,
  L: 6, ZL: 7, SL: 8,
  RX: 9, RY: 10, LX: 11, LY: 12,
  UP: 13, DOWN: 14, LEFT: 15, RIGHT: 16,
  X: 17, A: 18, B: 19, Y: 20,
  ACCX: 21, ACCY: 22, ACCZ: 23,
  GYROX: 24, GYROY: 25, GYROZ: 26,
  CAPTURE: 27
};

// Console output states
const CONSOLE_DISCONNECTED = 0;
const CONSOLE_SWITCH = 5;

// --- Load DLL ---
const dllPath = path.join(__dirname, '..', 'Gtuner3', 'gcdapi.dll');
console.log(`Loading DLL: ${dllPath}`);
const lib = koffi.load(dllPath);

// --- Bind functions (stdcall convention) ---
const gcdapi_Load       = lib.stdcall('gcdapi_Load', 'uint8_t', []);
const gcdapi_Unload     = lib.stdcall('gcdapi_Unload', 'void', []);
const gcapi_IsConnected = lib.stdcall('gcapi_IsConnected', 'uint8_t', []);
const gcapi_Write       = lib.stdcall('gcapi_Write', 'uint8_t', ['pointer']);
const gcapi_GetFWVer    = lib.stdcall('gcapi_GetFWVer', 'uint16_t', []);

// --- Helper: create an output buffer ---
function makeOutput() {
  // int8_t array of GCAPI_OUTPUT_TOTAL, all zeros = all buttons released
  return Buffer.alloc(GCAPI_OUTPUT_TOTAL, 0);
}

// --- Helper: sleep ---
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// --- Main ---
async function main() {
  // 1. Initialize the API
  console.log('Initializing GCDAPI...');
  const loadResult = gcdapi_Load();
  if (!loadResult) {
    console.error('ERROR: gcdapi_Load() failed. Is Gtuner running and the device plugged in?');
    process.exit(1);
  }
  console.log('GCDAPI loaded successfully.');

  // 2. Check connection
  const connected = gcapi_IsConnected();
  if (!connected) {
    console.error('ERROR: No Titan One device detected. Make sure it is connected and Gtuner is NOT using it exclusively.');
    gcdapi_Unload();
    process.exit(1);
  }

  const fw = gcapi_GetFWVer();
  console.log(`Device connected! Firmware version: ${fw}`);

  // 3. Press B button
  console.log('\nPressing Nintendo Switch B button...');
  const output = makeOutput();
  output.writeInt8(100, SWITCH.B);  // 100 = fully pressed
  const writeOk = gcapi_Write(output);
  console.log(`Write result (press): ${writeOk ? 'OK' : 'FAILED'}`);

  // 4. Hold for 200ms
  await sleep(200);

  // 5. Release B button (send all zeros)
  console.log('Releasing B button...');
  const release = makeOutput();
  const releaseOk = gcapi_Write(release);
  console.log(`Write result (release): ${releaseOk ? 'OK' : 'FAILED'}`);

  // 6. Cleanup
  console.log('\nUnloading GCDAPI...');
  gcdapi_Unload();
  console.log('Done!');
}

main().catch(err => {
  console.error('Unexpected error:', err);
  try { gcdapi_Unload(); } catch {}
  process.exit(1);
});
