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
      });
    return modelPromise;
  }

  global.nomaniClassifyImage = function (dataUrl) {
    return ensureModel().then(function (model) {
      return new Promise(function (resolve, reject) {
        var image = new Image();
        image.crossOrigin = 'anonymous';
        image.onload = function () {
          model
            .classify(image, 5)
            .then(function (preds) {
              resolve(
                preds.map(function (item) {
                  return {
                    text: item.className,
                    confidence: item.probability,
                  };
                }),
              );
            })
            .catch(reject);
        };
        image.onerror = reject;
        image.src = dataUrl;
      });
    });
  };
})(window);
