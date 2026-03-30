import 'web_plugin_registrant_stub.dart'
    if (dart.library.html) 'web_plugin_registrant_web.dart';

/// Registers Flutter web platform plugins (record, url_launcher, etc.).
void registerPlugins() => registerWebPlugins();
