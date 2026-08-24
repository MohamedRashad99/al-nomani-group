export 'pwa_install_stub.dart'
    if (dart.library.html) 'pwa_install_web.dart'
    if (dart.library.io) 'pwa_install_io.dart';
