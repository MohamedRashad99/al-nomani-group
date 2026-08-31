(function (global) {
  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      if (document.querySelector('script[src="' + src + '"]')) {
        resolve();
        return;
      }
      var script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.onload = function () { resolve(); };
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  var modelPromise = null;
  function ensureModel() {
    if (modelPromise) return modelPromise;
    modelPromise = loadScript(
      'https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0/dist/tf.min.js',
    )
      .then(function () {
        return loadScript(
          'https://cdn.jsdelivr.net/npm/@tensorflow-models/mobilenet@2.1.1/dist/mobilenet.min.js',
        );
      })
      .then(function () {
        return global.mobilenet.load({ version: 2, alpha: 0.5 });
      })
      .catch(function () {
        modelPromise = null;
        return null;
      });
    return modelPromise;
  }

  var ocrPromise = null;
  function ensureOcr() {
    if (ocrPromise) return ocrPromise;
    ocrPromise = loadScript(
      'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js',
    )
      .then(function () {
        if (!global.Tesseract || !global.Tesseract.createWorker) {
          throw new Error('tesseract');
        }
        return global.Tesseract.createWorker('ara+eng');
      })
      .catch(function () {
        ocrPromise = null;
        return null;
      });
    return ocrPromise;
  }

  function classifyImage(model, dataUrl) {
    if (!model) return Promise.resolve([]);
    return new Promise(function (resolve) {
      var image = new Image();
      image.crossOrigin = 'anonymous';
      image.onload = function () {
        model
          .classify(image, 5)
          .then(function (preds) {
            resolve(
              (preds || []).map(function (item) {
                return {
                  text: item.className,
                  confidence: item.probability,
                };
              }),
            );
          })
          .catch(function () { resolve([]); });
      };
      image.onerror = function () { resolve([]); };
      image.src = dataUrl;
    });
  }

  var packRe = /([\d]+(?:[.,]\d+)?)\s*(ml|ملل?|مليلتر|l|ltr|لتر|liter|litre|kg|كجم|كغ|كيلو|g|جم|غرام)/i;

  function parsePack(text) {
    var match = String(text || '').match(packRe);
    if (!match) return null;
    var unitRaw = match[2].toLowerCase();
    var unit = 'ml';
    if (/l|لتر|liter|litre/.test(unitRaw) && !/ml|مل/.test(unitRaw)) unit = 'l';
    else if (/kg|كجم|كغ|كيلو/.test(unitRaw)) unit = 'kg';
    else if (/g|جم|غرام/.test(unitRaw) && !/kg|كج/.test(unitRaw)) unit = 'g';
    return { size: match[1].replace(',', '.'), unit: unit };
  }

  global.nomaniReadProductImage = function (dataUrl) {
    return Promise.all([ensureModel(), ensureOcr()]).then(function (parts) {
      var model = parts[0];
      var worker = parts[1];
      var labelsTask = classifyImage(model, dataUrl);
      var textTask = worker
        ? worker.recognize(dataUrl).then(function (result) {
            return (result && result.data && result.data.text) || '';
          }).catch(function () { return ''; })
        : Promise.resolve('');
      return Promise.all([labelsTask, textTask]).then(function (out) {
        var labels = out[0] || [];
        var text = String(out[1] || '').replace(/\s+/g, ' ').trim();
        var pack = parsePack(text);
        if (text) {
          labels = [{ text: text, confidence: 0.92 }].concat(labels);
        }
        return {
          labels: labels,
          text: text,
          packageSize: pack ? pack.size : '',
          unitOfMeasure: pack ? pack.unit : '',
        };
      });
    });
  };

  global.nomaniClassifyImage = function (dataUrl) {
    return global.nomaniReadProductImage(dataUrl).then(function (result) {
      return result.labels || [];
    });
  };
})(window);
