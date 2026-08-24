enum PwaInstallResult { installed, alreadyInstalled, iosInstructions, unavailable }

void ensurePwaInstallListener() {}

bool isPwaStandalone() => false;

Future<PwaInstallResult> promptPwaInstall() async =>
    PwaInstallResult.unavailable;
