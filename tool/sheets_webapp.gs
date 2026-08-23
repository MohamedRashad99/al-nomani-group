const SPREADSHEET_ID = '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I';
const WRITE_TOKEN = 'nomani-sheet-2026';

function doPost(e) {
  try {
    const raw = e.postData && e.postData.contents ? e.postData.contents : '{}';
    const body = JSON.parse(raw);
    if (body.token !== WRITE_TOKEN) {
      return _json({ ok: false, error: 'unauthorized' });
    }
    const spreadsheetId = body.spreadsheetId || SPREADSHEET_ID;
    const sections = body.sections || {};
    const ss = SpreadsheetApp.openById(spreadsheetId);
    Object.keys(sections).forEach(function (title) {
      const values = sections[title] || [];
      let sheet = ss.getSheetByName(title);
      if (!sheet) {
        sheet = ss.insertSheet(title);
      }
      sheet.clearContents();
      if (values.length) {
        sheet
          .getRange(1, 1, values.length, values[0].length)
          .setValues(values);
      }
    });
    return _json({ ok: true, tabs: Object.keys(sections).length });
  } catch (error) {
    return _json({ ok: false, error: String(error) });
  }
}

function doGet() {
  return _json({ ok: true, service: 'al-nomani-sheets' });
}

function _json(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(
    ContentService.MimeType.JSON,
  );
}
