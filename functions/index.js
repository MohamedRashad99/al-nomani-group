const {onRequest} = require('firebase-functions/v2/https');
const {google} = require('googleapis');
const fs = require('fs');
const path = require('path');

const SPREADSHEET_ID = '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I';
const WRITE_TOKEN = 'nomani-sheet-2026';

function loadServiceAccount() {
  if (process.env.GOOGLE_SERVICE_ACCOUNT_JSON) {
    return JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  }
  const file = path.join(__dirname, 'service-account.json');
  if (fs.existsSync(file)) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  }
  throw new Error('Missing Google service account');
}

function parseBody(req) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return req.body;
  }
  const raw = Buffer.isBuffer(req.body)
    ? req.body.toString('utf8')
    : typeof req.body === 'string'
      ? req.body
      : typeof req.rawBody === 'string'
        ? req.rawBody
        : '';
  return raw ? JSON.parse(raw) : {};
}

async function writeSections(spreadsheetId, sections) {
  const sa = loadServiceAccount();
  const auth = new google.auth.JWT(
    sa.client_email,
    undefined,
    sa.private_key,
    ['https://www.googleapis.com/auth/spreadsheets'],
  );
  const sheets = google.sheets({version: 'v4', auth});
  const meta = await sheets.spreadsheets.get({spreadsheetId});
  const existing = new Set(
    (meta.data.sheets || [])
      .map((sheet) => sheet.properties && sheet.properties.title)
      .filter(Boolean),
  );
  const add = Object.keys(sections)
    .filter((title) => !existing.has(title))
    .map((title) => ({addSheet: {properties: {title}}}));
  if (add.length) {
    await sheets.spreadsheets.batchUpdate({
      spreadsheetId,
      requestBody: {requests: add},
    });
  }
  for (const [title, values] of Object.entries(sections)) {
    const range = `'${title}'!A:ZZ`;
    await sheets.spreadsheets.values.clear({spreadsheetId, range});
    if (Array.isArray(values) && values.length) {
      await sheets.spreadsheets.values.update({
        spreadsheetId,
        range,
        valueInputOption: 'RAW',
        requestBody: {values},
      });
    }
  }
}

exports.writeSheet = onRequest(
  {cors: true, timeoutSeconds: 120, memory: '512MiB', invoker: 'public'},
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method === 'GET') {
      res.status(200).json({ok: true, service: 'al-nomani-sheets'});
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ok: false, error: 'method'});
      return;
    }
    try {
      const body = parseBody(req);
      if (body.token !== WRITE_TOKEN) {
        res.status(401).json({ok: false, error: 'unauthorized'});
        return;
      }
      const sections = body.sections || {};
      await writeSections(body.spreadsheetId || SPREADSHEET_ID, sections);
      res.status(200).json({ok: true, tabs: Object.keys(sections).length});
    } catch (error) {
      res.status(500).json({ok: false, error: String(error && error.message || error)});
    }
  },
);
